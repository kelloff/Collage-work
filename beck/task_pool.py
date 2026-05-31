"""
Предзагруженный пул заданий на диске: выдача без ожидания LLM, фоновое пополнение.
Включение: TASK_POOL_ENABLED=1 (по умолчанию). Файл: TASK_POOL_PATH (tasks_pool.json рядом с beck).
"""
from __future__ import annotations

import json
import os
import threading
import time
from collections import defaultdict
from contextlib import contextmanager
from typing import Any, Callable, Dict, Generator, List, Optional

POOL_PATH = os.getenv(
    "TASK_POOL_PATH",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "tasks_pool.json"),
)
# Целевой запас на диске (не «за ночь»): пока total < MIN — фоновый refill.
POOL_MIN_TOTAL = int(os.getenv("TASK_POOL_MIN_TOTAL", "300"))
POOL_MAX_TOTAL = int(os.getenv("TASK_POOL_MAX_TOTAL", "320"))
POOL_TARGET_PER_LEVEL = int(os.getenv("TASK_POOL_TARGET_PER_LEVEL", "75"))
ENABLED = os.getenv("TASK_POOL_ENABLED", "1") == "1"
REFILL_RETRY_SEC = int(os.getenv("TASK_POOL_REFILL_RETRY_SEC", "90"))
REFILL_PAUSE_SEC = float(os.getenv("TASK_POOL_REFILL_PAUSE_SEC", "2"))
REFILL_ZERO_ADDED_WAIT_SEC = int(os.getenv("TASK_POOL_REFILL_ZERO_ADDED_WAIT", "8"))
REFILL_MAX_EMPTY_STREAK = int(os.getenv("TASK_POOL_REFILL_MAX_EMPTY_STREAK", "48"))
REFILL_GAVE_UP_RESTART_SEC = int(os.getenv("TASK_POOL_REFILL_GAVE_UP_RESTART_SEC", "600"))
REFILL_SKIP_LEVEL_AFTER = int(os.getenv("TASK_POOL_REFILL_SKIP_LEVEL_AFTER", "8"))

_lock = threading.Lock()
_refill_lock = threading.Lock()
_buckets: Dict[int, List[dict]] = defaultdict(list)
_refill_fn: Optional[Callable[[], List[dict]]] = None
_check_lock = threading.Lock()
_check_active_count = 0
_refill_level_miss: Dict[int, int] = {}


def refill_target_total() -> int:
    return POOL_MIN_TOTAL


def set_refill_fn(fn: Callable[[], List[dict]]) -> None:
    global _refill_fn
    _refill_fn = fn


def _prune_date_tasks_unlocked() -> int:
    from task_filters import is_date_related_task

    removed = 0
    for lv in list(_buckets.keys()):
        kept = [t for t in _buckets[lv] if not is_date_related_task(t)]
        removed += len(_buckets[lv]) - len(kept)
        _buckets[lv] = kept
    return removed


def _prune_invalid_playable_unlocked() -> int:
    from task_filters import is_valid_playable_task

    removed = 0
    for lv in list(_buckets.keys()):
        kept: List[dict] = []
        for t in _buckets[int(lv)]:
            if is_valid_playable_task(t, int(lv)):
                kept.append(t)
            else:
                removed += 1
        _buckets[int(lv)] = kept
    return removed


def _prune_similar_tasks_unlocked() -> int:
    import task_diversity

    removed = 0
    for lv in list(_buckets.keys()):
        kept: List[dict] = []
        for t in _buckets[lv]:
            if task_diversity.can_accept_task(t, kept, None):
                kept.append(t)
            else:
                removed += 1
        _buckets[lv] = kept
    return removed


def load() -> None:
    global _buckets
    _buckets = defaultdict(list)
    if not os.path.isfile(POOL_PATH):
        return
    try:
        with open(POOL_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"task_pool.load: failed {POOL_PATH}: {e}")
        return
    flat: List[Any]
    if isinstance(data, list):
        flat = data
    elif isinstance(data, dict) and "tasks" in data:
        flat = data["tasks"]
    else:
        return
    for t in flat:
        if not isinstance(t, dict):
            continue
        try:
            lv = int(t.get("level", 0))
        except Exception:
            continue
        _buckets[lv].append(t)
    removed = _prune_date_tasks_unlocked()
    if removed:
        print(f"task_pool.load: pruned {removed} date-related tasks")
    dup = 0
    if os.getenv("TASK_POOL_PRUNE_SIMILAR_ON_LOAD", "1") != "0":
        dup = _prune_similar_tasks_unlocked()
        if dup:
            print(f"task_pool.load: pruned {dup} similar/duplicate-topic tasks")
    bad = _prune_invalid_playable_unlocked()
    if bad:
        print(f"task_pool.load: pruned {bad} incoherent/unplayable tasks")
    if removed or dup or bad:
        save_unlocked()


def save_unlocked() -> None:
    flat: List[dict] = []
    for lv in sorted(_buckets.keys()):
        flat.extend(_buckets[lv])
    tmp = POOL_PATH + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(flat, f, ensure_ascii=False)
        os.replace(tmp, POOL_PATH)
    except Exception as e:
        print(f"task_pool.save: {e}")


def total_unlocked() -> int:
    return sum(len(v) for v in _buckets.values())


def snapshot_unlocked() -> List[dict]:
    flat: List[dict] = []
    for lv in sorted(_buckets.keys()):
        for t in _buckets[lv]:
            flat.append(dict(t))
    return flat


def snapshot_tasks() -> List[dict]:
    with _lock:
        return snapshot_unlocked()


def try_pop_batch(levels: List[int], count_per_level: int) -> Optional[List[dict]]:
    """
    Забирает по count_per_level задач с каждого уровня из levels.
    Если хотя бы одного уровня не хватает — None (без частичной выдачи).
    """
    if not ENABLED or not levels or count_per_level <= 0:
        return None
    with _lock:
        for lv in levels:
            if len(_buckets[lv]) < count_per_level:
                return None
        out: List[dict] = []
        for lv in levels:
            for _ in range(count_per_level):
                out.append(_buckets[lv].pop(0))
        save_unlocked()
        return out


def try_pop_partial_batch(levels: List[int], count_per_level: int) -> List[dict]:
    """Забирает до count_per_level задач с каждого уровня — сколько есть в пуле."""
    if not ENABLED or not levels or count_per_level <= 0:
        return []
    with _lock:
        out: List[dict] = []
        changed = False
        for lv in levels:
            lv_i = int(lv)
            take = min(count_per_level, len(_buckets[lv_i]))
            for _ in range(take):
                out.append(_buckets[lv_i].pop(0))
            if take > 0:
                changed = True
        if changed:
            save_unlocked()
        return out


def try_pop_for_level(level: int, count: int) -> List[dict]:
    return try_pop_partial_batch([int(level)], count)


def pick_level_for_refill(levels: List[int]) -> Optional[int]:
    """Уровень с наименьшим запасом; застрявшие (N пустых батчей) временно пропускаются."""
    below: list[tuple[int, int, int]] = []
    for lvl in levels:
        lv = int(lvl)
        cur = count_by_level(lv)
        if cur >= POOL_TARGET_PER_LEVEL:
            continue
        below.append((cur, lv, _refill_level_miss.get(lv, 0)))
    if not below:
        return None
    eligible = [x for x in below if x[2] < REFILL_SKIP_LEVEL_AFTER]
    if not eligible:
        for _, lv, _ in below:
            _refill_level_miss[lv] = 0
        print(f"task_pool: refill unstuck levels {[x[1] for x in below]}")
        eligible = below
    eligible.sort(key=lambda x: (x[0], x[1]))
    return eligible[0][1]


def note_refill_level_miss(level: int) -> None:
    lv = int(level)
    n = _refill_level_miss.get(lv, 0) + 1
    _refill_level_miss[lv] = n
    if n == REFILL_SKIP_LEVEL_AFTER:
        print(f"task_pool: refill lvl={lv} stuck ({n} misses), skipping to other levels")


def note_refill_level_success(level: int) -> None:
    _refill_level_miss.pop(int(level), None)


def _refill_batch_level(batch: List[dict]) -> Optional[int]:
    for t in batch:
        try:
            return int(t.get("level", -1))
        except (TypeError, ValueError):
            continue
    return None


def add_tasks(tasks: List[dict]) -> int:
    """Возвращает число реально добавленных задач (не len(batch))."""
    if not tasks:
        return 0
    from task_filters import is_date_related_task
    import task_diversity
    from pool_catalog import catalog_allow_repeat

    with _lock:
        if total_unlocked() >= POOL_MAX_TOTAL:
            return 0
        pool_snap = snapshot_unlocked()
        pool_total = total_unlocked()
        batch_buf: List[dict] = []
        added = 0
        skipped_similar = 0
        for t in tasks:
            if not isinstance(t, dict) or is_date_related_task(t):
                continue
            try:
                lv_chk = int(t.get("level", 0))
            except Exception:
                continue
            from task_filters import is_valid_playable_task, is_valid_pool_refill_task

            playable_ok = (
                is_valid_pool_refill_task(t, lv_chk)
                if pool_total < refill_target_total()
                else is_valid_playable_task(t, lv_chk)
            )
            if not playable_ok:
                continue
            from_catalog = bool(t.get("_from_catalog"))
            if from_catalog:
                allow_cat_repeat = catalog_allow_repeat(lv_chk, pool_snap, pool_total=pool_total)
                ok = task_diversity.can_accept_catalog_task(
                    t, pool_snap, batch_buf, allow_repeat=allow_cat_repeat
                )
            else:
                ok = task_diversity.can_accept_task(
                    t, pool_snap, batch_buf, pool_total=pool_total
                )
            if not ok:
                skipped_similar += 1
                continue
            try:
                lv = int(t.get("level", 0))
            except Exception:
                continue
            if len(_buckets[lv]) >= POOL_TARGET_PER_LEVEL:
                continue
            if total_unlocked() >= refill_target_total() or total_unlocked() >= POOL_MAX_TOTAL:
                break
            stored = {k: v for k, v in t.items() if k != "_from_catalog"}
            _buckets[lv].append(stored)
            pool_snap.append(stored)
            batch_buf.append(stored)
            added += 1
            pool_total += 1
        if skipped_similar:
            print(f"task_pool.add_tasks: skipped {skipped_similar} similar/duplicate-topic")
        if added:
            save_unlocked()
    return added


def begin_check() -> None:
    global _check_active_count
    import ollama_coordinator

    with _check_lock:
        was_idle = _check_active_count == 0
        _check_active_count += 1
    if was_idle:
        ollama_coordinator.pause_refill_for_check()


def end_check() -> None:
    global _check_active_count
    import ollama_coordinator

    with _check_lock:
        _check_active_count = max(0, _check_active_count - 1)
        idle = _check_active_count == 0
    if idle:
        try:
            ollama_coordinator.resume_refill_after_check()
        except Exception as e:
            print(f"task_pool: resume_refill_after_check error: {e}")


@contextmanager
def check_in_progress() -> Generator[None, None, None]:
    """A2: пока идёт /check_task, фоновый refill ждёт."""
    begin_check()
    try:
        yield
    finally:
        end_check()


def is_check_active() -> bool:
    with _check_lock:
        return _check_active_count > 0


def _wait_while_check_active() -> None:
    import ollama_coordinator

    ollama_coordinator.wait_if_check_active(poll_s=0.4)


def stats() -> dict:
    with _lock:
        by_level = {str(k): len(v) for k, v in sorted(_buckets.items())}
        tot = total_unlocked()
    return {
        "task_pool_enabled": ENABLED,
        "task_pool_total": tot,
        "task_pool_by_level": by_level,
        "task_pool_min_threshold": POOL_MIN_TOTAL,
        "task_pool_refill_target": refill_target_total(),
        "task_pool_check_pausing_refill": is_check_active(),
        "task_pool_max_cap": POOL_MAX_TOTAL,
        "task_pool_path": POOL_PATH,
    }


def count_by_level(level: int) -> int:
    with _lock:
        return len(_buckets.get(int(level), []))


def seed_from_catalog_if_low() -> int:
    """До 5 задач каталога на уровень, если на уровне меньше 5 (без повторного seed при рестарте)."""
    if not ENABLED or os.getenv("TASK_POOL_SEED_CATALOG", "1") == "0":
        return 0
    if total() >= refill_target_total():
        return 0
    from pool_catalog import catalog_refill_batch

    before = total()
    with _lock:
        snap = snapshot_unlocked()
    for lv in (0, 1, 2, 3):
        need = max(0, 5 - count_by_level(lv))
        if need > 0:
            add_tasks(catalog_refill_batch(lv, need, snap))
            with _lock:
                snap = snapshot_unlocked()
    n = total() - before
    if n:
        print(f"task_pool: seed catalog +{n} (total={total()})")
    return n


def bulk_seed_all_catalog() -> int:
    """Загрузить весь каталог (20 шаблонов) — мгновенный старт пула."""
    if not ENABLED or os.getenv("TASK_POOL_BULK_CATALOG_SEED", "1") == "0":
        return 0
    from pool_catalog import all_catalog_pool_tasks

    before = total()
    tasks = all_catalog_pool_tasks()
    for t in tasks:
        t["_from_catalog"] = True
    add_tasks(tasks)
    n = total() - before
    if n:
        print(f"task_pool: bulk catalog seed +{n} (total={total()})")
    return n


def schedule_refill_if_low() -> None:
    if not ENABLED or _refill_fn is None:
        return
    target = refill_target_total()
    if total() >= target:
        return

    def worker() -> None:
        if not _refill_lock.acquire(blocking=False):
            print("task_pool: refill already running")
            return
        empty_streak = 0
        try:
            print(f"task_pool: refill worker start target={refill_target_total()}")
            while total() < refill_target_total() and total() < POOL_MAX_TOTAL:
                _wait_while_check_active()
                try:
                    batch = _refill_fn()
                except Exception as e:
                    print(f"task_pool: refill batch error: {e}")
                    batch = []
                if not batch:
                    empty_streak += 1
                    wait = min(600, REFILL_RETRY_SEC * min(empty_streak, 6))
                    if os.getenv("TASK_POOL_FAST_EMPTY_RETRY", "1") != "0":
                        wait = min(wait, 30)
                    if empty_streak >= REFILL_MAX_EMPTY_STREAK:
                        print(
                            f"task_pool: refill gave up after {empty_streak} empty batches "
                            f"(total={total()}), reschedule in {REFILL_GAVE_UP_RESTART_SEC}s"
                        )
                        break
                    print(
                        f"task_pool: empty batch #{empty_streak}, "
                        f"retry in {wait}s (total={total()})"
                    )
                    time.sleep(wait)
                    continue
                added_n = add_tasks(batch)
                batch_lv = _refill_batch_level(batch)
                if added_n:
                    empty_streak = 0
                    if batch_lv is not None:
                        note_refill_level_success(batch_lv)
                    print(
                        f"task_pool: refill +{added_n} added "
                        f"(batch={len(batch)}), total={total()}"
                    )
                    if REFILL_PAUSE_SEC > 0:
                        time.sleep(REFILL_PAUSE_SEC)
                else:
                    empty_streak += 1
                    if batch_lv is not None:
                        note_refill_level_miss(batch_lv)
                    print(
                        f"task_pool: refill batch={len(batch)} but 0 added "
                        f"(dup/filter), streak={empty_streak}, total={total()}"
                    )
                    wait = min(30, REFILL_ZERO_ADDED_WAIT_SEC)
                    if empty_streak < REFILL_MAX_EMPTY_STREAK:
                        time.sleep(wait)
        finally:
            _refill_lock.release()
            if total() < refill_target_total() and total() < POOL_MAX_TOTAL:

                def _restart_later() -> None:
                    time.sleep(max(60, REFILL_GAVE_UP_RESTART_SEC))
                    if total() < refill_target_total():
                        print(
                            f"task_pool: refill auto-restart (total={total()}, "
                            f"target={refill_target_total()})"
                        )
                        schedule_refill_if_low()

                threading.Thread(target=_restart_later, daemon=True).start()

    threading.Thread(target=worker, daemon=True).start()


def total() -> int:
    with _lock:
        return total_unlocked()

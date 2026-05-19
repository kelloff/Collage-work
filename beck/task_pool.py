"""
Предзагруженный пул заданий на диске: выдача без ожидания LLM, фоновое пополнение.
Включение: TASK_POOL_ENABLED=1 (по умолчанию). Файл: TASK_POOL_PATH (tasks_pool.json рядом с beck).
"""
from __future__ import annotations

import json
import os
import threading
from collections import defaultdict
from typing import Any, Callable, Dict, List, Optional

POOL_PATH = os.getenv(
    "TASK_POOL_PATH",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "tasks_pool.json"),
)
POOL_MIN_TOTAL = int(os.getenv("TASK_POOL_MIN_TOTAL", "180"))
POOL_MAX_TOTAL = int(os.getenv("TASK_POOL_MAX_TOTAL", "400"))
ENABLED = os.getenv("TASK_POOL_ENABLED", "1") == "1"

_lock = threading.Lock()
_refill_lock = threading.Lock()
_buckets: Dict[int, List[dict]] = defaultdict(list)
_refill_fn: Optional[Callable[[], List[dict]]] = None


def set_refill_fn(fn: Callable[[], List[dict]]) -> None:
    global _refill_fn
    _refill_fn = fn


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


def add_tasks(tasks: List[dict]) -> None:
    if not tasks:
        return
    with _lock:
        if total_unlocked() >= POOL_MAX_TOTAL:
            return
        for t in tasks:
            if not isinstance(t, dict):
                continue
            try:
                lv = int(t.get("level", 0))
            except Exception:
                continue
            if total_unlocked() >= POOL_MAX_TOTAL:
                break
            _buckets[lv].append(t)
        save_unlocked()


def stats() -> dict:
    with _lock:
        by_level = {str(k): len(v) for k, v in sorted(_buckets.items())}
        tot = total_unlocked()
    return {
        "task_pool_enabled": ENABLED,
        "task_pool_total": tot,
        "task_pool_by_level": by_level,
        "task_pool_min_threshold": POOL_MIN_TOTAL,
        "task_pool_max_cap": POOL_MAX_TOTAL,
        "task_pool_path": POOL_PATH,
    }


def count_by_level(level: int) -> int:
    with _lock:
        return len(_buckets.get(int(level), []))


def schedule_refill_if_low() -> None:
    if not ENABLED or _refill_fn is None:
        return
    if total() >= POOL_MIN_TOTAL:
        return

    def worker() -> None:
        if not _refill_lock.acquire(blocking=False):
            return
        try:
            while total() < POOL_MIN_TOTAL and total() < POOL_MAX_TOTAL:
                batch = _refill_fn()
                if not batch:
                    print("task_pool: refill batch empty, stopping")
                    break
                add_tasks(batch)
                print(f"task_pool: refill +{len(batch)} tasks, total={total()}")
        finally:
            _refill_lock.release()

    threading.Thread(target=worker, daemon=True).start()


def total() -> int:
    with _lock:
        return total_unlocked()

"""
Фоновый refill пула: один запрос Ollama → до N задач в JSON (qwen2.5:3b на :11434).
"""
from __future__ import annotations

import os
import re
import threading
import time
from typing import Any, List, Optional

import task_pool
from models import TaskSpec
from ollama_client import OllamaAborted, ollama_chat
from ollama_coordinator import (
    RefillPaused,
    clear_active_refill,
    clear_refill_attempt,
    get_refill_abort_event,
    is_refill_aborted,
    mark_refill_attempt,
    register_active_refill,
    wait_until_refill_allowed,
)
from pool_catalog import catalog_refill_batch
from task_filters import is_date_related_task, is_valid_playable_task, level_curriculum_block
from tasks_fallback_catalog import FALLBACK_TASKS_BY_LEVEL

from ollama_tasks_json import parse_ollama_tasks_json

# Компактные задачи lvl0: ~130 токенов × 5 + запас (меньше = быстрее генерация)
_POOL_PREDICT_PER_TASK = int(os.getenv("OLLAMA_POOL_PREDICT_PER_TASK", "130"))
_BATCH_MIN_ACCEPT = int(os.getenv("TASK_POOL_BATCH_MIN_ACCEPT", "2"))
_POOL_MIN_PREDICT = int(os.getenv("OLLAMA_POOL_MIN_PREDICT", "280"))


def _pool_num_predict_for(count: int) -> int:
    base = int(os.getenv("OLLAMA_POOL_NUM_PREDICT", "0"))
    if base > 0:
        return base
    return min(
        2000,
        max(_POOL_MIN_PREDICT, _POOL_PREDICT_PER_TASK * max(1, count) + 96),
    )


def _refill_heavy_from_level() -> int:
    """Уровень, с которого refill переключается на heavy-модель. 99 = всегда лёгкая."""
    return int(os.getenv("OLLAMA_REFILL_HEAVY_FROM_LEVEL", "99"))


def _refill_ollama_max_level() -> int:
    """Фоновый Ollama (0.5b) только для уровней 0..N включительно. Выше — каталог."""
    return int(os.getenv("OLLAMA_REFILL_OLLAMA_MAX_LEVEL", "1"))


def _refill_use_ollama(level: int) -> bool:
    return int(level) <= _refill_ollama_max_level()


def _catalog_vary_enabled() -> bool:
    return os.getenv("OLLAMA_REFILL_CATALOG_VARY", "1").strip().lower() in (
        "1",
        "true",
        "yes",
    )


def _catalog_vary_level_range() -> tuple[int, int]:
    lo = int(os.getenv("OLLAMA_REFILL_CATALOG_VARY_FROM_LEVEL", "2"))
    hi = int(os.getenv("OLLAMA_REFILL_CATALOG_VARY_TO_LEVEL", "3"))
    return lo, hi


def _refill_use_catalog_vary(level: int) -> bool:
    """Lvl 2–3: 0.5b видоизменяет шаблоны каталога (не свободная генерация)."""
    if not _catalog_vary_enabled():
        return False
    if _refill_use_ollama(int(level)):
        return False
    lo, hi = _catalog_vary_level_range()
    lv = int(level)
    return lo <= lv <= hi


def _pick_catalog_seeds(level: int, count: int, pool_snap: List[dict]) -> List[dict]:
    catalog = FALLBACK_TASKS_BY_LEVEL.get(int(level), [])
    if not catalog:
        return []
    n_cat = len(catalog)
    on_level = sum(1 for t in pool_snap if int(t.get("level", -1)) == int(level))
    start = on_level % n_cat
    return [catalog[(start + i) % n_cat] for i in range(max(1, count))]


def _pool_catalog_vary_system_prompt(level: int, count: int) -> str:
    lv = int(level)
    return (
        "JSON только: {\"tasks\":[...]}. Без markdown и текста вне JSON.\n"
        + level_curriculum_block(lv)
        + (
            f"Сгенерируй ровно {count} вариаций: по одной на каждый образец в запросе.\n"
            "Тот же тип упражнения (цикл/список/сумма и т.д.), другие числа и формулировка.\n"
            "expected_output должен математически соответствовать новым числам в description.\n"
            "Не копируй description и expected_output образца дословно.\n"
        )
        + _json_format_example(lv, count)
        + (
            'Поля: level, category, description, expected_output, required_patterns "", '
            'check_type "stdout_exact", required_keywords "", allow_direct_print 0|1.\n'
        )
    )


def _pool_catalog_vary_user_prompt(
    level: int,
    seeds: List[dict],
    pool_snap: List[dict],
) -> str:
    outs = [
        str(t.get("expected_output", "")).strip()
        for t in pool_snap
        if int(t.get("level", 0)) == int(level) and t.get("expected_output")
    ]
    note = ""
    if outs:
        note = (
            "Не повторяй эти expected_output:\n- "
            + "\n- ".join(outs[:16])
            + "\n"
        )
    lines = [f"Образцы (сделай по одной вариации на каждый, level={int(level)}):"]
    for i, t in enumerate(seeds, 1):
        desc = str(t.get("description", "")).strip()
        out = str(t.get("expected_output", "")).strip()
        lines.append(f'{i}) "{desc[:120]}" → "{out[:60]}"')
    return "\n".join(lines) + "\n" + note + "Только JSON.\n"


def _refill_model_for_level(level: int, default_model: str) -> str:
    if int(level) < _refill_heavy_from_level():
        return default_model
    heavy = (
        os.getenv("OLLAMA_REFILL_HEAVY_MODEL", "").strip()
        or os.getenv("OLLAMA_MODEL", "").strip()
    )
    return heavy or default_model


def _refill_timeout_for_level(level: int, default_timeout: int) -> int:
    if int(level) < _refill_heavy_from_level():
        return default_timeout
    return int(
        os.getenv(
            "OLLAMA_REFILL_HEAVY_TIMEOUT",
            os.getenv("OLLAMA_SINGLE_TIMEOUT", "600"),
        )
    )


def _refill_chunk_for_level(level: int, default_chunk: int) -> int:
    if int(level) < _refill_heavy_from_level():
        return default_chunk
    heavy_chunk = int(os.getenv("TASK_POOL_REFILL_HEAVY_CHUNK", "1"))
    return min(max(1, default_chunk), max(1, heavy_chunk))


def _level0_quality_block() -> str:
    return (
        "Уровень 0 (note_01) — только для начинающих:\n"
        "- Одна простая цель: print, переменная и print, +, -, *, /.\n"
        "- Описание короткое (1–2 предложения), понятное школьнику.\n"
        "- expected_output: одно число или одна короткая строка (без \\n).\n"
        "- category всегда строка \"easy\" (не null, не None).\n"
        "- required_patterns и required_keywords — только пустая строка \"\".\n"
        "- allow_direct_print: 1 если решение — один print(...); иначе 0.\n"
        "- Задача должна быть уникальной: другие числа, другой смысл, другой вывод.\n"
        "- Не копируй из курса дословно: Hello World, Привет мир, Python, 2+3=5, 7*8=56.\n"
    )


def _catalog_examples_block(level: int) -> str:
    items = FALLBACK_TASKS_BY_LEVEL.get(int(level), [])
    if not items:
        return ""
    lines = ["Образцы стиля курса (смысл и простота, не копируй текст и вывод):"]
    for t in items[:5 if int(level) == 0 else 3]:
        desc = str(t.get("description", "")).strip()
        out = str(t.get("expected_output", "")).strip()
        if desc and out:
            lines.append(f'  "{desc[:90]}" → "{out[:40]}"')
    return "\n".join(lines) + "\n"


def _json_format_example(level: int, n: int) -> str:
    """Компактный шаблон — модель чаще держит валидный JSON."""
    if int(level) == 0:
        return (
            f'Пример формата (сделай {n} других заданий, level={level}):\n'
            '{"tasks":['
            '{"level":0,"category":"easy","description":"Умножь 4 на 6 и выведи результат",'
            '"expected_output":"24","required_patterns":"","check_type":"stdout_exact",'
            '"required_keywords":"","allow_direct_print":0},'
            '{"level":0,"category":"easy","description":"Выведи строку \\"Кот\\"",'
            '"expected_output":"Кот","required_patterns":"","check_type":"stdout_exact",'
            '"required_keywords":"","allow_direct_print":1}'
            "]}\n"
        )
    return (
        f'Формат: {{"tasks":[...]}} — ровно {n} объектов, у каждого level={level}, '
        "category easy|medium|hard, required_patterns \"\", required_keywords \"\".\n"
    )


def _pool_system_prompt(level: int, count: int) -> str:
    lv = int(level)
    parts = [
        "JSON только: {\"tasks\":[...]}. Без markdown и текста вне JSON.\n",
        "Без date/datetime/import/input/if/for/while/def/списков.\n",
        level_curriculum_block(lv),
        "Каждая задача — другие числа, формулировка и expected_output.\n",
    ]
    if lv == 0:
        parts.append(_level0_quality_block())
    parts.append(_catalog_examples_block(lv))
    parts.append(_json_format_example(lv, count))
    parts.append(
        'Поля: level, category, description, expected_output, required_patterns "", '
        'check_type "stdout_exact", required_keywords "", allow_direct_print 0|1.\n'
    )
    return "".join(parts)


def _pool_user_prompt(level: int, count: int, pool_snap: List[dict]) -> str:
    outs = [
        str(t.get("expected_output", "")).strip()
        for t in pool_snap
        if int(t.get("level", 0)) == int(level) and t.get("expected_output")
    ]
    note = ""
    if outs:
        note = (
            "Не повторяй эти expected_output:\n- "
            + "\n- ".join(outs[:16])
            + "\n"
        )
    one = "задачу" if count == 1 else f"{count} задач"
    return (
        f"Сгенерируй РОВНО {count} разн{'ую' if count == 1 else 'ые'} {one} "
        f"с level={int(level)} в массиве tasks.\n"
        + note
        + "description — для ученика (Выведи/Посчитай/Умножь). Только JSON. "
        + "Одна цель в description, конкретный expected_output.\n"
    )


def _normalize_model_description(desc: str) -> str:
    """Убираем эхо промпта «Сгенерируй…» — оставляем формулировку для игрока."""
    d = desc.strip()
    if not d:
        return d
    m = re.match(r"(?i)^сгенерируй(?:те)?\s+(.+)$", d)
    if m:
        rest = m.group(1).strip()
        rest = re.sub(r"(?i)\s+и\s+выведи(?:те)?\s+.*$", "", rest).strip()
        if rest:
            return rest[0].upper() + rest[1:] if len(rest) > 1 else rest.upper()
    m2 = re.match(r"(?i)^создай(?:те)?\s+задани[ея]\s*:?\s*(.+)$", d)
    if m2:
        rest = m2.group(1).strip()
        if rest:
            return rest[0].upper() + rest[1:] if len(rest) > 1 else rest.upper()
    return d


def _clean_str_field(val: Any, *, empty_ok: bool = True) -> str:
    s = str(val or "").strip()
    if s.lower() in ("none", "null", "n/a"):
        return "" if empty_ok else s
    if s in ("[]", "['']", '[""]'):
        return ""
    return s


def _normalize_category(val: Any, level: int) -> str:
    s = _clean_str_field(val, empty_ok=True)
    if not s or s.lower() == "none":
        return "easy" if int(level) == 0 else "medium"
    if s.lower() in ("easy", "medium", "hard"):
        return s.lower()
    return "easy" if int(level) == 0 else "medium"


def _normalize_allow_print(val: Any, level: int, desc: str) -> int:
    try:
        n = int(val)
        if n in (0, 1):
            return n
    except (TypeError, ValueError):
        pass
    d = desc.lower()
    if int(level) == 0 and ("print" in d or "выведи строк" in d or "выведи результат" in d):
        return 1
    return 0


_LVL0_OVERUSED_OUTPUTS = frozenset(
    {
        "hello, world!",
        "hello world",
        "привет, мир",
        "привет мир",
        "python",
    }
)


def _lvl0_output_overused(out: str) -> bool:
    o = out.lower().strip()
    return o in _LVL0_OVERUSED_OUTPUTS


def _task_from_obj(obj: dict, level: int) -> Optional[TaskSpec]:
    try:
        lv = int(obj.get("level", level))
    except (TypeError, ValueError):
        lv = int(level)
    if lv != int(level):
        return None

    desc = _normalize_model_description(_clean_str_field(obj.get("description"), empty_ok=False))
    out = _clean_str_field(obj.get("expected_output"), empty_ok=False)
    if not desc or not out or out in ("...", "…"):
        return None
    if int(level) == 0 and _lvl0_output_overused(out):
        return None

    pat = _clean_str_field(obj.get("required_patterns"))
    kw = _clean_str_field(obj.get("required_keywords"))
    cat = _normalize_category(obj.get("category"), level)
    allow = _normalize_allow_print(obj.get("allow_direct_print"), level, desc)

    task = TaskSpec(
        level=lv,
        category=cat,
        description=desc,
        expected_output=out,
        required_patterns=pat,
        check_type="stdout_exact",
        required_keywords=kw,
        allow_direct_print=allow,
    )
    from task_filters import is_valid_pool_refill_task

    if not is_valid_pool_refill_task(task, level):
        return None
    return task


def generate_pool_tasks_batch(
    level: int,
    count: int,
    *,
    ollama_base_url: str,
    ollama_model: str,
    ollama_num_predict: int,
    ollama_temperature: float,
    timeout_s: int,
    extra_options: Optional[dict],
    max_attempts: int = 3,
) -> List[dict]:
    """Один запрос Ollama → до count задач."""
    count = max(1, int(count))
    wait_until_refill_allowed()
    if is_refill_aborted():
        raise RefillPaused()

    mark_refill_attempt(level, count)
    local_abort = threading.Event()
    parent_abort = get_refill_abort_event()

    class _AbortProxy:
        def is_set(self) -> bool:
            return parent_abort.is_set() or local_abort.is_set()

    abort_proxy = _AbortProxy()
    register_active_refill(local_abort)

    pool_snap = [
        t
        for t in task_pool.snapshot_tasks()
        if int(t.get("level", 0)) == int(level)
    ]
    num_predict = ollama_num_predict if ollama_num_predict > 0 else _pool_num_predict_for(count)
    temp = min(ollama_temperature, 0.12)
    min_accept = min(count, max(1, _BATCH_MIN_ACCEPT))
    system_msg = _pool_system_prompt(level, count)
    last_raw = ""
    best: List[dict] = []

    try:
        import task_diversity

        for attempt in range(max(1, max_attempts)):
            wait_until_refill_allowed()
            if abort_proxy.is_set():
                raise RefillPaused()

            user_msg = _pool_user_prompt(level, count, pool_snap)
            t0 = time.monotonic()
            try:
                raw = ollama_chat(
                    ollama_base_url=ollama_base_url,
                    ollama_model=ollama_model,
                    ollama_num_predict=num_predict,
                    system_msg=system_msg,
                    user_msg=user_msg,
                    timeout_s=timeout_s,
                    force_json=True,
                    temperature=temp,
                    extra_options=extra_options,
                    abort_event=abort_proxy,
                )
                last_raw = raw
            except OllamaAborted:
                print(f"pool_refill: lvl={level} batch aborted (check_task)")
                raise RefillPaused()
            except Exception as e:
                print(
                    f"pool_refill: lvl={level} batch attempt={attempt + 1} "
                    f"error after {time.monotonic() - t0:.1f}s: {e}"
                )
                continue

            parsed = parse_ollama_tasks_json(raw, level)
            batch_buf: List[dict] = []
            seen_out: set[str] = set()
            for obj in parsed:
                task = _task_from_obj(obj, level)
                if not task:
                    continue
                td = task.model_dump()
                out_key = td["expected_output"].strip().lower()
                if out_key in seen_out:
                    continue
                if not task_diversity.can_accept_task(
                    td, pool_snap, batch_buf, pool_total=task_pool.total()
                ):
                    continue
                batch_buf.append(td)
                seen_out.add(out_key)
                if len(batch_buf) >= count:
                    break

            print(
                f"pool_refill: lvl={level} batch attempt={attempt + 1} "
                f"parsed={len(parsed)} accepted={len(batch_buf)}/{count} "
                f"elapsed={time.monotonic() - t0:.1f}s predict={num_predict}"
            )
            if len(batch_buf) > len(best):
                best = batch_buf
            if len(batch_buf) >= count:
                clear_refill_attempt()
                return batch_buf[:count]
            # Достаточно для скорости — не гоняем лишние попытки
            if len(batch_buf) >= min_accept:
                clear_refill_attempt()
                return batch_buf
            if batch_buf and attempt + 1 >= max(1, max_attempts):
                clear_refill_attempt()
                return batch_buf

        if last_raw:
            preview = re.sub(r"\s+", " ", last_raw[:280])
            print(
                f"pool_refill: lvl={level} batch incomplete "
                f"best={len(best)}/{count} raw={preview!r}"
            )
        if best:
            clear_refill_attempt()
            return best
        return []
    finally:
        clear_active_refill(local_abort)


def generate_pool_tasks_catalog_vary(
    level: int,
    seeds: List[dict],
    *,
    ollama_base_url: str,
    ollama_model: str,
    ollama_num_predict: int,
    ollama_temperature: float,
    timeout_s: int,
    extra_options: Optional[dict],
    max_attempts: int = 2,
) -> List[dict]:
    """0.5b: вариации фиксированных шаблонов каталога (lvl 2–3 refill)."""
    if not seeds:
        return []
    count = len(seeds)
    wait_until_refill_allowed()
    if is_refill_aborted():
        raise RefillPaused()

    mark_refill_attempt(level, count)
    local_abort = threading.Event()
    parent_abort = get_refill_abort_event()

    class _AbortProxy:
        def is_set(self) -> bool:
            return parent_abort.is_set() or local_abort.is_set()

    abort_proxy = _AbortProxy()
    register_active_refill(local_abort)

    pool_snap = [
        t
        for t in task_pool.snapshot_tasks()
        if int(t.get("level", 0)) == int(level)
    ]
    num_predict = ollama_num_predict if ollama_num_predict > 0 else _pool_num_predict_for(count)
    temp = min(ollama_temperature, 0.1)
    min_accept = min(count, max(1, _BATCH_MIN_ACCEPT))
    system_msg = _pool_catalog_vary_system_prompt(level, count)
    last_raw = ""
    best: List[dict] = []

    try:
        import task_diversity

        for attempt in range(max(1, max_attempts)):
            wait_until_refill_allowed()
            if abort_proxy.is_set():
                raise RefillPaused()

            user_msg = _pool_catalog_vary_user_prompt(level, seeds, pool_snap)
            t0 = time.monotonic()
            try:
                raw = ollama_chat(
                    ollama_base_url=ollama_base_url,
                    ollama_model=ollama_model,
                    ollama_num_predict=num_predict,
                    system_msg=system_msg,
                    user_msg=user_msg,
                    timeout_s=timeout_s,
                    force_json=True,
                    temperature=temp,
                    extra_options=extra_options,
                    abort_event=abort_proxy,
                )
                last_raw = raw
            except OllamaAborted:
                print(f"pool_refill: lvl={level} catalog-vary aborted (check_task)")
                raise RefillPaused()
            except Exception as e:
                print(
                    f"pool_refill: lvl={level} catalog-vary attempt={attempt + 1} "
                    f"error after {time.monotonic() - t0:.1f}s: {e}"
                )
                continue

            parsed = parse_ollama_tasks_json(raw, level)
            batch_buf: List[dict] = []
            seen_out: set[str] = set()
            for obj in parsed:
                task = _task_from_obj(obj, level)
                if not task:
                    continue
                td = task.model_dump()
                out_key = td["expected_output"].strip().lower()
                if out_key in seen_out:
                    continue
                if not task_diversity.can_accept_task(
                    td, pool_snap, batch_buf, pool_total=task_pool.total()
                ):
                    continue
                batch_buf.append(td)
                seen_out.add(out_key)
                if len(batch_buf) >= count:
                    break

            print(
                f"pool_refill: lvl={level} catalog-vary attempt={attempt + 1} "
                f"seeds={count} parsed={len(parsed)} accepted={len(batch_buf)}/{count} "
                f"elapsed={time.monotonic() - t0:.1f}s"
            )
            if len(batch_buf) > len(best):
                best = batch_buf
            if len(batch_buf) >= count:
                clear_refill_attempt()
                return batch_buf[:count]
            if len(batch_buf) >= min_accept:
                clear_refill_attempt()
                return batch_buf
            if batch_buf and attempt + 1 >= max(1, max_attempts):
                clear_refill_attempt()
                return batch_buf

        if last_raw:
            preview = re.sub(r"\s+", " ", last_raw[:280])
            print(
                f"pool_refill: lvl={level} catalog-vary incomplete "
                f"best={len(best)}/{count} raw={preview!r}"
            )
        if best:
            clear_refill_attempt()
            return best
        return []
    finally:
        clear_active_refill(local_abort)


def retry_pending_refill(
    level: int,
    count: int,
    *,
    ollama_base_url: str,
    ollama_model: str,
    ollama_num_predict: int,
    ollama_temperature: float,
    timeout_s: int,
    extra_options: Optional[dict],
    max_attempts: int = 3,
) -> None:
    def worker() -> None:
        try:
            batch = generate_pool_tasks_batch(
                level,
                count,
                ollama_base_url=ollama_base_url,
                ollama_model=ollama_model,
                ollama_num_predict=ollama_num_predict,
                ollama_temperature=ollama_temperature,
                timeout_s=timeout_s,
                extra_options=extra_options,
                max_attempts=max_attempts,
            )
            if batch:
                n = task_pool.add_tasks(batch)
                if n:
                    print(f"pool_refill: pending retry +{n} lvl={level}")
        except RefillPaused:
            pass
        except Exception as e:
            print(f"pool_refill: pending retry error: {e}")

    threading.Thread(target=worker, daemon=True).start()


# Совместимость
generate_one_pool_task = lambda level, **kw: generate_pool_tasks_batch(level, 1, **kw)


def _finish_refill_batch(level: int, batch: List[dict]) -> List[dict]:
    if not batch:
        task_pool.note_refill_level_miss(int(level))
    return batch


def run_refill_batch(
    pool_levels: List[int],
    pool_target_per_level: int,
    pool_refill_chunk: int,
    *,
    ollama_base_url: str,
    ollama_model: str,
    ollama_num_predict: int,
    ollama_temperature: float,
    timeout_s: int,
    extra_options: Optional[dict],
    max_attempts: int = 3,
) -> List[dict]:
    import ollama_coordinator

    ollama_coordinator.wait_if_check_active()

    lv = task_pool.pick_level_for_refill(pool_levels)
    if lv is None:
        return []

    need = max(0, pool_target_per_level - task_pool.count_by_level(lv))
    if need <= 0:
        return _finish_refill_batch(lv, [])

    ask = min(_refill_chunk_for_level(lv, pool_refill_chunk), need)
    counts = {int(l): task_pool.count_by_level(int(l)) for l in pool_levels}
    collected: List[dict] = []

    if _refill_use_ollama(lv):
        model = _refill_model_for_level(lv, ollama_model)
        timeout_eff = _refill_timeout_for_level(lv, timeout_s)
        model_note = f" model={model}" if model != ollama_model else ""
        print(
            f"task_pool: refill lvl={lv} ask={ask} ollama (batch){model_note} counts={counts}"
        )
        try:
            collected = generate_pool_tasks_batch(
                lv,
                ask,
                ollama_base_url=ollama_base_url,
                ollama_model=model,
                ollama_num_predict=ollama_num_predict,
                ollama_temperature=ollama_temperature,
                timeout_s=timeout_eff,
                extra_options=extra_options,
                max_attempts=max_attempts,
            )
        except RefillPaused:
            print(f"task_pool: refill lvl={lv} paused")
            return []
        if collected:
            print(f"task_pool: refill lvl={lv} +{len(collected)} ollama (batch)")
            return collected
    elif _refill_use_catalog_vary(lv):
        snap = task_pool.snapshot_tasks()
        seeds = _pick_catalog_seeds(lv, ask, snap)
        model = _refill_model_for_level(lv, ollama_model)
        timeout_eff = _refill_timeout_for_level(lv, timeout_s)
        print(
            f"task_pool: refill lvl={lv} ask={ask} catalog-vary "
            f"seeds={len(seeds)} model={model} counts={counts}"
        )
        if seeds:
            try:
                collected = generate_pool_tasks_catalog_vary(
                    lv,
                    seeds,
                    ollama_base_url=ollama_base_url,
                    ollama_model=model,
                    ollama_num_predict=ollama_num_predict,
                    ollama_temperature=ollama_temperature,
                    timeout_s=timeout_eff,
                    extra_options=extra_options,
                    max_attempts=max_attempts,
                )
            except RefillPaused:
                print(f"task_pool: refill lvl={lv} catalog-vary paused")
                return []
            if collected:
                print(f"task_pool: refill lvl={lv} +{len(collected)} catalog-vary")
                return collected
        print(f"task_pool: refill lvl={lv} catalog-vary miss → catalog fallback")
    else:
        print(
            f"task_pool: refill lvl={lv} ask={ask} catalog-only "
            f"(lvl>{_refill_ollama_max_level()}) counts={counts}"
        )

    if os.getenv("TASK_POOL_CATALOG_ON_MISS", "1") == "0":
        return _finish_refill_batch(lv, [])

    cat = catalog_refill_batch(lv, ask, task_pool.snapshot_tasks())
    if cat:
        print(f"task_pool: refill lvl={lv} +{len(cat)} from catalog")
        return cat
    print(f"task_pool: refill lvl={lv} catalog empty")
    return _finish_refill_batch(lv, [])

from typing import Callable, List, Optional, Tuple
import json
import os
import re
import time
from openai import OpenAI

import task_pool
import task_diversity
from models import TaskSpec
from ollama_client import ollama_chat
from task_filters import is_date_related_task, is_valid_playable_task, text_mentions_date_topic


def _no_date_tasks_prompt_block() -> str:
    return (
        "Не создавай задания про дату, время, календарь, datetime, strftime, "
        "today/сегодня/текущая дата, now() или import datetime.\n"
        "Только базовый Python: print, переменные, арифметика, if/else, циклы, списки — "
        "без сторонних библиотек.\n"
    )


def _normalize_task_list(tasks: List[TaskSpec]) -> List[TaskSpec]:
    return [t for t in tasks if not is_date_related_task(t)]


def parse_ollama_tasks_json(raw_text: str, level_hint: int = -1) -> List[dict]:
    from ollama_tasks_json import parse_ollama_tasks_json as _parse

    return _parse(raw_text, level_hint)


def fallback_generate_tasks(level: int, count: int) -> List[TaskSpec]:
    from tasks_fallback_catalog import catalog_tasks_for_level

    out: list[TaskSpec] = []
    for obj in catalog_tasks_for_level(level, count):
        out.append(
            TaskSpec(
                level=level,
                category=str(obj.get("category", "easy")),
                description=str(obj.get("description", "")),
                expected_output=str(obj.get("expected_output", "")),
                required_patterns=str(obj.get("required_patterns", "")),
                check_type=str(obj.get("check_type", "stdout_exact")),
                required_keywords=str(obj.get("required_keywords", "")),
                allow_direct_print=int(obj.get("allow_direct_print", 0)),
            )
        )
    return out


_FALLBACK_DESCRIPTIONS: Optional[set[str]] = None


def _fallback_description_set() -> set[str]:
    global _FALLBACK_DESCRIPTIONS
    if _FALLBACK_DESCRIPTIONS is None:
        found: set[str] = set()
        for lvl in range(4):
            for t in fallback_generate_tasks(lvl, 12):
                found.add(t.description.strip())
        _FALLBACK_DESCRIPTIONS = found
    return _FALLBACK_DESCRIPTIONS


def is_fallback_task(task: TaskSpec | dict) -> bool:
    if isinstance(task, TaskSpec):
        desc = task.description.strip()
    else:
        desc = str(task.get("description", "")).strip()
        if desc.startswith("AI:"):
            desc = desc[3:].strip()
    return desc in _fallback_description_set()


def strip_fallback_tasks(tasks: List[TaskSpec]) -> List[TaskSpec]:
    return [t for t in tasks if not is_fallback_task(t)]


def generate_tasks_via_ollama(
    level: int,
    count: int,
    ollama_base_url: str,
    ollama_model: str,
    ollama_num_predict: int,
    ollama_temperature: float,
    timeout_s: int = 120,
    extra_options: Optional[dict] = None,
    *,
    max_attempts: int = 5,
) -> Tuple[List[TaskSpec], bool]:
    """Генерация для игрока (/generate_tasks*), не для фонового пула."""
    system_msg = (
        "Ты создаёшь учебные задания по Python для новичков.\n"
        + _no_date_tasks_prompt_block()
        + task_diversity.diversity_prompt_block(level)
        + "Верни только валидный JSON-объект формата {\"tasks\":[...]}.\n"
        "В tasks должно быть ровно N объектов (N задаётся пользователем).\n"
        "Никакого markdown, комментариев, code fences и текста вне JSON.\n"
        "У каждого объекта обязательные поля: "
        "level, category, description, expected_output, required_patterns, check_type, required_keywords, allow_direct_print.\n"
        "check_type всегда \"stdout_exact\".\n"
        "required_keywords обычно пустая строка.\n"
        "description внутри ответа должен быть уникальным.\n"
        "Не фиксируй имена переменных (name/x/age), формулируй нейтрально.\n"
        "Для многострочного expected_output используй символы '\\n' внутри строки."
    )

    def _build_user_msg(need_count: int, avoid: List[str]) -> str:
        avoid_text = ""
        if avoid:
            avoid_text = (
                "Не повторяй формулировки из этого списка:\n- "
                + "\n- ".join(avoid[:20])
                + "\n"
            )
        return (
            f"Сгенерируй РОВНО {need_count} задач уровня сложности {level}.\n"
            "Верни только JSON-объект с ключом tasks: {\"tasks\":[...]}.\n"
            "Каждый объект задачи должен содержать все обязательные поля.\n"
            "- level равен текущему уровню.\n"
            "- category: easy/medium/hard.\n"
            "- description на русском, без привязки к имени переменной.\n"
            "- expected_output краткий и однозначный.\n"
            "- не создавай задачи, где ожидается конкретное имя человека в выводе (например 'Иван').\n"
            "- не создавай задачи про дату, время или datetime.\n"
            + avoid_text
            + "Никакого текста вне JSON."
        )

    collected: List[TaskSpec] = []
    seen_desc: set[str] = set()
    attempts = max(1, min(5, int(max_attempts)))
    for attempt in range(attempts):
        if len(collected) >= count:
            break
        need = count - len(collected)
        user_msg = _build_user_msg(need, list(seen_desc))
        try:
            raw = ollama_chat(
                ollama_base_url=ollama_base_url,
                ollama_model=ollama_model,
                ollama_num_predict=ollama_num_predict,
                system_msg=system_msg,
                user_msg=user_msg,
                timeout_s=timeout_s,
                force_json=True,
                temperature=ollama_temperature,
                extra_options=extra_options,
            )
        except Exception as e:
            print(f"generate_tasks_via_ollama: attempt={attempt + 1} error: {e}")
            continue

        for obj in parse_ollama_tasks_json(raw, level):
            try:
                desc = str(obj.get("description", "")).strip()
                out = str(obj.get("expected_output", "")).strip()
                if not desc or desc in seen_desc:
                    continue
                if any(task_diversity.descriptions_too_similar(desc, p) for p in seen_desc):
                    continue
                task = TaskSpec(
                    level=level,
                    category=str(obj.get("category", "easy")),
                    description=desc,
                    expected_output=out,
                    required_patterns=str(obj.get("required_patterns", "")),
                    check_type=str(obj.get("check_type", "stdout_exact")),
                    required_keywords=str(obj.get("required_keywords", "")),
                    allow_direct_print=int(obj.get("allow_direct_print", 0)),
                )
                if is_date_related_task(task) or not is_valid_playable_task(task, level):
                    continue
                collected.append(task)
                seen_desc.add(desc)
                if len(collected) >= count:
                    break
            except Exception:
                continue

    if not collected:
        return [], True
    return collected, False


def llm_generate_tasks(
    level: int,
    count: int,
    client: Optional[OpenAI],
    ollama_base_url: str,
    ollama_model: str,
    ollama_num_predict: int,
    ollama_temperature: float,
    ollama_single_timeout: int = 120,
    ollama_extra_options: Optional[dict] = None,
) -> Tuple[List[TaskSpec], str]:
    if not client:
        tasks, used_fallback = generate_tasks_via_ollama(
            level,
            count,
            ollama_base_url,
            ollama_model,
            ollama_num_predict,
            ollama_temperature,
            timeout_s=ollama_single_timeout,
            extra_options=ollama_extra_options,
        )
        if used_fallback or not tasks:
            return [], "fallback"
        return tasks, "ollama"

    system_msg = (
        "Ты создаёшь учебные задания по Python для новичков. "
        "Верни список задач в JSON, без пояснений."
    )
    user_msg = (
        f"Сгенерируй {count} задач уровня сложности {level} для обучения Python.\n"
        "Формат каждой задачи (JSON‑объект):\n"
        "{\n"
        '  "category": "easy" или "medium",\n'
        '  "description": "текст задания на русском",\n'
        '  "expected_output": "строка вывода программы",\n'
        '  "required_patterns": "фрагменты кода через ; которые ДОЛЖНЫ быть в решении",\n'
        '  "check_type": "stdout_exact",\n'
        '  "required_keywords": "" (можно оставить пустым),\n'
        '  "allow_direct_print": 0 или 1\n'
        "}\n"
        "Важно:\n"
        "- Задания уровня 0 — самые простые: одна переменная, один print.\n"
        "- Более высокие уровни — постепенное усложнение: условия, циклы, списки и т.п.\n"
        "- В description НЕ указывай конкретные имена переменных (name, x, age и т.д.). "
        "Используй нейтрально: \"создай переменную со значением ... и выведи её\".\n"
        "- Избегай задач, где ожидается конкретное имя человека (например 'Иван') в выводе.\n"
        "- Не создавай задачи про дату, время, datetime или сторонние библиотеки.\n"
        "Верни JSON‑массив таких объектов, без комментариев и лишнего текста."
    )

    try:
        resp = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_msg},
                {"role": "user", "content": user_msg},
            ],
            max_tokens=1200,
            temperature=0.5,
        )
        raw = resp.choices[0].message.content.strip()
    except Exception:
        tasks, used_fallback = generate_tasks_via_ollama(
            level,
            count,
            ollama_base_url,
            ollama_model,
            ollama_num_predict,
            ollama_temperature,
            timeout_s=ollama_single_timeout,
            extra_options=ollama_extra_options,
        )
        if used_fallback or not tasks:
            return [], "fallback"
        return tasks, "ollama"

    try:
        data = json.loads(raw)
    except Exception:
        return [], "fallback"

    tasks: List[TaskSpec] = []
    for obj in data:
        try:
            task = TaskSpec(
                level=level,
                category=str(obj.get("category", "easy")),
                description=str(obj.get("description", "")),
                expected_output=str(obj.get("expected_output", "")),
                required_patterns=str(obj.get("required_patterns", "")),
                check_type=str(obj.get("check_type", "stdout_exact")),
                required_keywords=str(obj.get("required_keywords", "")),
                allow_direct_print=int(obj.get("allow_direct_print", 0)),
            )
        except Exception:
            continue
        if is_date_related_task(task):
            continue
        tasks.append(task)
    tasks = strip_fallback_tasks(tasks)
    if not tasks:
        return [], "fallback"
    return tasks, "openai"


def normalize_tasks_multi(objs: List[dict], levels: List[int], count_per_level: int) -> List[TaskSpec]:
    remaining: dict[int, int] = {int(lv): count_per_level for lv in levels}
    out: List[TaskSpec] = []
    for obj in objs:
        if sum(remaining.values()) == 0:
            break
        desc = str(obj.get("description", "")).strip()
        if not desc:
            continue
        if text_mentions_date_topic(desc) or text_mentions_date_topic(
            str(obj.get("expected_output", ""))
        ) or text_mentions_date_topic(str(obj.get("required_patterns", ""))):
            continue
        lv: Optional[int] = None
        try:
            if obj.get("level") is not None and str(obj.get("level")).strip() != "":
                lv = int(obj["level"])
        except Exception:
            lv = None
        if lv is None or lv not in remaining or remaining[lv] <= 0:
            for level in levels:
                level = int(level)
                if remaining.get(level, 0) > 0:
                    lv = level
                    break
            else:
                continue
        if remaining.get(lv, 0) <= 0:
            continue
        remaining[lv] -= 1
        try:
            out.append(
                TaskSpec(
                    level=lv,
                    category=str(obj.get("category", "easy")),
                    description=desc,
                    expected_output=str(obj.get("expected_output", "")),
                    required_patterns=str(obj.get("required_patterns", "")),
                    check_type=str(obj.get("check_type", "stdout_exact")),
                    required_keywords=str(obj.get("required_keywords", "")),
                    allow_direct_print=int(obj.get("allow_direct_print", 0)),
                )
            )
        except Exception:
            continue
    return out


def generate_all_levels_via_ollama_one_shot(
    levels: List[int],
    count_per_level: int,
    ollama_base_url: str,
    ollama_model: str,
    ollama_multi_num_predict: int,
    ollama_temperature: float,
    ollama_multi_timeout: int,
    extra_options: Optional[dict] = None,
    *,
    for_pool: bool = False,
) -> Tuple[List[TaskSpec], str]:
    if for_pool:
        import ollama_coordinator

        ollama_coordinator.wait_if_check_active()
    levels = [int(x) for x in levels]
    total = len(levels) * count_per_level
    lv_str = ", ".join(str(x) for x in levels)
    system_msg = (
        "Ты создаёшь учебные задания по Python для новичков.\n"
        + _no_date_tasks_prompt_block()
        + "Верни только валидный JSON-объект формата {\"tasks\":[...]}.\n"
        f"В tasks должно быть ровно {total} объектов.\n"
        "Никакого markdown, комментариев, code fences и текста вне JSON.\n"
        "У каждого объекта обязательные поля: "
        "level, category, description, expected_output, required_patterns, check_type, required_keywords, allow_direct_print.\n"
        "check_type всегда \"stdout_exact\".\n"
        "required_keywords обычно пустая строка.\n"
        "Каждое description уникально.\n"
        "Не фиксируй имена переменных (name/x/age), формулируй нейтрально.\n"
        "Для многострочного expected_output используй символы '\\n' внутри строки."
    )
    user_msg = (
        f"Нужны задачи для уровней сложности: {lv_str}.\n"
        f"Для каждого из этих уровней — ровно по {count_per_level} задач; поле level в объекте = номер уровня.\n"
        f"Всего {total} задач.\n"
        "- Уровень 0: самые простые (print, одна переменная).\n"
        "- Уровни 1–3: постепенно сложнее (if, циклы, списки).\n"
        "- description на русском; expected_output краткий и проверяемый.\n"
        "- не создавай задачи про дату, время или datetime.\n"
        "Верни JSON с ключом tasks."
    )
    try:
        raw = ollama_chat(
            ollama_base_url=ollama_base_url,
            ollama_model=ollama_model,
            ollama_num_predict=ollama_multi_num_predict,
            system_msg=system_msg,
            user_msg=user_msg,
            timeout_s=ollama_multi_timeout,
            force_json=True,
            temperature=ollama_temperature,
            extra_options=extra_options,
        )
    except Exception as e:
        print(f"generate_all_levels_via_ollama_one_shot: ollama error: {e}")
        return [], "ollama_error"

    objs = parse_ollama_tasks_json(raw, -1)
    tasks = normalize_tasks_multi(objs, levels, count_per_level)
    if len(tasks) < total:
        print(f"generate_all_levels_via_ollama_one_shot: got {len(tasks)}/{total} tasks after normalize")
    return tasks, "ollama_one_shot"


def refill_one_batch(
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
    from pool_refill import run_refill_batch

    return run_refill_batch(
        pool_levels,
        pool_target_per_level,
        pool_refill_chunk,
        ollama_base_url=ollama_base_url,
        ollama_model=ollama_model,
        ollama_num_predict=ollama_num_predict,
        ollama_temperature=ollama_temperature,
        timeout_s=timeout_s,
        extra_options=extra_options,
        max_attempts=max_attempts,
    )

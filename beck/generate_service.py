from typing import Callable, List, Optional, Tuple
import json
import os
import re
from datetime import date, datetime

from openai import OpenAI

import task_pool
from models import TaskSpec
from ollama_client import ollama_chat


def _reference_date_prompt_block() -> str:
    today = date.today()
    now = datetime.now()
    return (
        f"Сегодня на сервере: {today.isoformat()} (год {today.year}).\n"
        f"Текущие дата и время: {now.isoformat(sep=' ', timespec='seconds')}.\n"
        "Если задание про «текущую» / «сегодняшнюю» дату — expected_output должен "
        f"соответствовать этой дате (год {today.year}), не выдумывай 2023 или другой год.\n"
        "Задания с datetime.now() / import datetime — только для уровня 2+; "
        "на уровне 0–1 не требуй импорт библиотек.\n"
    )


def _task_mentions_live_date(text: str) -> bool:
    t = (text or "").lower()
    keys = (
        "текущ",
        "сегодня",
        "нынешн",
        "datetime",
        "дату",
        "дата",
        "now()",
        "сейчас",
    )
    return any(k in t for k in keys)


def _normalize_task_list(tasks: List[TaskSpec]) -> List[TaskSpec]:
    return [_normalize_task_dates(t) for t in tasks]


def _normalize_task_dates(task: TaskSpec) -> TaskSpec:
    """Задачи про «текущую дату» — уровень 2+, актуальный expected_output."""
    desc = task.description.strip()
    exp = (task.expected_output or "").strip()
    patterns = (task.required_patterns or "").strip()
    lv = int(task.level)

    if not _task_mentions_live_date(desc) and not _task_mentions_live_date(exp):
        return task

    if lv < 2:
        lv = 2
        if not patterns:
            patterns = "datetime"

    if _task_mentions_live_date(desc):
        now = datetime.now()
        iso = now.isoformat(sep=" ", timespec="seconds")
        if not exp or re.search(r"20(1[0-9]|2[0-3])", exp):
            exp = iso
        elif str(date.today().year) not in exp:
            exp = iso

    return TaskSpec(
        level=lv,
        category=task.category,
        description=desc,
        expected_output=exp,
        required_patterns=patterns,
        check_type=task.check_type,
        required_keywords=task.required_keywords,
        allow_direct_print=task.allow_direct_print,
    )


def parse_ollama_tasks_json(raw_text: str, level_hint: int = -1) -> List[dict]:
    cleaned = (raw_text or "").strip()
    cleaned = cleaned.replace("```json", "").replace("```", "").strip()
    cleaned = cleaned.replace("\\[", "[").replace("\\]", "]")
    cleaned = cleaned.replace("\\{", "{").replace("\\}", "}")
    cleaned = re.sub(r",\s*//[^\n\r]*", "", cleaned)
    cleaned = re.sub(r"//[^\n\r]*", "", cleaned)
    cleaned = re.sub(r",\s*([}\]])", r"\1", cleaned)

    data = None
    try:
        data = json.loads(cleaned)
    except Exception:
        data = None

    if data is None:
        arr_match = re.search(r"\[[\s\S]*\]", cleaned)
        if arr_match:
            try:
                data = json.loads(arr_match.group(0))
            except Exception:
                data = None
        if data is None:
            arr_match = re.search(r"\[[\s\S]*?\]", cleaned)
            if arr_match:
                try:
                    data = json.loads(arr_match.group(0))
                except Exception:
                    data = None

    if data is None:
        obj_match = re.search(r"\{[\s\S]*?\"tasks\"[\s\S]*?\}", cleaned)
        if obj_match:
            try:
                maybe_obj = json.loads(obj_match.group(0))
                if isinstance(maybe_obj, dict) and "tasks" in maybe_obj:
                    data = maybe_obj["tasks"]
            except Exception:
                pass

    if data is None:
        obj_matches = re.findall(
            r"\{[\s\S]*?\"category\"[\s\S]*?\"expected_output\"[\s\S]*?\}",
            cleaned,
        )
        objs: list[dict] = []
        for m in obj_matches:
            if '"category"' not in m or '"expected_output"' not in m:
                continue
            try:
                parsed_obj = json.loads(m)
                if isinstance(parsed_obj, dict) and "expected_output" in parsed_obj:
                    objs.append(parsed_obj)
            except Exception:
                continue
        if objs:
            data = objs

    if isinstance(data, dict):
        if "tasks" in data and isinstance(data["tasks"], list):
            data = data["tasks"]
        elif "category" in data and "expected_output" in data:
            data = [data]

    if not isinstance(data, list):
        short = (raw_text or "")[:400].replace("\n", "\\n")
        print(
            f"parse_ollama_tasks_json: JSON parse failed, "
            f"level_hint={level_hint}. Raw(head)={short!r}"
        )
        return []

    return [obj for obj in data if isinstance(obj, dict)]


def fallback_generate_tasks(level: int, count: int) -> List[TaskSpec]:
    tasks_by_level: dict[int, list[dict]] = {
        0: [
            {"category": "easy", "description": 'Выведи строку "Hello, World!"', "expected_output": "Hello, World!", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 1},
            {"category": "easy", "description": 'Создай переменную со значением "Python" и выведи её', "expected_output": "Python", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 1},
            {"category": "easy", "description": "Создай переменную со значением 20 и выведи её", "expected_output": "20", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 1},
            {"category": "easy", "description": "Сложи числа 2 и 3 и выведи результат", "expected_output": "5", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 1},
            {"category": "easy", "description": "Выведи результат выражения 7*8", "expected_output": "56", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 1},
        ],
        1: [
            {"category": "medium", "description": 'Создай переменную x = 12. Если x больше 10, выведи "Большое", иначе "Маленькое"', "expected_output": "Большое", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
            {"category": "medium", "description": 'Создай переменную x = 7. Если число чётное — выведи "Even", иначе "Odd"', "expected_output": "Odd", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
            {"category": "medium", "description": 'Создай строку s = "Python". Если строка равна "Python", выведи "Да", иначе "Нет"', "expected_output": "Да", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
            {"category": "medium", "description": 'Создай переменную x = -5. Если число отрицательное — выведи "Минус", иначе "Плюс"', "expected_output": "Минус", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
            {"category": "medium", "description": 'Создай переменную x = 9. Если число делится на 3 — выведи "Div3", иначе "No"', "expected_output": "Div3", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
        ],
        2: [
            {"category": "medium", "description": "Пройди по списку чисел [1,2,3] и выведи каждое", "expected_output": "1\n2\n3", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
            {"category": "medium", "description": "Посчитай сумму чисел от 1 до 5 с помощью цикла", "expected_output": "15", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
            {"category": "medium", "description": "Выведи квадраты чисел от 1 до 3", "expected_output": "1\n4\n9", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
            {"category": "medium", "description": "Выведи все элементы списка ['a','b','c']", "expected_output": "a\nb\nc", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
            {"category": "medium", "description": "Посчитай количество элементов в списке [10,20,30]", "expected_output": "3", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
        ],
        3: [
            {"category": "hard", "description": "Отсортируй список [5,2,9,1] и выведи результат", "expected_output": "[1, 2, 5, 9]", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
            {"category": "hard", "description": "Выведи только чётные числа из списка [1,2,3,4,5]", "expected_output": "2\n4", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
            {"category": "hard", "description": "Найди максимальное число в списке [3,7,2]", "expected_output": "7", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
            {"category": "hard", "description": "Найди минимальное число в списке [3,7,2]", "expected_output": "2", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
            {"category": "hard", "description": "Посчитай сумму элементов списка [1,2,3,4]", "expected_output": "10", "required_patterns": "", "check_type": "stdout_exact", "required_keywords": "", "allow_direct_print": 0},
        ],
    }
    lst = tasks_by_level.get(level, [])
    out: list[TaskSpec] = []
    for i in range(min(count, len(lst))):
        obj = lst[i]
        out.append(TaskSpec(level=level, category=str(obj.get("category", "easy")), description=str(obj.get("description", "")), expected_output=str(obj.get("expected_output", "")), required_patterns=str(obj.get("required_patterns", "")), check_type=str(obj.get("check_type", "stdout_exact")), required_keywords=str(obj.get("required_keywords", "")), allow_direct_print=int(obj.get("allow_direct_print", 0))))
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
) -> Tuple[List[TaskSpec], bool]:
    system_msg = (
        "Ты создаёшь учебные задания по Python для новичков.\n"
        + _reference_date_prompt_block()
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
                + "\n- ".join(avoid[:10])
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
            + avoid_text
            + "Никакого текста вне JSON."
        )

    collected: List[TaskSpec] = []
    seen_desc: set[str] = set()
    for _ in range(5):
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
        except Exception:
            continue

        for obj in parse_ollama_tasks_json(raw, level):
            try:
                desc = str(obj.get("description", "")).strip()
                if not desc or desc in seen_desc:
                    continue
                task = _normalize_task_dates(
                    TaskSpec(
                        level=level,
                        category=str(obj.get("category", "easy")),
                        description=desc,
                        expected_output=str(obj.get("expected_output", "")),
                        required_patterns=str(obj.get("required_patterns", "")),
                        check_type=str(obj.get("check_type", "stdout_exact")),
                        required_keywords=str(obj.get("required_keywords", "")),
                        allow_direct_print=int(obj.get("allow_direct_print", 0)),
                    )
                )
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
            tasks.append(
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
        except Exception:
            continue
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
) -> Tuple[List[TaskSpec], str]:
    levels = [int(x) for x in levels]
    total = len(levels) * count_per_level
    lv_str = ", ".join(str(x) for x in levels)
    system_msg = (
        "Ты создаёшь учебные задания по Python для новичков.\n"
        + _reference_date_prompt_block()
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
    client: Optional[OpenAI],
    pool_levels: List[int],
    pool_target_per_level: int,
    pool_refill_chunk: int,
    pool_use_one_shot_refill: bool,
    llm_generate_tasks_fn: Callable[[int, int], Tuple[List[TaskSpec], str]],
    generate_tasks_via_ollama_fn: Callable[[int, int], Tuple[List[TaskSpec], bool]],
    generate_all_levels_via_ollama_one_shot_fn: Callable[[List[int], int], Tuple[List[TaskSpec], str]],
) -> List[dict]:
    out: List[dict] = []
    if client:
        for lvl in pool_levels:
            cur = task_pool.count_by_level(lvl)
            need = max(0, pool_target_per_level - cur)
            if need <= 0:
                continue
            ask = min(max(1, pool_refill_chunk), need)
            batch, _ = llm_generate_tasks_fn(int(lvl), ask)
            out.extend([t.model_dump() for t in strip_fallback_tasks(batch)])
        return [t for t in out if not is_fallback_task(t)]

    # Один уровень за батч (по умолчанию): один HTTP к Ollama ≈ до 5 задач — реже 480s timeout.
    # Старый режим «все уровни за раз»: TASK_POOL_REFILL_ONE_LEVEL_PER_BATCH=0
    one_level_per_batch = os.getenv("TASK_POOL_REFILL_ONE_LEVEL_PER_BATCH", "1") != "0"

    if pool_use_one_shot_refill and not one_level_per_batch:
        levels_need: List[int] = []
        max_need = 0
        for lvl in pool_levels:
            need = max(0, pool_target_per_level - task_pool.count_by_level(lvl))
            if need > 0:
                levels_need.append(lvl)
                max_need = max(max_need, min(need, pool_refill_chunk))
        if levels_need and max_need > 0:
            one, _ = generate_all_levels_via_ollama_one_shot_fn(levels_need, max_need)
            out.extend([t.model_dump() for t in strip_fallback_tasks(one)])
            filtered = [t for t in out if not is_fallback_task(t)]
            if filtered:
                return filtered

    if one_level_per_batch:
        # Строго 0 → 1 → 2 → 3: сначала добиваем уровень 0 до цели, потом следующий.
        for lvl in pool_levels:
            lv = int(lvl)
            need = max(0, pool_target_per_level - task_pool.count_by_level(lv))
            if need <= 0:
                continue
            ask = min(max(1, pool_refill_chunk), need)
            print(f"task_pool: refill lvl={lv} ask={ask} have={task_pool.count_by_level(lv)}")
            batch, used_fb = generate_tasks_via_ollama_fn(lv, ask)
            if used_fb or not batch:
                print(f"task_pool: refill lvl={lv} empty (fallback or ollama fail)")
                continue
            dumped = [t.model_dump() for t in _normalize_task_list(strip_fallback_tasks(batch))]
            filtered = [t for t in dumped if not is_fallback_task(t)]
            if filtered:
                print(f"task_pool: refill lvl={lv} +{len(filtered)}")
                return filtered
        return []

    for lvl in pool_levels:
        cur = task_pool.count_by_level(lvl)
        need = max(0, pool_target_per_level - cur)
        if need <= 0:
            continue
        ask = min(max(1, pool_refill_chunk), need)
        batch, used_fb = generate_tasks_via_ollama_fn(int(lvl), ask)
        if used_fb:
            continue
        out.extend([t.model_dump() for t in strip_fallback_tasks(batch)])
    return [t for t in out if not is_fallback_task(t)]

from typing import Callable, List, Optional, Tuple
import json
import re

from openai import OpenAI

import task_pool
from models import TaskSpec
from ollama_client import ollama_chat


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
        "Верни только валидный JSON-объект формата {\"tasks\":[...]}.\n"
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
                task = TaskSpec(
                    level=level,
                    category=str(obj.get("category", "easy")),
                    description=desc,
                    expected_output=str(obj.get("expected_output", "")),
                    required_patterns=str(obj.get("required_patterns", "")),
                    check_type=str(obj.get("check_type", "stdout_exact")),
                    required_keywords=str(obj.get("required_keywords", "")),
                    allow_direct_print=int(obj.get("allow_direct_print", 0)),
                )
                collected.append(task)
                seen_desc.add(desc)
                if len(collected) >= count:
                    break
            except Exception:
                continue

    if not collected:
        return fallback_generate_tasks(level, count), True
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
        return tasks, ("fallback" if used_fallback else "ollama")

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
        return tasks, ("fallback" if used_fallback else "ollama")

    try:
        data = json.loads(raw)
    except Exception:
        return fallback_generate_tasks(level, count), "fallback"

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
    if not tasks:
        return fallback_generate_tasks(level, count), "fallback"
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
        "Верни только валидный JSON-объект формата {\"tasks\":[...]}.\n"
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
            out.extend([t.model_dump() for t in batch])
        return out

    if pool_use_one_shot_refill:
        levels_need: List[int] = []
        max_need = 0
        for lvl in pool_levels:
            need = max(0, pool_target_per_level - task_pool.count_by_level(lvl))
            if need > 0:
                levels_need.append(lvl)
                max_need = max(max_need, min(need, pool_refill_chunk))
        if levels_need and max_need > 0:
            one, _ = generate_all_levels_via_ollama_one_shot_fn(levels_need, max_need)
            out.extend([t.model_dump() for t in one])
            if out:
                return out

    for lvl in pool_levels:
        cur = task_pool.count_by_level(lvl)
        need = max(0, pool_target_per_level - cur)
        if need <= 0:
            continue
        ask = min(max(1, pool_refill_chunk), need)
        batch, _ = generate_tasks_via_ollama_fn(int(lvl), ask)
        out.extend([t.model_dump() for t in batch])
    return out

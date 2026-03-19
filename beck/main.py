from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional, Tuple, List
import contextlib
import io
import os
import traceback
import re
import json

from openai import OpenAI
import requests

app = FastAPI(title="CollageWork AI Backend")

# ---------- OpenAI client ----------

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
client: Optional[OpenAI] = None
if OPENAI_API_KEY:
    client = OpenAI(api_key=OPENAI_API_KEY)
else:
    # Важно: не печатаем сам ключ. Просто сигнализируем, почему будут "заглушки".
    print("beck/main.py: OPENAI_API_KEY is not set. /generate_tasks will fail.")

# ---------- Ollama config ----------
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1:8b-instruct")


def _ollama_chat(system_msg: str, user_msg: str, timeout_s: int = 120) -> str:
    """
    Query local Ollama model via /api/chat (non-streaming).
    Returns assistant message content (string).
    """
    url = f"{OLLAMA_BASE_URL}/api/chat"
    payload = {
        "model": OLLAMA_MODEL,
        "messages": [
            {"role": "system", "content": system_msg},
            {"role": "user", "content": user_msg},
        ],
        "stream": False,
    }
    resp = requests.post(url, json=payload, timeout=timeout_s)
    resp.raise_for_status()
    data = resp.json()
    return str(data.get("message", {}).get("content", "")).strip()


class CheckTaskRequest(BaseModel):
    description: str
    expected_output: Optional[str] = None
    user_code: str
    required_patterns: Optional[str] = None


class CheckTaskResponse(BaseModel):
    success: bool
    feedback: str
    stdout: str = ""
    stderr: str = ""


class TaskSpec(BaseModel):
    level: int
    category: str
    description: str
    expected_output: str
    required_patterns: str
    check_type: str = "stdout_exact"
    required_keywords: str = ""
    allow_direct_print: int = 0


class GenerateTasksRequest(BaseModel):
    level: int
    count: int = 5


class GenerateTasksResponse(BaseModel):
    tasks: List[TaskSpec]


def _normalize_out(text: str) -> str:
    return (text or "").replace("\r", "").strip()


def _run_user_code_safely(code: str) -> Tuple[str, str]:
    """Мини‑песочница для выполнения пользовательского кода."""
    safe_builtins = {
        "print": print,
        "range": range,
        "len": len,
        "int": int,
        "float": float,
        "str": str,
        "bool": bool,
        "list": list,
        "dict": dict,
        "set": set,
        "tuple": tuple,
        "min": min,
        "max": max,
        "sum": sum,
        "abs": abs,
        "enumerate": enumerate,
    }
    globals_env = {"__builtins__": safe_builtins}
    locals_env = {}

    out_buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(out_buf):
            exec(code, globals_env, locals_env)
        return out_buf.getvalue(), ""
    except Exception:
        return out_buf.getvalue(), traceback.format_exc(limit=1)


def _llm_explain_mistake(description: str, expected: str, code: str, stdout: str) -> str:
    """Используем LLM, чтобы красиво объяснить ошибку."""
    if not client:
        # Нет OpenAI-клиента: пытаемся объяснить через Ollama.
        # Если Ollama тоже недоступна — отдаём простой текст.
        try:
            system_msg = (
                "Ты преподаватель по Python для начинающих. "
                "Кратко и по-доброму объясни, что не так в решении студента. "
                "Не пиши решение целиком, только направляй."
            )
            user_msg = (
                f"Задание: {description}\n"
                f"Ожидаемый вывод: {expected or '<нет>'}\n"
                f"Код студента:\n{code}\n"
                f"Фактический вывод:\n{stdout or '<пусто>'}\n"
                "Объясни, что нужно поправить."
            )
            return _ollama_chat(system_msg, user_msg, timeout_s=60)
        except Exception:
            return (
                "Вывод или логика не соответствуют заданию.\n"
                f"Ожидался вывод: {expected or '<нет>'}\n"
                f"Получено: {stdout or '<пусто>'}"
            )

    system_msg = (
        "Ты преподаватель по Python для начинающих. "
        "Кратко и по‑доброму объясни, что не так в решении студента. "
        "Не пиши решение целиком, только направляй."
    )
    user_msg = (
        f"Задание: {description}\n"
        f"Ожидаемый вывод: {expected or '<нет>'}\n"
        f"Код студента:\n{code}\n"
        f"Фактический вывод:\n{stdout or '<пусто>'}\n"
        "Объясни, что нужно поправить."
    )

    try:
        resp = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_msg},
                {"role": "user", "content": user_msg},
            ],
            max_tokens=300,
            temperature=0.2,
        )
        return resp.choices[0].message.content.strip()
    except Exception:
        # Квота могла кончиться — не падать, а вернуть простой текст.
        return (
            "Вывод или логика не соответствуют заданию.\n"
            f"Ожидался вывод: {expected or '<нет>'}\n"
            f"Получено: {stdout or '<пусто>'}"
        )


def _ai_check_solution_via_ollama(
    description: str,
    expected_output: str,
    required_patterns: str,
    user_code: str,
    stdout: str,
    stderr: str,
) -> Tuple[bool, str]:
    """
    Проверка "через AI": возвращает (success, feedback).
    Основа всё равно вычисляется локально (stdout/stderr), AI лишь решает итог по условиям задания.
    """
    system_msg = (
        "Ты проверяешь решение студента по заданию на Python. "
        "Ты НЕ изменяешь код. Ты оцениваешь корректность по входным данным ниже. "
        "Верни строго JSON без markdown вида: {\"success\": true/false, \"feedback\": \"...\"}."
    )
    user_msg = (
        f"Задание: {description}\n"
        f"Ожидаемый вывод: {expected_output or '<нет>'}\n"
        f"required_patterns: {required_patterns or '<пусто>'}\n"
        f"stdout: {stdout or '<пусто>'}\n"
        f"stderr: {stderr or '<пусто>'}\n"
        f"Код студента:\n{user_code}\n"
        "Правила:\n"
        "- Если stderr непустой: success=false.\n"
        "- Если expected_output непустой: сравни stdout (нормализуй пробелы и переводы строк), чтобы совпасть со значением.\n"
        "- required_patterns: если какие-то фрагменты разделенные ';' не входят в user_code, то success=false.\n"
        "- feedback должен кратко объяснить что поправить. Не пиши готовое решение.\n"
    )

    # Ollama может быть недоступна
    raw = _ollama_chat(system_msg, user_msg, timeout_s=120)

    # Вытаскиваем JSON из ответа
    arr_match = re.search(r"\{[\s\S]*\}", raw)
    json_str = arr_match.group(0) if arr_match else raw
    data = json.loads(json_str)
    success = bool(data.get("success", False))
    feedback = str(data.get("feedback", ""))
    return success, feedback


def _llm_generate_tasks(level: int, count: int) -> List[TaskSpec]:
    """Генерируем задачи через LLM в формате TaskSpec."""
    # Приоритет: OpenAI (если есть ключ), но если квота/ошибка — пробуем Ollama.
    if not client:
        return _generate_tasks_via_ollama(level, count)

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
        f"Верни JSON‑массив таких объектов, без комментариев и лишнего текста."
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
        # Если OpenAI недоступен (quota/rate limit/etc) — пробуем Ollama.
        return _generate_tasks_via_ollama(level, count)

    import json

    try:
        data = json.loads(raw)
    except Exception:
        # если модель ответила не‑JSON — делаем fallback
        return _fallback_generate_tasks(level, count)

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

    return tasks


def _generate_tasks_via_ollama(level: int, count: int) -> List[TaskSpec]:
    system_msg = (
        "Ты создаёшь учебные задания по Python для новичков. "
        "Верни список задач строго в JSON массиве (без markdown и без пояснений)."
    )
    user_msg = (
        f"Сгенерируй {count} задач уровня сложности {level} для обучения Python.\n"
        "Формат каждой задачи (JSON-объект):\n"
        "{\n"
        '  "category": "easy" или "medium" или "hard",\n'
        '  "description": "текст задания на русском",\n'
        '  "expected_output": "строка вывода программы",\n'
        '  "required_patterns": "фрагменты кода через ; которые ДОЛЖНЫ быть в решении",\n'
        '  "check_type": "stdout_exact",\n'
        '  "required_keywords": "" (можно оставить пустым),\n'
        '  "allow_direct_print": 0 или 1\n'
        "}\n"
        "Важно:\n"
        f"- Задания уровня 0 — самые простые.\n"
        f"- Более высокие уровни — усложнение: условия, циклы, списки.\n"
        "Верни ТОЛЬКО JSON-массив таких объектов."
    )

    try:
        raw = _ollama_chat(system_msg, user_msg)
    except Exception:
        return _fallback_generate_tasks(level, count)

    # У Ollama иногда могут быть префиксы/суффиксы — вытаскиваем первый JSON-массив.
    try:
        arr_match = re.search(r"\[[\s\S]*\]", raw)
        json_str = arr_match.group(0) if arr_match else raw
        data = json.loads(json_str)
    except Exception:
        return _fallback_generate_tasks(level, count)

    tasks: List[TaskSpec] = []
    if not isinstance(data, list):
        return _fallback_generate_tasks(level, count)

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
        return _fallback_generate_tasks(level, count)
    return tasks


def _fallback_generate_tasks(level: int, count: int) -> List[TaskSpec]:
    """Оффлайн список заданий (чтобы при 429/без ключа игра продолжала работать)."""
    tasks_by_level: dict[int, list[dict]] = {
        0: [
            {
                "category": "easy",
                "description": 'Выведи строку "Hello, World!"',
                "expected_output": "Hello, World!",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 1,
            },
            {
                "category": "easy",
                "description": 'Создай переменную name = "Python" и выведи её',
                "expected_output": "Python",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 1,
            },
            {
                "category": "easy",
                "description": "Создай переменную age = 20 и выведи её",
                "expected_output": "20",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 1,
            },
            {
                "category": "easy",
                "description": "Сложи числа 2 и 3 и выведи результат",
                "expected_output": "5",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 1,
            },
            {
                "category": "easy",
                "description": "Выведи результат выражения 7*8",
                "expected_output": "56",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 1,
            },
        ],
        1: [
            {
                "category": "medium",
                "description": 'Создай переменную x = 12. Если x больше 10, выведи "Большое", иначе "Маленькое"',
                "expected_output": "Большое",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
            {
                "category": "medium",
                "description": 'Создай переменную x = 7. Если число чётное — выведи "Even", иначе "Odd"',
                "expected_output": "Odd",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
            {
                "category": "medium",
                "description": 'Создай строку s = "Python". Если строка равна "Python", выведи "Да", иначе "Нет"',
                "expected_output": "Да",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
            {
                "category": "medium",
                "description": 'Создай переменную x = -5. Если число отрицательное — выведи "Минус", иначе "Плюс"',
                "expected_output": "Минус",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
            {
                "category": "medium",
                "description": 'Создай переменную x = 9. Если число делится на 3 — выведи "Div3", иначе "No"',
                "expected_output": "Div3",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
        ],
        2: [
            {
                "category": "medium",
                "description": "Пройди по списку чисел [1,2,3] и выведи каждое",
                "expected_output": "1\n2\n3",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
            {
                "category": "medium",
                "description": "Посчитай сумму чисел от 1 до 5 с помощью цикла",
                "expected_output": "15",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
            {
                "category": "medium",
                "description": "Выведи квадраты чисел от 1 до 3",
                "expected_output": "1\n4\n9",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
            {
                "category": "medium",
                "description": "Выведи все элементы списка ['a','b','c']",
                "expected_output": "a\nb\nc",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
            {
                "category": "medium",
                "description": "Посчитай количество элементов в списке [10,20,30]",
                "expected_output": "3",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
        ],
        3: [
            {
                "category": "hard",
                "description": "Отсортируй список [5,2,9,1] и выведи результат",
                "expected_output": "[1, 2, 5, 9]",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
            {
                "category": "hard",
                "description": "Выведи только чётные числа из списка [1,2,3,4,5]",
                "expected_output": "2\n4",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
            {
                "category": "hard",
                "description": "Найди максимальное число в списке [3,7,2]",
                "expected_output": "7",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
            {
                "category": "hard",
                "description": "Найди минимальное число в списке [3,7,2]",
                "expected_output": "2",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
            {
                "category": "hard",
                "description": "Посчитай сумму элементов списка [1,2,3,4]",
                "expected_output": "10",
                "required_patterns": "",
                "check_type": "stdout_exact",
                "required_keywords": "",
                "allow_direct_print": 0,
            },
        ],
    }

    lst = tasks_by_level.get(level, [])
    out: list[TaskSpec] = []
    for i in range(min(count, len(lst))):
        obj = lst[i]
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


@app.post("/check_task", response_model=CheckTaskResponse)
def check_task(req: CheckTaskRequest):
    desc = req.description.strip()
    expected = (req.expected_output or "").strip()
    code = req.user_code.strip()
    patterns_raw = (req.required_patterns or "").strip()

    if not code:
        return CheckTaskResponse(
            success=False,
            feedback="Код пустой. Напиши решение для задания.",
            stdout="",
            stderr=""
        )

    # 1) Выполняем код
    stdout, stderr = _run_user_code_safely(code)
    normalized_stdout = _normalize_out(stdout)
    normalized_expected = _normalize_out(expected)

    # 2) Делаем базовую "детерминированную" проверку,
    # чтобы не доверять AI на 100% при ошибках выполнения.
    det_success: bool = False
    det_feedback: str = ""

    if stderr:
        det_success = False
        det_feedback = "Ошибка выполнения. Посмотри stderr и исправь код."
    else:
        # expected_output задан → сравниваем stdout
        if expected:
            if normalized_stdout != normalized_expected:
                det_success = False
                det_feedback = "Вывод не совпадает с ожидаемым."
            else:
                # проверяем required_patterns (фрагменты кода)
                missing: List[str] = []
                if patterns_raw:
                    for p in patterns_raw.split(";"):
                        p = p.strip()
                        if not p:
                            continue
                        if p not in code:
                            missing.append(p)
                if missing:
                    det_success = False
                    det_feedback = "В коде не хватает обязательных фрагментов:\n" + "\n".join(f"- {m}" for m in missing)
                else:
                    det_success = True
                    det_feedback = "Решение корректное."
        else:
            # expected_output нет → успех, если нет ошибок выполнения
            det_success = True
            det_feedback = "Решение принято (ошибок выполнения нет)."

    # 3) "AI-проверка" и объяснение (через Ollama):
    # - если детерминированно успех → оставляем успех, но берём объяснение у AI
    # - если детерминированно не успех → AI может подтвердить/объяснить и вернуть success
    ai_success: bool = det_success
    ai_feedback: str = det_feedback
    try:
        ai_success, ai_feedback = _ai_check_solution_via_ollama(
            description=desc,
            expected_output=expected,
            required_patterns=patterns_raw,
            user_code=code,
            stdout=stdout,
            stderr=stderr,
        )
    except Exception:
        # Если Ollama не доступна/JSON не распарсился — оставляем детерминированный результат.
        ai_success = det_success
        ai_feedback = det_feedback

    # Ограничение безопасности:
    # если stderr есть — точно считаем неуспех.
    if stderr:
        ai_success = False

    # Итог: если детерминированно успешно — считаем успешным.
    # Иначе success берём из AI.
    final_success: bool = det_success if det_success else ai_success

    return CheckTaskResponse(
        success=final_success,
        feedback=ai_feedback or det_feedback,
        stdout=stdout,
        stderr=stderr
    )


@app.post("/generate_tasks", response_model=GenerateTasksResponse)
def generate_tasks(req: GenerateTasksRequest):
    level = req.level
    count = req.count

    tasks = _llm_generate_tasks(level, count)
    if not tasks:
        # Технический fallback на случай совсем неожиданных ситуаций.
        tasks = _fallback_generate_tasks(level, count)

    return GenerateTasksResponse(tasks=tasks)
"""Фильтры заданий (без date/datetime) — общие для пула и generate_service."""
from __future__ import annotations

import re

from models import TaskSpec

_DATE_TASK_KEYWORDS = (
    "текущ",
    "сегодня",
    "нынешн",
    "datetime",
    "strftime",
    "календар",
    "дату",
    "дата",
    "дате",
    "даты",
    "now()",
    "import time",
    "from datetime",
    "import datetime",
    "сейчас",
    "число месяца",
    "день недели",
)


def text_mentions_date_topic(text: str) -> bool:
    t = (text or "").lower()
    return any(k in t for k in _DATE_TASK_KEYWORDS)


def is_date_related_task(task: TaskSpec | dict) -> bool:
    if isinstance(task, TaskSpec):
        parts = (task.description, task.expected_output, task.required_patterns)
    else:
        parts = (
            str(task.get("description", "")),
            str(task.get("expected_output", "")),
            str(task.get("required_patterns", "")),
        )
    return any(text_mentions_date_topic(p) for p in parts)


# Эхо промпта / плейсхолдеры — не должны попадать игроку.
_META_DESC_MARKERS = (
    "фонов",
    "пул игр",
    "пул игры",
    "json",
    "tasks:[",
    "объектов",
    "ровно n",
    "учебные задания python",
    "верни только",
    "формат:",
    "без markdown",
    "уровня сложности",
    "напиши программу",
    "создай задание",
    "пример:",
    "с уровнем",
    "для пула",
    "фоновый",
)

_FORBIDDEN_ADVANCED = (
    "while ",
    "while(",
    "def ",
    "input(",
    "import ",
    "class ",
    "lambda ",
    "try:",
    "except",
    "open(",
    "with open",
)


def _task_text_parts(task: TaskSpec | dict) -> tuple[str, str, str]:
    if isinstance(task, TaskSpec):
        return (
            str(task.description or "").strip(),
            str(task.expected_output or "").strip(),
            str(task.required_patterns or "").strip(),
        )
    return (
        str(task.get("description", "")).strip(),
        str(task.get("expected_output", "")).strip(),
        str(task.get("required_patterns", "")).strip(),
    )


def is_invalid_expected_output(expected_output: str) -> bool:
    o = (expected_output or "").strip()
    if not o:
        return True
    low = o.lower()
    if low in ("...", "…", "....", "-", "?", "???", "n/a", "none", "null", "todo"):
        return True
    if re.fullmatch(r"\.{2,}", o):
        return True
    if len(o) <= 2 and not re.search(r"\d", o) and o not in ("Да", "Нет", "Odd", "Even"):
        if o in ("..", "…", "?"):
            return True
    if o.startswith("[") and o.endswith("]"):
        if "'" in o or '"' in o:
            return True
        if re.fullmatch(r"\[[\d,\s\-]+\]", o):
            return False
        return True
    if "\n" in o:
        lines = [ln.strip() for ln in o.splitlines() if ln.strip()]
        if not lines:
            return True
        if all(re.fullmatch(r"\d+", ln) for ln in lines):
            return False
        if all(re.fullmatch(r"[a-zA-Z]", ln) for ln in lines):
            return False
        if any(re.match(r"^-\s", ln) for ln in lines):
            return True
        if len(lines) > 10:
            return True
        return False
    return False


def is_vague_description(desc: str) -> bool:
    d = (desc or "").strip().lower()
    if not d:
        return True
    actions = (
        "выведи", "посчитай", "сложи", "умнож", "раздел", "вычти", "найди",
        "создай", "напиши", "определи", "провер", "сравни", "отсортиру", "print",
    )
    if not any(a in d for a in actions):
        return True
    if re.search(r"(?i)^(сделай|сделайте|создай|создайте)\s+\d+\s+задач", d):
        return True
    if re.search(r"(?i)^\d+\s+(прост|задач)", d):
        return True
    if "массив tasks" in d or "массиве tasks" in d:
        return True
    if re.search(r"(?i)\blevel=\d+", d) and "задач" in d:
        return True
    return False


def is_prompt_echo_task(task: TaskSpec | dict) -> bool:
    desc, out, pat = _task_text_parts(task)
    if not desc:
        return True
    d = desc.lower()
    combined = f"{d} {out.lower()} {pat.lower()}"
    # Эхо инструкции модели (не путать с «Выведи число 5» для ученика)
    if re.search(r"(?i)^сгенерируй(?:те)?\s+(?:ровно\s+)?\d*\s*задач", d):
        return True
    if re.search(r"(?i)^сгенерируй(?:те)?\s+.*\b(json|пул|массив tasks)\b", d):
        return True
    if re.search(r"(?i)^(сделай|сделайте|создай|создайте)\s+\d+\s+задач", d):
        return True
    if "массив tasks" in d or "массиве tasks" in d:
        return True
    if re.search(r"(?i)\blevel=\d+", d) and "задач" in d:
        return True
    if any(m in d for m in _META_DESC_MARKERS):
        return True
    if "задач" in d and ("пул" in d or "фонов" in d):
        return True
    if re.search(r"уровн[ьяе]\s*[0-3]?\s*$", d) and len(d) < 80:
        return True
    return False


def level_curriculum_block(level: int) -> str:
    """Согласовано с docs/EDUCATION.md и docs/notes/."""
    lv = int(level)
    if lv == 0:
        return (
            "Уровень 0 — только print, переменные, арифметика (+ - * /), простой вывод строки или числа.\n"
            "Запрещено: if/else, циклы, списки, функции, input, import, datetime.\n"
            "Задание должно быть понятно новичку с нуля (как в note_01).\n"
        )
    if lv == 1:
        return (
            "Уровень 1 — только if/else, сравнения, чётность, строки (без циклов).\n"
            "Запрещено: for/while, списки как структуры, def, input, import.\n"
        )
    if lv == 2:
        return (
            "Уровень 2 — циклы for/range, обход списка, сумма в цикле, квадраты, len().\n"
            "Запрещено: while, def, input, import, сортировка/min/max как в lvl3.\n"
        )
    return (
        "Уровень 3 — списки: sorted(), min(), max(), sum(), фильтр чётных, конкретный вывод.\n"
        "Запрещено: def, class, import, файлы, input, datetime.\n"
    )


def _ints_in_description(desc: str) -> list[int]:
    return [int(x) for x in re.findall(r"\b(\d+)\b", desc or "")]


def description_output_coherent(task: TaskSpec | dict, level: int) -> bool:
    """Описание и expected_output не противоречат (типичный мусор LLM/каталога)."""
    desc, out, _ = _task_text_parts(task)
    o = (out or "").strip()
    if not desc or not o:
        return False
    d = desc.lower()
    lv = int(level)

    # Уровень 0: «сложи два числа» без конкретных чисел — непригодно
    if lv <= 0 and re.search(r"сложен|сложи|сумм", d) and "списк" not in d:
        nums = _ints_in_description(desc)
        if len(nums) < 2:
            return False

    # Явное сложение двух чисел в тексте
    m = re.search(r"слож\S*\s+(?:числ\w*\s+)?(\d+)\s+и\s+(\d+)", d)
    if m:
        return o == str(int(m.group(1)) + int(m.group(2)))

    # Умножение 7*8 / 7×8
    m = re.search(r"(\d+)\s*[*×]\s*(\d+)", desc)
    if m:
        return o == str(int(m.group(1)) * int(m.group(2)))

    # Сумма списка в квадратных скобках
    if "сумм" in d or "sum(" in d:
        bm = re.search(r"\[([^\]]+)\]", desc)
        if bm:
            try:
                parts = [p.strip() for p in bm.group(1).split(",")]
                nums = [int(p) for p in parts if p.isdigit() or (p.lstrip("-").isdigit())]
                if nums and o.isdigit():
                    return o == str(sum(nums))
            except ValueError:
                pass

    # Уровень 0: одиночное число в ответе — в тексте должно быть откуда оно взялось
    if lv <= 0 and re.fullmatch(r"-?\d+", o):
        if _ints_in_description(desc) and o not in [str(n) for n in _ints_in_description(desc)]:
            # допускаем только если явно формула с этим результатом
            if not re.search(rf"\b{re.escape(o)}\b", desc):
                m2 = re.search(r"слож\S*\s+(?:числ\w*\s+)?(\d+)\s+и\s+(\d+)", d)
                if m2 and str(int(m2.group(1)) + int(m2.group(2))) == o:
                    return True
                m3 = re.search(r"(\d+)\s*[*×]\s*(\d+)", desc)
                if m3 and str(int(m3.group(1)) * int(m3.group(2))) == o:
                    return True
                return False
    return True


def task_uses_forbidden_advanced(task: TaskSpec | dict, level: int) -> bool:
    desc, out, pat = _task_text_parts(task)
    blob = f"{desc} {pat}".lower()
    if any(k in blob for k in _FORBIDDEN_ADVANCED):
        return True
    lv = int(level)
    if lv <= 1 and (re.search(r"\bfor\b", blob) or "range(" in blob or "[" in desc):
        return True
    if lv <= 0 and (re.search(r"\bif\b", blob) or re.search(r"\belse\b", blob)):
        return True
    return False


def is_valid_pool_refill_task(task: TaskSpec | dict, level: int | None = None) -> bool:
    """Мягкая проверка для фонового refill: явный мусор, без жёсткой coherence/clarity."""
    if is_date_related_task(task):
        return False
    if is_prompt_echo_task(task):
        return False
    lv = level
    if lv is None:
        if isinstance(task, TaskSpec):
            lv = int(task.level)
        else:
            try:
                lv = int(task.get("level", 0))
            except Exception:
                lv = 0
    if task_uses_forbidden_advanced(task, lv):
        return False
    desc, out, _ = _task_text_parts(task)
    if len(desc) < 8:
        return False
    if is_vague_description(desc):
        return False
    if is_invalid_expected_output(out):
        return False
    return True


def is_valid_playable_task(task: TaskSpec | dict, level: int | None = None) -> bool:
    """Задача пригодна для игрока (не мусор LLM, не вне программы)."""
    if not is_valid_pool_refill_task(task, level):
        return False
    lv = level
    if lv is None:
        if isinstance(task, TaskSpec):
            lv = int(task.level)
        else:
            try:
                lv = int(task.get("level", 0))
            except Exception:
                lv = 0
    if not description_output_coherent(task, lv):
        return False
    return True

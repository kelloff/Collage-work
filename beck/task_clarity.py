"""
Понятность задания: согласованность description ↔ expected_output (stdout).

Типичная ошибка LLM: «выведи две строки» в тексте, а в expected_output одна склеенная
строка без \\n — или наоборот.
"""
from __future__ import annotations

import re
from typing import TYPE_CHECKING, Tuple

if TYPE_CHECKING:
    from models import TaskSpec


def _norm_out(text: str) -> str:
    return (text or "").replace("\r\n", "\n").replace("\r", "\n")


def _desc_lower(desc: str) -> str:
    return (desc or "").lower()


def output_line_count(expected_output: str) -> int:
    o = _norm_out(expected_output).strip()
    if not o:
        return 0
    return len(o.split("\n"))


def _desc_says_multiline(desc: str) -> bool:
    d = _desc_lower(desc)
    if re.search(r"\b(две|2|три|3|несколько)\s+строк", d):
        return True
    if re.search(r"нов(ой|ая|ую)\s+строк", d):
        return True
    if "на разных строк" in d or "с перенос" in d or "с новой строк" in d:
        return True
    if re.search(r"кажд\w+\s+(print|вывод)", d):
        return True
    return False


def _desc_says_single_line(desc: str) -> bool:
    d = _desc_lower(desc)
    if re.search(r"одн\w+\s+строк", d):
        return True
    if re.search(r"\bскле", d):
        return True
    if "конкатен" in d or "через +" in d or " через плюс" in d:
        return True
    if re.search(r"без\s+перенос", d):
        return True
    return False


def _quoted_fragments(desc: str) -> list[str]:
    return re.findall(r'["«]([^"»]{1,40})["»]', desc or "")


def stdout_clarity_prompt_block(level: int) -> str:
    lv = int(level)
    lines = [
        "Формат вывода (обязательно согласуй description и expected_output):",
        "- Одна строка stdout → в description: «одной строкой» или «склей через + в одном print».",
        "- Несколько строк (в expected_output символ \\n между строками) → "
        "в description: «N строк, каждая с новой строки» или «два print».",
        "- Нельзя писать «две строки», если expected_output без \\n (одна склеенная строка).",
        "- Нельзя требовать склейку в кавычках, если expected_output содержит \\n.",
        "- Если в условии два текста в кавычках и один вывод без \\n — явно: "
        "«склей в одном print: print(\\\"а\\\" + \\\"б\\\")».",
    ]
    if lv == 0:
        lines.append(
            "- Уровень 0: по умолчанию один print, одна строка вывода (без \\n в expected_output)."
        )
    return "\n".join(lines) + "\n"


def clarify_description(desc: str, expected_output: str) -> str:
    """Добавляет короткую подсказку игроку, если модель забыла указать формат вывода."""
    d = (desc or "").strip()
    if not d:
        return d
    out = _norm_out(expected_output)
    if not out.strip():
        return d

    lines = output_line_count(out)
    multiline = lines > 1
    says_ml = _desc_says_multiline(d)
    says_single = _desc_says_single_line(d)
    quoted = _quoted_fragments(d)

    suffix = ""
    if multiline and not says_ml:
        suffix = (
            f" (Вывод: {lines} строки — каждая с новой строки, "
            "отдельный print или \\n в одном print.)"
        )
    elif not multiline and says_ml:
        if len(quoted) >= 2 or "+" in d:
            suffix = (
                " (Выведи одной строкой: склей текст в одном print, "
                f'например print("…" + "…") — ожидается «{out[:50]}».)'
            )
        else:
            suffix = f" (Ожидается одна строка вывода: «{out[:60]}».)"
    elif not multiline and len(quoted) >= 2 and not says_single and not says_ml:
        suffix = (
            " (Склей обе части в одном print через +; вывод — одна строка без переноса.)"
        )
    elif not multiline and lines == 1 and not says_single and "+" in out:
        pass

    if not suffix:
        return d
    if suffix.strip(" ()") in d:
        return d
    return d.rstrip(".!?") + suffix


def is_stdout_description_ambiguous(desc: str, expected_output: str) -> bool:
    """Несовместимые указания — такую задачу не отдаём игроку."""
    d = _desc_lower(desc)
    out = _norm_out(expected_output).strip()
    if not d or not out:
        return True

    lines = output_line_count(out)
    multiline = lines > 1
    says_ml = _desc_says_multiline(d)
    says_single = _desc_says_single_line(d)

    if multiline and says_single:
        return True
    if not multiline and says_ml and says_single:
        return True

    # «две строки» при однострочном выводе — исправит clarify; не режем здесь
    if not multiline and says_ml:
        return False

    # многострочный вывод без намёка — clarify добавит подсказку
    if multiline and not says_ml:
        return False

    return False


def normalize_task_clarity(task: "TaskSpec | dict") -> Tuple[dict, bool]:
    """
    Возвращает (dict задачи, ok).
    ok=False — задачу отбрасываем.
    """
    if isinstance(task, TaskSpec):
        d = task.model_dump()
    else:
        d = dict(task)

    desc = str(d.get("description", "")).strip()
    out = str(d.get("expected_output", "")).strip()
    if not desc or not out:
        return d, False

    if is_stdout_description_ambiguous(desc, out):
        return d, False

    new_desc = clarify_description(desc, out)
    d["description"] = new_desc

    if is_stdout_description_ambiguous(new_desc, out):
        return d, False

    return d, True

"""
Разнообразие заданий: print может быть много, но контекст и ожидаемый вывод — разные.
Блокируем «Привет друг» / «Привет друг как дела» три раза подряд, а не print вообще.
"""
from __future__ import annotations

import os
import re
from collections import defaultdict
from typing import Any

_GREETING = ("привет", "hello", "hi ", "добрый", "как дела", "здравств")

def similar_group_max() -> int:
    """Сколько похожих задач допустимо на уровень (2–3 по умолчанию, не больше)."""
    raw = (os.getenv("TASK_SIMILAR_MAX_PER_GROUP") or "").strip()
    if raw:
        return max(1, int(raw))
    legacy = (os.getenv("TASK_SAME_OUTPUT_FAMILY_MAX") or "").strip()
    if legacy:
        return max(1, int(legacy))
    return 3


def greeting_context_max() -> int:
    raw = (os.getenv("TASK_GREETING_CONTEXT_MAX_PER_LEVEL") or "").strip()
    if raw:
        return max(1, int(raw))
    return similar_group_max()


def _normalize_text(s: str) -> str:
    d = (s or "").lower().strip()
    d = re.sub(r'["\'][^"\']*["\']', " STR ", d)
    d = re.sub(r"\d+", " N ", d)
    d = re.sub(r"[^\w\s]+", " ", d, flags=re.UNICODE)
    d = re.sub(r"\s+", " ", d)
    return d.strip()


def _normalize_output(out: str) -> str:
    o = (out or "").lower().strip()
    o = re.sub(r"\s+", " ", o)
    return o


def descriptions_too_similar(a: str, b: str) -> bool:
    if not a or not b:
        return False
    na, nb = _normalize_text(a), _normalize_text(b)
    if not na or not nb:
        return False
    if na == nb:
        return True
    short, long = (na, nb) if len(na) <= len(nb) else (nb, na)
    if len(short) >= 10 and short in long:
        return True
    wa, wb = set(na.split()), set(nb.split())
    if not wa or not wb:
        return False
    inter = len(wa & wb)
    union = len(wa | wb)
    threshold = 0.62
    if any(g in na and g in nb for g in _GREETING):
        threshold = 0.38
    if union > 0 and inter / union >= threshold:
        return True
    return False


def outputs_too_similar(a: str, b: str) -> bool:
    if not a or not b:
        return False
    na, nb = _normalize_output(a), _normalize_output(b)
    if not na or not nb:
        return False
    if na == nb:
        return True
    if re.fullmatch(r"\d+", na) and re.fullmatch(r"\d+", nb):
        return na == nb
    short, long = (na, nb) if len(na) <= len(nb) else (nb, na)
    if len(short) >= 4 and short in long:
        return True
    wa = set(re.findall(r"[\w]+", na, flags=re.UNICODE))
    wb = set(re.findall(r"[\w]+", nb, flags=re.UNICODE))
    if len(wa) < 2 or len(wb) < 2:
        return False
    return descriptions_too_similar(na, nb)


def _has_greeting(text: str) -> bool:
    t = (text or "").lower()
    return any(g in t for g in _GREETING)


def output_family_key(expected_output: str, context: str = "") -> str:
    """Ключ «одинакового смысла» вывода: одна приветственная строка = одно семейство."""
    o = _normalize_output(expected_output)
    if not o:
        return "empty"
    if re.search(r"\d", o) and not _has_greeting(o):
        digits = re.sub(r"\D", "", o) or o[:24]
        if context and context not in ("other_lvl0", "print_number", "print_generic"):
            return f"num:{digits}:{context}"
        return f"num:{digits}"
    words = re.findall(r"[\w]+", o, flags=re.UNICODE)
    if not words:
        return "text:empty"
    head = " ".join(words[:5])
    if _has_greeting(o):
        greet = next((g for g in _GREETING if g in o), "greet")
        return f"greet:{greet}:{head}"
    return f"text:{head}"


def task_context_key(
    level: int,
    description: str,
    required_patterns: str = "",
    expected_output: str = "",
) -> str:
    """Навык/контекст задания — чтобы не дублировать один сценарий."""
    d = (description or "").lower()
    pat = (required_patterns or "").lower()
    e = (expected_output or "").lower()

    if int(level) == 0:
        if any(x in d for x in ("умнож", "произведен")) or "*" in pat:
            return "math_mul"
        if any(x in d for x in ("делен", "делит")) or "/" in pat:
            return "math_div"
        if any(x in d for x in ("больше", "меньше", "сравн", "равн")):
            return "compare"
        if any(x in d for x in ("слож", "вычти", "сумм")) or re.search(r"[+\-]", pat):
            return "math_addsub"
        if "переменн" in d:
            return "var_print"
        if _has_greeting(d) or _has_greeting(e):
            return "greeting_print"
        if re.search(r"\d", e) and not _has_greeting(e):
            return "print_number"
        if re.search(r"выведи|вывести|напечатай", d) or "print" in pat:
            return "print_literal"
        return "other_lvl0"

    if int(level) == 1:
        if "if" in d or "иначе" in d:
            return "if_else"
        return "other_lvl1"
    if int(level) == 2:
        if any(x in d for x in ("цикл", "список", "for ", "range")):
            return "loop_list"
        return "other_lvl2"
    return "other"


def topic_limit(level: int, topic: str) -> int:
    """Совместимость со старым API; жёстких лимитов на print больше нет."""
    return 45


def task_skill_topic(level: int, description: str, required_patterns: str = "") -> str:
    return task_context_key(level, description, required_patterns, "")


def _count_families_and_contexts(tasks: list[dict[str, Any]]) -> tuple[dict[str, int], dict[str, int]]:
    families: dict[str, int] = defaultdict(int)
    contexts: dict[str, int] = defaultdict(int)
    for t in tasks:
        if not isinstance(t, dict):
            continue
        lv = int(t.get("level", 0))
        desc = str(t.get("description", ""))
        pat = str(t.get("required_patterns", ""))
        out = str(t.get("expected_output", ""))
        ctx = task_context_key(lv, desc, pat, out)
        fam = output_family_key(out, ctx)
        families[f"{lv}:{fam}"] += 1
        contexts[f"{lv}:{ctx}"] += 1
    return dict(families), dict(contexts)


def tasks_too_close(existing: dict[str, Any], candidate: dict[str, Any]) -> bool:
    ed = str(existing.get("description", ""))
    cd = str(candidate.get("description", ""))
    eo = str(existing.get("expected_output", ""))
    co = str(candidate.get("expected_output", ""))
    pat_e = str(existing.get("required_patterns", ""))
    pat_c = str(candidate.get("required_patterns", ""))
    lv = int(existing.get("level", candidate.get("level", 0)))

    ctx_e = task_context_key(lv, ed, pat_e, eo)
    ctx_c = task_context_key(lv, cd, pat_c, co)
    if outputs_too_similar(eo, co):
        no, nc = _normalize_output(eo), _normalize_output(co)
        if not (
            ctx_e != ctx_c
            and re.fullmatch(r"\d+", no or "")
            and re.fullmatch(r"\d+", nc or "")
        ):
            return True
    fam_e, fam_c = output_family_key(eo, ctx_e), output_family_key(co, ctx_c)
    if fam_e == fam_c and fam_c not in ("empty", "text:empty"):
        return True

    # Разный навык (умножение vs деление) — не режем по похожим словам «выведи…»
    if ctx_e != ctx_c:
        return False
    if descriptions_too_similar(ed, cd):
        return True
    return False


def count_tasks_close_to(
    candidate: dict[str, Any],
    existing: list[dict[str, Any]],
) -> int:
    lv = int(candidate.get("level", 0))
    n = 0
    for ex in existing:
        if int(ex.get("level", 0)) != lv:
            continue
        if tasks_too_close(ex, candidate):
            n += 1
    return n


def can_accept_catalog_task(
    task: dict[str, Any],
    pool_tasks: list[dict[str, Any]] | None = None,
    batch_tasks: list[dict[str, Any]] | None = None,
) -> bool:
    """Каталог: только точный дубликат expected_output на том же уровне — не режем «похожие»."""
    lv = int(task.get("level", 0))
    out = str(task.get("expected_output", "")).strip()
    if not str(task.get("description", "")).strip() or not out:
        return False
    combined: list[dict[str, Any]] = []
    if pool_tasks:
        combined.extend(pool_tasks)
    if batch_tasks:
        combined.extend(batch_tasks)
    for ex in combined:
        if int(ex.get("level", 0)) != lv:
            continue
        if _normalize_output(str(ex.get("expected_output", ""))) == _normalize_output(out):
            return False
    return True


def can_accept_task(
    task: dict[str, Any] | Any,
    pool_tasks: list[dict[str, Any]] | None = None,
    batch_tasks: list[dict[str, Any]] | None = None,
    *,
    pool_total: int | None = None,
) -> bool:
    try:
        import os

        relax = int(os.getenv("TASK_POOL_RELAX_BELOW_TOTAL", "0"))
        if relax > 0:
            if pool_total is None:
                import task_pool

                pool_total = task_pool.total()
            if pool_total < relax:
                td = task if isinstance(task, dict) else task.model_dump()
                return can_accept_catalog_task(td, pool_tasks, batch_tasks)
    except Exception:
        pass

    if isinstance(task, dict):
        lv = int(task.get("level", 0))
        desc = str(task.get("description", "")).strip()
        pat = str(task.get("required_patterns", ""))
        out = str(task.get("expected_output", "")).strip()
    else:
        lv = int(getattr(task, "level", 0))
        desc = str(getattr(task, "description", "")).strip()
        pat = str(getattr(task, "required_patterns", ""))
        out = str(getattr(task, "expected_output", "")).strip()

    if not desc:
        return False

    combined: list[dict[str, Any]] = []
    if pool_tasks:
        combined.extend(pool_tasks)
    if batch_tasks:
        combined.extend(batch_tasks)

    candidate = {"level": lv, "description": desc, "required_patterns": pat, "expected_output": out}
    mx = similar_group_max()
    if count_tasks_close_to(candidate, combined) >= mx:
        return False

    families, contexts = _count_families_and_contexts(
        [t for t in combined if int(t.get("level", 0)) == lv]
    )
    ctx = task_context_key(lv, desc, pat, out)
    fam_key = f"{lv}:{output_family_key(out, ctx)}"
    if families.get(fam_key, 0) >= mx:
        return False

    ctx_key = f"{lv}:{ctx}"
    if ctx == "greeting_print" and contexts.get(ctx_key, 0) >= greeting_context_max():
        return False

    return True


def filter_diverse_tasks(
    tasks: list[Any],
    pool_tasks: list[dict[str, Any]] | None = None,
) -> list[Any]:
    pool = list(pool_tasks or [])
    accepted: list[Any] = []
    batch_dicts: list[dict[str, Any]] = []

    for t in tasks:
        if isinstance(t, dict):
            d = dict(t)
        elif hasattr(t, "model_dump"):
            d = t.model_dump()
        else:
            continue
        if not can_accept_task(d, pool, batch_dicts):
            continue
        accepted.append(t)
        batch_dicts.append(d)

    return accepted


def pool_few_shot_example(level: int) -> str:
    """Короткий образец JSON — модель копирует структуру, не текст задания."""
    lv = int(level)
    samples = {
        0: (
            '{"tasks":[{"level":0,"category":"easy","description":"Выведи произведение 6 и 7",'
            '"expected_output":"42","required_patterns":"","check_type":"stdout_exact",'
            '"required_keywords":"","allow_direct_print":0}]}'
        ),
        1: (
            '{"tasks":[{"level":1,"category":"easy","description":"Если 8 чётное — выведи Да, иначе Нет",'
            '"expected_output":"Да","required_patterns":"if else","check_type":"stdout_exact",'
            '"required_keywords":"","allow_direct_print":0}]}'
        ),
        2: (
            '{"tasks":[{"level":2,"category":"medium","description":"Суммируй 2, 3 и 5 в цикле for",'
            '"expected_output":"10","required_patterns":"for","check_type":"stdout_exact",'
            '"required_keywords":"","allow_direct_print":0}]}'
        ),
        3: (
            '{"tasks":[{"level":3,"category":"easy","description":"Отсортируй [3,1,2] и выведи через пробел",'
            '"expected_output":"1 2 3","required_patterns":"","check_type":"stdout_exact",'
            '"required_keywords":"","allow_direct_print":0}]}'
        ),
    }
    return f"Образец формата (не копируй текст задания): {samples.get(lv, samples[0])}\n"


def pool_refill_prompt_block(level: int) -> str:
    """Промпт для фонового пула: ИИ-задачи должны отличаться друг от друга."""
    from task_filters import level_curriculum_block

    base = diversity_prompt_block(level)
    return (
        base
        + level_curriculum_block(level)
        + pool_few_shot_example(level)
        + "description — что сделать ученику (русский текст), не команда модели.\n"
        + "Запрещено в description: сгенерируй, JSON, пул, верни, уровень N как заголовок.\n"
        + "expected_output — точный stdout (число, слово или строки через \\n).\n"
        + "Каждая новая задача — другой навык/числа/формулировка/ожидаемый вывод.\n"
        + "Запрещено копировать шаблоны из списка «не повторяй» и из каталога курса.\n"
        + "allow_direct_print=1 только если без print нельзя; иначе 0.\n"
    )


def diversity_prompt_block(level: int) -> str:
    lv = int(level)
    lines = [
        "Задания в батче должны отличаться КОНТЕКСТОМ и ожидаемым выводом, не только словами в кавычках.",
        "Нельзя дважды дать «выведи Привет друг» / «Привет мир» с тем же смыслом — это один шаблон.",
    ]
    if lv == 0:
        lines.extend(
            [
                "print() — нормально и часто, но чередуй навыки: переменная+print, сложение/вычитание, умножение, деление, сравнение больше/меньше, разные числа и фразы.",
                "Не делай несколько заданий подряд с одной приветственной строкой (Привет друг, Привет как дела и т.п.).",
                "expected_output у каждой задачи должен быть уникальным по смыслу.",
            ]
        )
    elif lv == 1:
        lines.append("Чередуй if/else: числа, чётность, строки, сравнения — без копий формулировок и вывода.")
    elif lv >= 2:
        lines.append("Чередуй циклы, списки, суммы — разный контекст, без дубликатов вывода.")
    return "\n".join(lines) + "\n"

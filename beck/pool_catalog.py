"""Каталог в пул (seed / дозаполнение, когда Ollama не успел)."""
from __future__ import annotations

from typing import Any, List

from tasks_fallback_catalog import FALLBACK_TASKS_BY_LEVEL, catalog_tasks_for_level


def _outputs_on_level(tasks: list[dict[str, Any]] | None, level: int) -> set[str]:
    outs: set[str] = set()
    for t in tasks or []:
        if int(t.get("level", 0)) != int(level):
            continue
        o = str(t.get("expected_output", "")).strip()
        if o:
            outs.add(o)
    return outs


def all_catalog_pool_tasks() -> List[dict[str, Any]]:
    out: List[dict[str, Any]] = []
    for lv, items in FALLBACK_TASKS_BY_LEVEL.items():
        for t in items:
            d = dict(t)
            d["level"] = int(lv)
            out.append(d)
    return out


def catalog_refill_batch(
    level: int,
    count: int,
    pool_tasks: list[dict[str, Any]] | None = None,
) -> List[dict[str, Any]]:
    """Задачи каталога, которых ещё нет в пуле (по expected_output на уровне)."""
    import task_diversity

    lv = int(level)
    need = max(1, count)
    have = _outputs_on_level(pool_tasks, lv)
    out: List[dict[str, Any]] = []
    for t in FALLBACK_TASKS_BY_LEVEL.get(lv, []):
        if len(out) >= need:
            break
        out_str = str(t.get("expected_output", "")).strip()
        if not out_str or out_str in have:
            continue
        d = dict(t)
        d["level"] = lv
        d["_from_catalog"] = True
        if not task_diversity.can_accept_catalog_task(d, pool_tasks, out):
            continue
        out.append(d)
        have.add(out_str)
    return out


def catalog_tasks_for_level_unused(
    level: int,
    count: int,
    pool_tasks: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Алиас для seed: только ещё не лежащие в пуле шаблоны."""
    batch = catalog_refill_batch(level, count, pool_tasks)
    return [{k: v for k, v in t.items() if k != "_from_catalog"} for t in batch]

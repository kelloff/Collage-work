from typing import List
import os
import time

from fastapi import APIRouter, HTTPException

import task_pool
from app_context import AppContext
from generate_service import fallback_generate_tasks, strip_fallback_tasks
from models import (
    GenerateTasksMultiRequest,
    GenerateTasksRequest,
    GenerateTasksResponse,
    TaskSpec,
)


def _fallback_on_miss_enabled() -> bool:
    """1 = отдать шаблонные задачи (200), если пул+Ollama не успели. 0 = HTTP 503."""
    v = os.getenv("GENERATE_FALLBACK_ON_MISS", "1")
    return v.strip().lower() in ("1", "true", "yes", "on")


def _fallback_multi(levels: List[int], count_per_level: int) -> GenerateTasksResponse:
    tasks: List[TaskSpec] = []
    for lvl in levels:
        tasks.extend(fallback_generate_tasks(int(lvl), count_per_level))
    print(
        f"generate_tasks_multi: serving built-in fallback "
        f"{len(tasks)} tasks (levels={levels}, n={count_per_level})"
    )
    return GenerateTasksResponse(tasks=tasks, source="fallback")


def _serial_per_level(
    ctx: AppContext,
    levels: List[int],
    n: int,
    expected: int,
    max_attempts: int = 5,
) -> List[TaskSpec]:
    """По очереди 0→3: до n задач на уровень."""
    out2: List[TaskSpec] = []
    for lvl in levels:
        level_tasks: List[TaskSpec] = []
        attempts = 0
        while len(level_tasks) < n and attempts < max_attempts:
            attempts += 1
            need = n - len(level_tasks)
            print(
                f"generate_tasks_multi: ollama lvl={int(lvl)} "
                f"attempt={attempts} need={need}"
            )
            t, used_fb = ctx.generate_tasks_via_ollama(int(lvl), need)
            if used_fb or not t:
                print(
                    f"generate_tasks_multi: ollama lvl={int(lvl)} "
                    f"attempt={attempts} returned 0 tasks"
                )
                break
            level_tasks.extend(strip_fallback_tasks(t)[:need])
            print(
                f"generate_tasks_multi: ollama lvl={int(lvl)} "
                f"attempt={attempts} got_now={len(t[:need])}, "
                f"level_total={len(level_tasks)}/{n}"
            )
        print(
            f"generate_tasks_multi: ollama lvl={int(lvl)} "
            f"final={len(level_tasks[:n])}/{n}"
        )
        out2.extend(level_tasks[:n])
    if len(out2) >= expected:
        print(
            f"generate_tasks_multi: serial complete total={len(out2[:expected])}/{expected}"
        )
    return out2


def _top_up_after_partial(
    ctx: AppContext,
    base: List[TaskSpec],
    levels: List[int],
    n: int,
    expected: int,
    max_attempts: int = 5,
) -> List[TaskSpec]:
    """Добирает недостающие задачи по уровням (пул + Ollama)."""
    out: List[TaskSpec] = []
    for lvl in levels:
        lv = int(lvl)
        level_tasks = [t for t in base if int(t.level) == lv][:n]
        attempts = 0
        while len(level_tasks) < n and attempts < max_attempts:
            attempts += 1
            need = n - len(level_tasks)
            print(
                f"generate_tasks_multi: topup lvl={lv} attempt={attempts} need={need}"
            )
            t, used_fb = ctx.generate_tasks_via_ollama(lv, need)
            if used_fb or not t:
                break
            level_tasks.extend(strip_fallback_tasks(t)[:need])
        print(f"generate_tasks_multi: topup lvl={lv} final={len(level_tasks[:n])}/{n}")
        out.extend(level_tasks[:n])
    if len(out) >= expected:
        print(
            f"generate_tasks_multi: topup complete total={len(out[:expected])}/{expected}"
        )
    return out


def _serve_multi_from_pool_and_llm(
    ctx: AppContext,
    levels: List[int],
    n: int,
    expected: int,
) -> GenerateTasksResponse:
    pooled = task_pool.try_pop_partial_batch(levels, n)
    base = [TaskSpec(**d) for d in pooled]
    if len(base) >= expected:
        print(f"generate_tasks_multi: served from pool {len(base)}/{expected}")
        ctx.trigger_async_refill_once()
        return GenerateTasksResponse(tasks=base[:expected], source="pool")

    combined: List[TaskSpec] = list(base)
    one_src = ""

    if ctx.settings.multi_oneshot_first:
        print(
            f"generate_tasks_multi: pool {len(base)}/{expected} → "
            f"one_shot 3b ({ctx.settings.ollama_model})"
        )
        one, one_src = ctx.generate_all_levels_via_ollama_one_shot(levels, n)
        one = strip_fallback_tasks(one)
        if one:
            combined.extend(one)
            print(f"generate_tasks_multi: one_shot got {len(one)} tasks ({one_src})")

    merged = _top_up_after_partial(ctx, combined, levels, n, expected)
    if len(merged) >= expected:
        if base and one_src:
            src = f"pool+ollama_{one_src}"
        elif base:
            src = "pool+ollama"
        elif one_src:
            src = f"ollama_{one_src}"
        else:
            src = "ollama"
        print(f"generate_tasks_multi: {src} {len(merged[:expected])}/{expected}")
        ctx.trigger_async_refill_once()
        return GenerateTasksResponse(tasks=merged[:expected], source=src)

    if ctx.client:
        out: List[TaskSpec] = list(merged)
        for lvl in levels:
            lv = int(lvl)
            have = len([t for t in out if int(t.level) == lv])
            need = max(0, n - have)
            if need <= 0:
                continue
            t, src = ctx.llm_generate_tasks(lv, need)
            t = strip_fallback_tasks(t)
            if t:
                out.extend(t[:need])
        if len(out) >= expected:
            return GenerateTasksResponse(tasks=out[:expected], source="openai_multi")

    if not ctx.settings.multi_oneshot_first:
        one, one_src = ctx.generate_all_levels_via_ollama_one_shot(levels, n)
        one = strip_fallback_tasks(one)
        merged2 = _top_up_after_partial(ctx, merged + one, levels, n, expected)
        if len(merged2) >= expected:
            return GenerateTasksResponse(
                tasks=merged2[:expected],
                source="pool+ollama" if base else f"ollama_{one_src}",
            )

    out2 = _serial_per_level(ctx, levels, n, expected)
    merged3 = _top_up_after_partial(ctx, merged + out2, levels, n, expected)
    if len(merged3) >= expected:
        return GenerateTasksResponse(tasks=merged3[:expected], source="ollama_serial")

    if _fallback_on_miss_enabled():
        return _fallback_multi(levels, n)

    raise HTTPException(
        status_code=503,
        detail=(
            f"Could not generate {expected} tasks from pool/LLM "
            f"(got {len(merged3)}). Retry later."
        ),
    )


def create_generate_router(ctx: AppContext) -> APIRouter:
    router = APIRouter(tags=["generate"])

    @router.post("/generate_tasks_multi", response_model=GenerateTasksResponse)
    def generate_tasks_multi(req: GenerateTasksMultiRequest):
        try:
            levels = req.levels if req.levels else [0, 1, 2, 3]
            n = req.count_per_level
            expected = len(levels) * n
            print(
                f"generate_tasks_multi: start levels={levels}, "
                f"count_per_level={n}, expected_total={expected}, "
                f"pool_total={task_pool.total()}"
            )
            return _serve_multi_from_pool_and_llm(ctx, levels, n, expected)
        finally:
            task_pool.schedule_refill_if_low()

    @router.post("/generate_tasks", response_model=GenerateTasksResponse)
    def generate_tasks(req: GenerateTasksRequest):
        pooled = task_pool.try_pop_for_level(req.level, req.count)
        if len(pooled) >= req.count:
            ctx.trigger_async_refill_once()
            return GenerateTasksResponse(
                tasks=[TaskSpec(**d) for d in pooled[: req.count]],
                source="pool",
            )

        base = [TaskSpec(**d) for d in pooled]
        merged = _top_up_after_partial(
            ctx, base, [req.level], req.count, req.count
        )
        if len(merged) >= req.count:
            src = "pool+ollama" if base else "ollama"
            ctx.trigger_async_refill_once()
            return GenerateTasksResponse(tasks=merged[: req.count], source=src)

        tasks, source = ctx.llm_generate_tasks(req.level, req.count)
        tasks = strip_fallback_tasks(tasks)
        if tasks:
            return GenerateTasksResponse(tasks=tasks[: req.count], source=source)

        if _fallback_on_miss_enabled():
            fb = fallback_generate_tasks(req.level, req.count)
            return GenerateTasksResponse(tasks=fb, source="fallback")

        raise HTTPException(
            status_code=503,
            detail=f"Could not generate {req.count} tasks for level {req.level}",
        )

    return router

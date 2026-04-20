from typing import List
import time

from fastapi import APIRouter

import task_pool
from app_context import AppContext
from generate_service import fallback_generate_tasks
from models import (
    GenerateTasksMultiRequest,
    GenerateTasksRequest,
    GenerateTasksResponse,
    TaskSpec,
)


def _serial_per_level(
    ctx: AppContext,
    levels: List[int],
    n: int,
    expected: int,
) -> List[TaskSpec]:
    """По очереди 0→3: до n задач на уровень, до 3 попыток на уровень."""
    out2: List[TaskSpec] = []
    for lvl in levels:
        level_tasks: List[TaskSpec] = []
        attempts = 0
        while len(level_tasks) < n and attempts < 3:
            attempts += 1
            need = n - len(level_tasks)
            print(
                f"generate_tasks_multi: ollama lvl={int(lvl)} "
                f"attempt={attempts} need={need}"
            )
            t, _ = ctx.generate_tasks_via_ollama(int(lvl), need)
            if not t:
                print(
                    f"generate_tasks_multi: ollama lvl={int(lvl)} "
                    f"attempt={attempts} returned 0 tasks"
                )
                break
            level_tasks.extend(t[:need])
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


def _fill_with_local_fallback(
    tasks: List[TaskSpec],
    levels: List[int],
    n: int,
) -> List[TaskSpec]:
    out: List[TaskSpec] = list(tasks)
    for lvl in levels:
        lv = int(lvl)
        have = len([t for t in out if int(t.level) == lv])
        need = max(0, n - have)
        if need <= 0:
            continue
        out.extend(fallback_generate_tasks(lv, need))
    return out


def _top_up_after_partial_oneshot(
    ctx: AppContext,
    base: List[TaskSpec],
    levels: List[int],
    n: int,
    expected: int,
) -> List[TaskSpec]:
    """Добирает недостающие задачи по уровням после неполного one-shot."""
    out: List[TaskSpec] = []
    for lvl in levels:
        lv = int(lvl)
        level_tasks = [t for t in base if int(t.level) == lv][:n]
        attempts = 0
        while len(level_tasks) < n and attempts < 3:
            attempts += 1
            need = n - len(level_tasks)
            print(
                f"generate_tasks_multi: topup lvl={lv} attempt={attempts} need={need}"
            )
            t, _ = ctx.generate_tasks_via_ollama(lv, need)
            if not t:
                break
            level_tasks.extend(t[:need])
        print(f"generate_tasks_multi: topup lvl={lv} final={len(level_tasks[:n])}/{n}")
        out.extend(level_tasks[:n])
    if len(out) >= expected:
        print(
            f"generate_tasks_multi: oneshot+topup complete total={len(out[:expected])}/{expected}"
        )
    return out


def create_generate_router(ctx: AppContext) -> APIRouter:
    router = APIRouter(tags=["generate"])

    @router.post("/generate_tasks_multi", response_model=GenerateTasksResponse)
    def generate_tasks_multi(req: GenerateTasksMultiRequest):
        try:
            started_at = time.monotonic()
            max_s = max(30, int(ctx.settings.generate_max_seconds))
            levels = req.levels if req.levels else [0, 1, 2, 3]
            n = req.count_per_level
            expected = len(levels) * n
            os_first = ctx.settings.multi_oneshot_first
            print(
                f"generate_tasks_multi: start levels={levels}, "
                f"count_per_level={n}, expected_total={expected}, "
                f"oneshot_first={os_first}, max_seconds={max_s}"
            )

            pooled = task_pool.try_pop_batch(levels, n)
            if pooled is not None and len(pooled) == expected:
                tasks = [TaskSpec(**d) for d in pooled]
                print(f"generate_tasks_multi: served from pool {len(tasks)}/{expected}")
                ctx.trigger_async_refill_once()
                return GenerateTasksResponse(tasks=tasks, source="pool")

            if ctx.client:
                out: List[TaskSpec] = []
                for lvl in levels:
                    t, _ = ctx.llm_generate_tasks(int(lvl), n)
                    out.extend(t)
                    print(
                        f"generate_tasks_multi: openai lvl={int(lvl)} "
                        f"got={len(t)}/{n}, total={len(out)}/{expected}"
                    )
                return GenerateTasksResponse(tasks=out, source="openai_multi")

            # --- Ollama (без OpenAI) ---
            if os_first:
                print("generate_tasks_multi: trying one-shot first (speed)")
                one, src = ctx.generate_all_levels_via_ollama_one_shot(levels, n)
                if len(one) >= expected:
                    return GenerateTasksResponse(
                        tasks=one[:expected], source=src
                    )
                if one:
                    print(
                        f"generate_tasks_multi: one-shot partial {len(one)}/{expected}, top-up"
                    )
                merged = _top_up_after_partial_oneshot(
                    ctx, one, levels, n, expected
                )
                if len(merged) >= expected:
                    return GenerateTasksResponse(
                        tasks=merged[:expected], source="ollama_oneshot_plus_serial"
                    )

                if time.monotonic() - started_at > max_s:
                    final_tasks = _fill_with_local_fallback(merged, levels, n)
                    print(
                        f"generate_tasks_multi: deadline hit -> local fallback fill "
                        f"{len(final_tasks[:expected])}/{expected}"
                    )
                    return GenerateTasksResponse(
                        tasks=final_tasks[:expected],
                        source="ollama_timeout_local_fallback",
                    )

                one2, src2 = ctx.generate_all_levels_via_ollama_one_shot(levels, n)
                merged2 = merged + one2
                if len(merged2) >= expected:
                    return GenerateTasksResponse(
                        tasks=merged2[:expected],
                        source=f"ollama_oneshot_retry_{src2}",
                    )
                print(
                    f"generate_tasks_multi: partial merged={len(merged2)}/{expected}"
                )
                final_tasks = _fill_with_local_fallback(merged2, levels, n)
                return GenerateTasksResponse(
                    tasks=final_tasks[:expected], source="ollama_partial_local_fallback"
                )

            # По умолчанию: сначала поуровнево (предсказуемо), потом one-shot
            out2 = _serial_per_level(ctx, levels, n, expected)
            if len(out2) >= expected:
                return GenerateTasksResponse(
                    tasks=out2[:expected], source="ollama_serial"
                )

            if time.monotonic() - started_at > max_s:
                final_tasks = _fill_with_local_fallback(out2, levels, n)
                print(
                    f"generate_tasks_multi: deadline hit (serial path) -> local fallback fill "
                    f"{len(final_tasks[:expected])}/{expected}"
                )
                return GenerateTasksResponse(
                    tasks=final_tasks[:expected], source="ollama_serial_timeout_local_fallback"
                )

            one, src = ctx.generate_all_levels_via_ollama_one_shot(levels, n)
            merged = out2 + one
            if len(merged) >= expected:
                print(
                    f"generate_tasks_multi: serial+one_shot complete "
                    f"serial={len(out2)}, oneshot={len(one)}, total={len(merged[:expected])}/{expected}"
                )
                return GenerateTasksResponse(
                    tasks=merged[:expected], source=f"ollama_serial_plus_{src}"
                )

            print(
                f"generate_tasks_multi: partial serial={len(out2)}, "
                f"oneshot={len(one)}, total={len(merged)}/{expected}"
            )
            final_tasks = _fill_with_local_fallback(merged, levels, n)
            return GenerateTasksResponse(
                tasks=final_tasks[:expected], source="ollama_partial_local_fallback"
            )
        finally:
            task_pool.schedule_refill_if_low()

    @router.post("/generate_tasks", response_model=GenerateTasksResponse)
    def generate_tasks(req: GenerateTasksRequest):
        tasks, source = ctx.llm_generate_tasks(req.level, req.count)
        if not tasks:
            tasks = fallback_generate_tasks(req.level, req.count)
            source = "fallback"
        return GenerateTasksResponse(tasks=tasks, source=source)

    return router

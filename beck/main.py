from typing import List, Optional
import os
import threading

from fastapi import FastAPI
from openai import OpenAI

import task_pool
from app_context import AppContext
from generate_service import (
    generate_all_levels_via_ollama_one_shot,
    generate_tasks_via_ollama,
    llm_generate_tasks,
    refill_one_batch,
)
from routes import register_routes
from settings import load_settings

SETTINGS = load_settings()

app = FastAPI(title="CollageWork AI Backend")

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
client: Optional[OpenAI] = None
if OPENAI_API_KEY:
    client = OpenAI(api_key=OPENAI_API_KEY)
else:
    print("beck/main.py: OPENAI_API_KEY is not set. /generate_tasks will fail.")

POOL_LEVELS = [0, 1, 2, 3]
POOL_TARGET_PER_LEVEL = int(os.getenv("TASK_POOL_TARGET_PER_LEVEL", "75"))
POOL_REFILL_CHUNK = int(os.getenv("TASK_POOL_REFILL_CHUNK", "5"))


def _llm_generate_tasks(level: int, count: int):
    return llm_generate_tasks(
        level=level,
        count=count,
        client=client,
        ollama_base_url=SETTINGS.ollama_base_url,
        ollama_model=SETTINGS.ollama_model,
        ollama_num_predict=SETTINGS.ollama_num_predict,
        ollama_temperature=SETTINGS.ollama_temperature,
        ollama_single_timeout=SETTINGS.ollama_single_timeout,
        ollama_extra_options=SETTINGS.ollama_extra_options(),
    )


def _generate_tasks_via_ollama(level: int, count: int):
    return generate_tasks_via_ollama(
        level=level,
        count=count,
        ollama_base_url=SETTINGS.ollama_base_url,
        ollama_model=SETTINGS.ollama_model,
        ollama_num_predict=SETTINGS.ollama_num_predict,
        ollama_temperature=SETTINGS.ollama_temperature,
        timeout_s=SETTINGS.ollama_single_timeout,
        extra_options=SETTINGS.ollama_extra_options(),
    )


def _generate_all_levels_via_ollama_one_shot(levels: List[int], count_per_level: int):
    return generate_all_levels_via_ollama_one_shot(
        levels=levels,
        count_per_level=count_per_level,
        ollama_base_url=SETTINGS.ollama_base_url,
        ollama_model=SETTINGS.ollama_model,
        ollama_multi_num_predict=SETTINGS.ollama_multi_num_predict,
        ollama_temperature=SETTINGS.ollama_temperature,
        ollama_multi_timeout=SETTINGS.ollama_multi_timeout,
        extra_options=SETTINGS.ollama_extra_options(),
        for_pool=False,
    )


def _refill_kwargs() -> dict:
    return {
        "ollama_base_url": SETTINGS.ollama_refill_base_url,
        "ollama_model": SETTINGS.ollama_refill_model,
        "ollama_num_predict": SETTINGS.ollama_pool_num_predict,
        "ollama_temperature": SETTINGS.ollama_pool_temperature,
        "timeout_s": SETTINGS.ollama_pool_timeout,
        "extra_options": SETTINGS.ollama_pool_extra_options(),
        "max_attempts": SETTINGS.ollama_pool_max_attempts,
    }


def _refill_one_batch() -> List[dict]:
    return refill_one_batch(
        POOL_LEVELS,
        POOL_TARGET_PER_LEVEL,
        POOL_REFILL_CHUNK,
        **_refill_kwargs(),
    )


def _trigger_async_refill_once() -> None:
    def worker() -> None:
        try:
            import ollama_coordinator

            ollama_coordinator.wait_if_check_active()
            batch = _refill_one_batch()
            if batch:
                task_pool.add_tasks(batch)
                print(f"task_pool: async refill after pop +{len(batch)}")
        except Exception as e:
            print(f"task_pool: async refill error: {e}")

    threading.Thread(target=worker, daemon=True).start()


def _retry_pending_refill(level: int, count: int) -> None:
    from pool_refill import retry_pending_refill

    retry_pending_refill(level, count, **_refill_kwargs())


_ctx = AppContext(
    settings=SETTINGS,
    client=client,
    openai_api_key=OPENAI_API_KEY,
    llm_generate_tasks=_llm_generate_tasks,
    generate_tasks_via_ollama=_generate_tasks_via_ollama,
    generate_all_levels_via_ollama_one_shot=_generate_all_levels_via_ollama_one_shot,
    trigger_async_refill_once=_trigger_async_refill_once,
    refill_one_batch=_refill_one_batch,
)

register_routes(app, _ctx)


@app.on_event("startup")
def _task_pool_startup() -> None:
    import ollama_coordinator

    ollama_coordinator.set_refill_hooks(
        task_pool.schedule_refill_if_low,
        _retry_pending_refill,
    )
    task_pool.set_refill_fn(_refill_one_batch)
    task_pool.load()
    task_pool.bulk_seed_all_catalog()
    task_pool.schedule_refill_if_low()
    print(
        f"task_pool: startup target={task_pool.refill_target_total()} "
        f"per_level={POOL_TARGET_PER_LEVEL} "
        f"refill_model={SETTINGS.ollama_refill_model} @ {SETTINGS.ollama_refill_base_url}"
    )

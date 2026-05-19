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
from ollama_client import ollama_chat
from routes import register_routes
from settings import load_settings

SETTINGS = load_settings()

app = FastAPI(title="CollageWork AI Backend")

# ---------- OpenAI client ----------
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
client: Optional[OpenAI] = None
if OPENAI_API_KEY:
    client = OpenAI(api_key=OPENAI_API_KEY)
else:
    print("beck/main.py: OPENAI_API_KEY is not set. /generate_tasks will fail.")

POOL_LEVELS = [0, 1, 2, 3]
POOL_TARGET_PER_LEVEL = int(os.getenv("TASK_POOL_TARGET_PER_LEVEL", "45"))
POOL_REFILL_CHUNK = int(os.getenv("TASK_POOL_REFILL_CHUNK", "5"))
POOL_USE_ONE_SHOT_REFILL = os.getenv("TASK_POOL_USE_ONE_SHOT_REFILL", "0") == "1"


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
    )


def _refill_one_batch() -> List[dict]:
    return refill_one_batch(
        client=client,
        pool_levels=POOL_LEVELS,
        pool_target_per_level=POOL_TARGET_PER_LEVEL,
        pool_refill_chunk=POOL_REFILL_CHUNK,
        pool_use_one_shot_refill=POOL_USE_ONE_SHOT_REFILL,
        llm_generate_tasks_fn=_llm_generate_tasks,
        generate_tasks_via_ollama_fn=_generate_tasks_via_ollama,
        generate_all_levels_via_ollama_one_shot_fn=_generate_all_levels_via_ollama_one_shot,
    )


def _trigger_async_refill_once() -> None:
    def worker() -> None:
        try:
            batch = _refill_one_batch()
            if batch:
                task_pool.add_tasks(batch)
                print(f"task_pool: async refill after pop +{len(batch)}")
        except Exception as e:
            print(f"task_pool: async refill error: {e}")

    threading.Thread(target=worker, daemon=True).start()


def _start_ollama_warmup_background() -> None:
    if not SETTINGS.ollama_warmup_enabled:
        return

    def worker() -> None:
        try:
            base_opts = SETTINGS.ollama_extra_options()
            timeout_s = SETTINGS.ollama_warmup_timeout

            print("ollama_warmup: start")
            # 1) Супер-легкий ping для быстрого пробуждения модели.
            ping_opts = dict(base_opts)
            ping_opts["num_predict"] = 8
            # Первый запрос: модель может долго грузиться в RAM — не обрезать до 25 с.
            ping_timeout_s = max(20, min(timeout_s, 120))
            _ = ollama_chat(
                ollama_base_url=SETTINGS.ollama_base_url,
                ollama_model=SETTINGS.ollama_model,
                ollama_num_predict=8,
                system_msg="Ответь одним символом: 1",
                user_msg="1",
                timeout_s=ping_timeout_s,
                force_json=False,
                temperature=0.0,
                extra_options=ping_opts,
            )

            warm_opts = dict(base_opts)
            warm_opts["num_predict"] = SETTINGS.ollama_warmup_num_predict

            # 2) Короткий "чекер"-промпт в стиле check_task.
            _ = ollama_chat(
                ollama_base_url=SETTINGS.ollama_base_url,
                ollama_model=SETTINGS.ollama_model,
                ollama_num_predict=SETTINGS.ollama_warmup_num_predict,
                system_msg=(
                    "Ты проверяешь решение студента по заданию Python. "
                    "Верни строго JSON: {\"success\": true/false, \"feedback\": \"...\"}."
                ),
                user_msg=(
                    "Задание: Вывести число 5\n"
                    "Ожидаемый вывод: 5\n"
                    "required_patterns: <пусто>\n"
                    "stdout: 5\n"
                    "stderr: <пусто>\n"
                    "Код студента:\nprint(5)\n"
                ),
                timeout_s=timeout_s,
                force_json=True,
                temperature=SETTINGS.ollama_temperature,
                extra_options=warm_opts,
            )

            # 3) Короткий "генератор"-промпт в стиле generate_tasks.
            _ = ollama_chat(
                ollama_base_url=SETTINGS.ollama_base_url,
                ollama_model=SETTINGS.ollama_model,
                ollama_num_predict=SETTINGS.ollama_warmup_num_predict,
                system_msg=(
                    "Ты создаёшь учебные задания Python. "
                    "Верни только JSON формата {\"tasks\":[...]}."
                ),
                user_msg=(
                    "Сгенерируй 1 задачу уровня 0. "
                    "Поля: level, category, description, expected_output, "
                    "required_patterns, check_type, required_keywords, allow_direct_print."
                ),
                timeout_s=timeout_s,
                force_json=True,
                temperature=SETTINGS.ollama_temperature,
                extra_options=warm_opts,
            )
            print("ollama_warmup: done")
        except Exception as e:
            # Не валим запуск backend, если прогрев не удался.
            print(f"ollama_warmup: skipped ({e})")

    threading.Thread(target=worker, daemon=True).start()


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
    task_pool.set_refill_fn(_refill_one_batch)
    task_pool.load()
    _start_ollama_warmup_background()
    task_pool.schedule_refill_if_low()

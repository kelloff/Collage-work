"""
Центральные настройки бэка из env.
Значения по умолчанию ориентированы на VPS ~4 vCPU / 8 GB RAM и qwen2.5:3b:
быстрее ответ Ollama при сохранении полного JSON (20 задач) и нормального качества.
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Dict


def _b(name: str, default: bool) -> bool:
    v = os.getenv(name)
    if v is None:
        return default
    return v.strip().lower() in ("1", "true", "yes", "on")


def _i(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


def _f(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    ollama_base_url: str
    ollama_model: str
    ollama_refill_base_url: str
    ollama_refill_model: str
    ollama_temperature: float
    ollama_num_predict: int
    ollama_pool_model: str
    ollama_pool_num_predict: int
    ollama_pool_temperature: float
    ollama_pool_timeout: int
    ollama_pool_num_ctx: int
    ollama_pool_max_attempts: int
    ollama_multi_num_predict: int
    ollama_num_ctx: int
    ollama_top_p: float
    ollama_repeat_penalty: float
    ollama_single_timeout: int
    ollama_multi_timeout: int
    multi_oneshot_first: bool
    ollama_warmup_enabled: bool
    ollama_warmup_timeout: int
    ollama_warmup_num_predict: int
    generate_max_seconds: int
    ollama_check_base_url: str
    ollama_check_model: str
    ollama_check_num_predict: int
    ollama_check_timeout: int
    ollama_check_num_ctx: int

    def ollama_extra_options(self) -> Dict[str, Any]:
        """Опции Ollama кроме temperature/num_predict (добавляются в /api/chat options)."""
        d: Dict[str, Any] = {
            "top_p": self.ollama_top_p,
            "repeat_penalty": self.ollama_repeat_penalty,
        }
        if self.ollama_num_ctx > 0:
            d["num_ctx"] = self.ollama_num_ctx
        return d

    def ollama_pool_extra_options(self) -> Dict[str, Any]:
        d = self.ollama_extra_options()
        if self.ollama_pool_num_ctx > 0:
            d["num_ctx"] = self.ollama_pool_num_ctx
        return d

    def health_public(self) -> Dict[str, Any]:
        return {
            "ollama_base_url": self.ollama_base_url,
            "ollama_model": self.ollama_model,
            "ollama_refill_base_url": self.ollama_refill_base_url,
            "ollama_refill_model": self.ollama_refill_model,
            "ollama_pool_model": self.ollama_pool_model,
            "ollama_num_predict": self.ollama_num_predict,
            "ollama_pool_num_predict": self.ollama_pool_num_predict,
            "ollama_pool_temperature": self.ollama_pool_temperature,
            "ollama_pool_timeout": self.ollama_pool_timeout,
            "ollama_pool_num_ctx": self.ollama_pool_num_ctx,
            "ollama_multi_num_predict": self.ollama_multi_num_predict,
            "ollama_num_ctx": self.ollama_num_ctx,
            "ollama_top_p": self.ollama_top_p,
            "ollama_repeat_penalty": self.ollama_repeat_penalty,
            "ollama_single_timeout": self.ollama_single_timeout,
            "ollama_multi_timeout": self.ollama_multi_timeout,
            "task_multi_oneshot_first": self.multi_oneshot_first,
            "ollama_warmup_enabled": self.ollama_warmup_enabled,
            "generate_max_seconds": self.generate_max_seconds,
            "ollama_check_base_url": self.ollama_check_base_url,
            "ollama_check_model": self.ollama_check_model,
            "ollama_check_num_predict": self.ollama_check_num_predict,
            "ollama_check_timeout": self.ollama_check_timeout,
        }


def load_settings() -> Settings:
    return Settings(
        ollama_base_url=os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434"),
        ollama_model=os.getenv("OLLAMA_MODEL", "qwen2.5:3b"),
        ollama_refill_base_url=os.getenv(
            "OLLAMA_REFILL_BASE_URL",
            os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434"),
        ),
        ollama_refill_model=os.getenv("OLLAMA_REFILL_MODEL", "").strip()
        or os.getenv("OLLAMA_POOL_MODEL", "").strip()
        or os.getenv("OLLAMA_MODEL", "qwen2.5:3b"),
        ollama_temperature=_f("OLLAMA_TEMPERATURE", 0.1),
        ollama_num_predict=_i("OLLAMA_NUM_PREDICT", 768),
        ollama_pool_model=os.getenv("OLLAMA_POOL_MODEL", "").strip()
        or os.getenv("OLLAMA_REFILL_MODEL", "").strip()
        or os.getenv("OLLAMA_MODEL", "qwen2.5:3b"),
        ollama_pool_num_predict=_i("OLLAMA_POOL_NUM_PREDICT", 512),
        ollama_pool_temperature=_f("OLLAMA_POOL_TEMPERATURE", 0.2),
        ollama_pool_timeout=_i("OLLAMA_POOL_SINGLE_TIMEOUT", 120),
        ollama_pool_num_ctx=_i("OLLAMA_POOL_NUM_CTX", 1536),
        ollama_pool_max_attempts=_i("TASK_POOL_REFILL_MAX_OLLAMA_ATTEMPTS", 2),
        # 4 уровня × 5 задач: запас по токенам, чтобы не резало JSON
        ollama_multi_num_predict=_i("OLLAMA_MULTI_NUM_PREDICT", 2800),
        # Ограничение контекста: меньше — быстрее, но не ставь слишком мало (обрезка промпта/JSON)
        ollama_num_ctx=_i("OLLAMA_NUM_CTX", 4096),
        ollama_top_p=_f("OLLAMA_TOP_P", 0.95),
        ollama_repeat_penalty=_f("OLLAMA_REPEAT_PENALTY", 1.08),
        ollama_single_timeout=_i("OLLAMA_SINGLE_TIMEOUT", 300),
        ollama_multi_timeout=_i("OLLAMA_MULTI_TIMEOUT", 480),
        # При пустом пуле: сначала один запрос на все уровни (быстрее по wall-clock), потом дозаполнение
        multi_oneshot_first=_b("TASK_MULTI_ONESHOT_FIRST", True),
        # Неблокирующий прогрев Ollama на старте сервиса.
        ollama_warmup_enabled=_b("OLLAMA_WARMUP_ENABLED", False),
        ollama_warmup_timeout=_i("OLLAMA_WARMUP_TIMEOUT", 45),
        ollama_warmup_num_predict=_i("OLLAMA_WARMUP_NUM_PREDICT", 96),
        # Жёсткий лимит на один /generate_tasks_multi, чтобы не ждать часами.
        generate_max_seconds=_i("GENERATE_MAX_SECONDS", 300),
        ollama_check_base_url=os.getenv("OLLAMA_CHECK_BASE_URL", "http://127.0.0.1:11435"),
        ollama_check_model=os.getenv("OLLAMA_CHECK_MODEL", "qwen2.5:0.5b"),
        ollama_check_num_predict=_i("OLLAMA_CHECK_NUM_PREDICT", 64),
        ollama_check_timeout=_i("CHECK_TASK_AI_TIMEOUT", 10),
        ollama_check_num_ctx=_i("OLLAMA_CHECK_NUM_CTX", 1024),
    )

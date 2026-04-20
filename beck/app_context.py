from dataclasses import dataclass
from typing import Callable, List, Optional, Tuple

from openai import OpenAI

from models import TaskSpec
from settings import Settings


@dataclass(frozen=True)
class AppContext:
    """Снимок конфигурации и колбэков для HTTP-роутов."""

    settings: Settings
    client: Optional[OpenAI]
    openai_api_key: Optional[str]

    llm_generate_tasks: Callable[[int, int], Tuple[List[TaskSpec], str]]
    generate_tasks_via_ollama: Callable[[int, int], Tuple[List[TaskSpec], bool]]
    generate_all_levels_via_ollama_one_shot: Callable[
        [List[int], int], Tuple[List[TaskSpec], str]
    ]
    trigger_async_refill_once: Callable[[], None]
    refill_one_batch: Callable[[], List[dict]]

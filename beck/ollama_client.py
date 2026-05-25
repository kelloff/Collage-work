from __future__ import annotations

import json
from typing import Optional, Protocol

import requests


class OllamaAborted(Exception):
    """HTTP к Ollama прерван (refill на паузе из-за /check_task)."""


class _AbortLike(Protocol):
    def is_set(self) -> bool: ...


def ollama_chat(
    ollama_base_url: str,
    ollama_model: str,
    ollama_num_predict: int,
    system_msg: str,
    user_msg: str,
    timeout_s: int = 120,
    force_json: bool = False,
    temperature: float = 0.1,
    extra_options: Optional[dict] = None,
    abort_event: Optional[_AbortLike] = None,
) -> str:
    """
    Query local Ollama via /api/chat (non-streaming response, stream=True read).
    abort_event: при is_set() соединение закрывается (пауза refill).
    """
    url = f"{ollama_base_url.rstrip('/')}/api/chat"
    opts = {
        "temperature": temperature,
        "num_predict": ollama_num_predict,
    }
    if extra_options:
        opts.update(extra_options)
    payload = {
        "model": ollama_model,
        "messages": [
            {"role": "system", "content": system_msg},
            {"role": "user", "content": user_msg},
        ],
        "options": opts,
        "stream": False,
    }
    if force_json:
        payload["format"] = "json"
    connect_s = min(5, max(2, timeout_s // 4))
    resp = requests.post(
        url,
        json=payload,
        timeout=(connect_s, timeout_s),
        stream=True,
    )
    try:
        resp.raise_for_status()
        chunks: list[bytes] = []
        for chunk in resp.iter_content(chunk_size=8192):
            if abort_event and abort_event.is_set():
                raise OllamaAborted("refill aborted")
            if chunk:
                chunks.append(chunk)
        raw = b"".join(chunks).decode("utf-8", errors="replace")
        data = json.loads(raw)
        return str(data.get("message", {}).get("content", "")).strip()
    except OllamaAborted:
        raise
    except Exception:
        raise
    finally:
        resp.close()

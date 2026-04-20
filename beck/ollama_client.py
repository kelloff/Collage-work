from typing import Optional

import requests


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
) -> str:
    """
    Query local Ollama model via /api/chat (non-streaming).
    Returns assistant message content (string).
    """
    url = f"{ollama_base_url}/api/chat"
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
    resp = requests.post(url, json=payload, timeout=timeout_s)
    resp.raise_for_status()
    data = resp.json()
    return str(data.get("message", {}).get("content", "")).strip()

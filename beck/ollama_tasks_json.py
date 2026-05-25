"""Разбор JSON с задачами из ответа Ollama."""
from __future__ import annotations

import json
import re
from typing import List


def parse_ollama_tasks_json(raw_text: str, level_hint: int = -1) -> List[dict]:
    cleaned = (raw_text or "").strip()
    cleaned = cleaned.replace("```json", "").replace("```", "").strip()
    cleaned = cleaned.replace("\\[", "[").replace("\\]", "]")
    cleaned = cleaned.replace("\\{", "{").replace("\\}", "}")
    cleaned = re.sub(r",\s*//[^\n\r]*", "", cleaned)
    cleaned = re.sub(r"//[^\n\r]*", "", cleaned)
    cleaned = re.sub(r",\s*([}\]])", r"\1", cleaned)

    data = None
    try:
        data = json.loads(cleaned)
    except Exception:
        data = None

    if data is None:
        arr_match = re.search(r"\[[\s\S]*\]", cleaned)
        if arr_match:
            try:
                data = json.loads(arr_match.group(0))
            except Exception:
                data = None
        if data is None:
            arr_match = re.search(r"\[[\s\S]*?\]", cleaned)
            if arr_match:
                try:
                    data = json.loads(arr_match.group(0))
                except Exception:
                    data = None

    if data is None:
        obj_match = re.search(r"\{[\s\S]*?\"tasks\"[\s\S]*?\}", cleaned)
        if obj_match:
            try:
                maybe_obj = json.loads(obj_match.group(0))
                if isinstance(maybe_obj, dict) and "tasks" in maybe_obj:
                    data = maybe_obj["tasks"]
            except Exception:
                pass

    if data is None:
        obj_matches = re.findall(
            r"\{[\s\S]*?\"category\"[\s\S]*?\"expected_output\"[\s\S]*?\}",
            cleaned,
        )
        objs: list[dict] = []
        for m in obj_matches:
            if '"category"' not in m or '"expected_output"' not in m:
                continue
            try:
                parsed_obj = json.loads(m)
                if isinstance(parsed_obj, dict) and "expected_output" in parsed_obj:
                    objs.append(parsed_obj)
            except Exception:
                continue
        if objs:
            data = objs

    if isinstance(data, dict):
        if "tasks" in data and isinstance(data["tasks"], list):
            data = data["tasks"]
        elif "category" in data and "expected_output" in data:
            data = [data]

    if not isinstance(data, list):
        short = (raw_text or "")[:400].replace("\n", "\\n")
        print(
            f"parse_ollama_tasks_json: JSON parse failed, "
            f"level_hint={level_hint}. Raw(head)={short!r}"
        )
        return []

    return [obj for obj in data if isinstance(obj, dict)]

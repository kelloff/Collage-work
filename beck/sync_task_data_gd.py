#!/usr/bin/env python3
"""
Синхронизирует db/task_data.gd с fallback_generate_tasks() в generate_service.py.

Единый учебный каталог для:
- локального fallback в Godot (new_game_loading)
- server source=fallback и refill каталога lvl 2+
- документации notes / EDUCATION.md

Запуск из корня репозитория:
  python beck/sync_task_data_gd.py
"""
from __future__ import annotations

from pathlib import Path

from tasks_fallback_catalog import FALLBACK_TASKS_BY_LEVEL

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_GD_PATH = PROJECT_ROOT / "db" / "task_data.gd"
LEVELS = [0, 1, 2, 3]


def to_gd_string(value: str) -> str:
    s = str(value)
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build_gd() -> str:
    lines = [
        "# Синхронизировано с beck/tasks_fallback_catalog.py\n",
        "# Не править вручную: python beck/sync_task_data_gd.py\n",
        "# Совпадает с server source=fallback и локальным fallback Godot.\n",
        "extends Node\n\n",
        "var default_tasks = [\n",
    ]
    total = 0
    for lvl in LEVELS:
        for obj in FALLBACK_TASKS_BY_LEVEL.get(lvl, []):
            total += 1
            desc = str(obj.get("description", "")).strip()
            if not desc.startswith("AI:"):
                desc = "AI: " + desc
            row = [
                "\t{",
                f"\t\t\"level\": {lvl},",
                f"\t\t\"category\": {to_gd_string(str(obj.get('category', 'easy')))},",
                f"\t\t\"description\": {to_gd_string(desc)},",
                f"\t\t\"expected_output\": {to_gd_string(str(obj.get('expected_output', '')))},",
                f"\t\t\"required_patterns\": {to_gd_string(str(obj.get('required_patterns', '')))},",
                f"\t\t\"check_type\": {to_gd_string(str(obj.get('check_type', 'stdout_exact')))},",
                f"\t\t\"required_keywords\": {to_gd_string(str(obj.get('required_keywords', '')))},",
                f"\t\t\"allow_direct_print\": {int(obj.get('allow_direct_print', 0))},",
                "\t},",
            ]
            lines.append("\n".join(row) + "\n")
    lines.append("]\n")
    return "".join(lines), total


def main() -> None:
    gd, total = build_gd()
    OUTPUT_GD_PATH.write_text(gd, encoding="utf-8")
    print(f"Wrote {total} tasks to {OUTPUT_GD_PATH}")


if __name__ == "__main__":
    main()

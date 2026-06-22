#!/usr/bin/env python3
"""Генератор листинга кода для ПЗ: часть 1 (~5000 строк) + часть 2 (остальное)."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PART1 = ROOT / "code_listing_pz.txt"
OUTPUT_PART2 = ROOT / "code_listing_pz_part2.txt"
TARGET_LINES = 5000

MUST_INCLUDE = [
    "project.godot",
    "scenes/player/player.gd",
    "scenes/maniac/maniac.gd",
    "scenes/level_1/level_manager.gd",
    "scenes/level_1/hud_ui.gd",
    "scenes/computer/computer.gd",
    "scenes/computer/terminal_ui.gd",
    "scripts/code_runner.gd",
    "scripts/AiChecker.gd",
    "scripts/GameState.gd",
    "scripts/save_manager.gd",
    "db/db_meneger.gd",
    "db/db_save.gd",
    "db/db_tasks.gd",
]

OPTIONAL_ORDERED = [
    "scenes/main_menu/main_menu.gd",
    "scenes/lever/lever.gd",
    "db/db_doors.gd",
    "db/db_terminal_code.gd",
    "scenes/inventory/inventory.gd",
    "scenes/inventory/inventory_slot.gd",
    "scenes/finish/finish_trigger.gd",
    "scenes/screamer/screamer.gd",
    "scripts/death_flow.gd",
    "scenes/notes/note.gd",
    "scenes/pause_menu/pause_menu.gd",
    "scripts/run_stats.gd",
    "scenes/items/heal_buff.gd",
    "scenes/items/speed_buff.gd",
    "scenes/items/invis_buff.gd",
    "scenes/finish/win_ui.gd",
    "scenes/ui/confirm_dialog.gd",
    "scripts/backend_urls.gd",
    "scripts/new_game_config.gd",
    "scenes/player/camera_2d.gd",
    "scripts/save_meneger.gd",
    "scripts/task_client_filter.gd",
    "scenes/door/door.gd",
    "scenes/chest/chest.gd",
    "db/db_levers.gd",
    "scenes/new_game_loading/new_game_loading.gd",
    "scenes/death_stats/death_stats.gd",
    "scenes/journal/journal.gd",
    "scripts/JournalData.gd",
    "scenes/settings_menu/settings_menu.gd",
    "scripts/game_ui_theme.gd",
    "scenes/tutorial/tutorial_overlay.gd",
    "scripts/audio_manger.gd",
    "scripts/interact_highlight.gd",
    "scripts/interaction_outline.gd",
    "scenes/items/pickup_buff_common.gd",
    "db/db_migration.gd",
    "db/db_debug.gd",
]

# Часть 2: всё важное, чего нет в части 1. Без лимита строк.
PART2_ORDERED = [
    # Крупная логика, не вошедшая в часть 1
    "scripts/tutorial_manager.gd",
    "db/task_data.gd",
    "scripts/task_client_filter.gd",
    "scenes/door/door.gd",
    "scenes/chest/chest.gd",
    "db/db_levers.gd",
    # Меню и UI
    "scenes/pause_menu/pause_menu.gd",
    "scenes/settings_menu/settings_menu.gd",
    "scenes/new_game_loading/new_game_loading.gd",
    "scenes/new_game_loading/loading_background.gd",
    "scenes/new_game_loading/simple_spinner.gd",
    "scenes/death_stats/death_stats.gd",
    "scenes/journal/journal.gd",
    "scripts/JournalData.gd",
    "scenes/finish/win_ui.gd",
    "scenes/ui/confirm_dialog.gd",
    "scripts/game_ui_theme.gd",
    "scenes/tutorial/tutorial_overlay.gd",
    # Геймплей
    "scripts/run_stats.gd",
    "scenes/items/speed_buff.gd",
    "scenes/items/invis_buff.gd",
    "scenes/items/pickup_buff_common.gd",
    # Инфраструктура
    "scripts/backend_urls.gd",
    "scripts/new_game_config.gd",
    "scripts/save_meneger.gd",
    "scripts/audio_manger.gd",
    "scripts/interact_highlight.gd",
    "scripts/interaction_outline.gd",
    "db/db_migration.gd",
    "db/db_debug.gd",
    "export_presets.cfg",
    # Сцены (.tscn) — структура проекта
    "scenes/level_1/level_1.tscn",
    "scenes/player/player.tscn",
    "scenes/maniac/maniac.tscn",
    "scenes/inventory/inventory.tscn",
    "scenes/computer/computer.tscn",
    "scenes/door/door.tscn",
    "scenes/chest/chest.tscn",
    "scenes/chest/chest1.tscn",
    "scenes/lever/lever.tscn",
    "scenes/main_menu/main_menu.tscn",
    "scenes/pause_menu/pause_menu.tscn",
    "scenes/settings_menu/settings_menu.tscn",
    "scenes/new_game_loading/new_game_loading.tscn",
    "scenes/death_stats/death_stats.tscn",
    "scenes/journal/journal.tscn",
    "scenes/finish/win_ui.tscn",
    "scenes/finish/finish_trigger.tscn",
    "scenes/ui/confirm_dialog.tscn",
    "scenes/tutorial/tutorial_overlay.tscn",
    "scenes/screamer/screamer.tscn",
    "scenes/notes/note.tscn",
    "scenes/items/heal_buff.tscn",
    "scenes/items/speed_buff.tscn",
    "scenes/items/invis_buff.tscn",
]

SKIP_PREFIXES = ("addons/", ".godot/")
SKIP_PATHS = {
    "scenes/props/vaza1.tscn",
    "scenes/props/vaza_2.tscn",
}

SOURCE_ROOTS = ("scenes", "scripts", "db")


def compress_code(text: str) -> str:
    """Убирает пустые строки и схлопывает подряд идущие строки только с ')'."""
    lines = text.splitlines()
    out: list[str] = []
    paren_buf: list[str] = []

    def flush_parens() -> None:
        if paren_buf:
            out.append(" ".join(paren_buf))
            paren_buf.clear()

    for line in lines:
        stripped = line.rstrip()
        if not stripped.strip():
            flush_parens()
            continue

        if re.fullmatch(r"[\s\)]*", stripped) and ")" in stripped:
            only_parens = "".join(ch for ch in stripped if ch == ")")
            if only_parens:
                paren_buf.append(only_parens)
                continue

        flush_parens()
        out.append(stripped.rstrip())

    flush_parens()
    return "\n".join(out)


def read_and_compress(rel_path: str) -> tuple[str, int, int]:
    path = ROOT / rel_path
    raw = path.read_text(encoding="utf-8")
    compressed = compress_code(raw)
    return compressed, len(raw.splitlines()), len(compressed.splitlines()) if compressed else 0


def block_line_count(code_lines: int) -> int:
    return 1 + code_lines + 1


def rel_path_str(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def should_skip(rel: str) -> bool:
    if rel in SKIP_PATHS:
        return True
    return any(rel.startswith(p) for p in SKIP_PREFIXES)


def discover_extra_part2(exclude: set[str]) -> list[str]:
    """Любые исходники в scenes/scripts/db, не попавшие в часть 1."""
    found: list[str] = []
    for root_name in SOURCE_ROOTS:
        base = ROOT / root_name
        if not base.exists():
            continue
        for pattern in ("*.gd", "*.tscn"):
            for path in sorted(base.rglob(pattern)):
                rel = rel_path_str(path)
                if rel in exclude or should_skip(rel) or rel in PART2_ORDERED:
                    continue
                found.append(rel)
    return found


def write_listing(
    output: Path,
    files: list[str],
    *,
    target: int | None,
    label: str,
) -> tuple[list[tuple[str, int, int]], list[str], int]:
    parts: list[str] = []
    total_lines = 0
    included: list[tuple[str, int, int]] = []
    skipped: list[str] = []

    for rel in files:
        path = ROOT / rel
        if not path.exists():
            skipped.append(f"{rel} (нет файла)")
            continue

        code, raw_n, comp_n = read_and_compress(rel)
        need = block_line_count(comp_n)
        if target is not None and total_lines + need > target and included:
            skipped.append(f"{rel} (лимит {target})")
            continue

        parts.append(f"#{rel}\n{code}\n")
        total_lines += need
        included.append((rel, raw_n, comp_n))

    output.write_text("\n".join(parts), encoding="utf-8")

    print(f"\n=== {label} ===")
    print(f"Записано: {output}")
    print(f"Файлов: {len(included)}, строк: ~{total_lines}")
    saved = sum(raw_n - comp_n for _, raw_n, comp_n in included)
    print(f"Сэкономлено строк сжатием: {saved}")
    for rel, raw_n, comp_n in included:
        print(f"  {rel}: {raw_n} -> {comp_n}")
    if skipped:
        print("Пропущено:")
        for s in skipped:
            print(f"  {s}")

    return included, skipped, total_lines


def main() -> None:
    part1_files = list(MUST_INCLUDE)
    part1_seen: set[str] = set(part1_files)

    # Симулируем часть 1, чтобы знать что реально вошло
    temp_included: list[str] = []
    temp_lines = 0
    for rel in MUST_INCLUDE:
        path = ROOT / rel
        if not path.exists():
            continue
        _, _, comp_n = read_and_compress(rel)
        temp_included.append(rel)
        temp_lines += block_line_count(comp_n)

    for rel in OPTIONAL_ORDERED:
        if rel in part1_seen:
            continue
        path = ROOT / rel
        if not path.exists():
            continue
        _, _, comp_n = read_and_compress(rel)
        need = block_line_count(comp_n)
        if temp_lines + need > TARGET_LINES and temp_included:
            continue
        temp_included.append(rel)
        part1_seen.add(rel)
        temp_lines += need

    part1_included, _, _ = write_listing(
        OUTPUT_PART1,
        temp_included,
        target=TARGET_LINES,
        label="Часть 1",
    )
    part1_set = {rel for rel, _, _ in part1_included}

    part2_files: list[str] = []
    part2_seen: set[str] = set()
    for rel in PART2_ORDERED:
        if rel not in part1_set and rel not in part2_seen:
            part2_files.append(rel)
            part2_seen.add(rel)

    for rel in discover_extra_part2(part1_set | part2_seen):
        part2_files.append(rel)
        part2_seen.add(rel)

    write_listing(
        OUTPUT_PART2,
        part2_files,
        target=None,
        label="Часть 2 (без лимита)",
    )


if __name__ == "__main__":
    main()

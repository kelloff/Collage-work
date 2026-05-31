#!/usr/bin/env python3
"""
Генератор функциональной схемы CollageWork (draw.io).
Стиль: белое на чёрном, ортогональные линии, сетка.

Запуск:
  python scheme/gen_functional_scheme.py
  → scheme/collage_functional_scheme.drawio
"""
from __future__ import annotations

import html
import os
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

OUT = os.path.join(os.path.dirname(__file__), "collage_functional_scheme.drawio")

# --- стили draw.io (белое на чёрном) ---
S_RECT = (
    "rounded=0;whiteSpace=wrap;html=1;"
    "strokeColor=#ffffff;fontColor=#ffffff;fillColor=#000000;"
    "align=center;verticalAlign=middle;"
)
S_OVAL = (
    "ellipse;whiteSpace=wrap;html=1;"
    "strokeColor=#ffffff;fontColor=#ffffff;fillColor=#000000;"
    "align=center;verticalAlign=middle;"
)
S_DIAMOND = (
    "rhombus;whiteSpace=wrap;html=1;"
    "strokeColor=#ffffff;fontColor=#ffffff;fillColor=#000000;"
    "align=center;verticalAlign=middle;"
)
S_BAR = (
    "rounded=0;whiteSpace=wrap;html=1;"
    "strokeColor=#ffffff;fontColor=#ffffff;fillColor=#000000;"
    "align=center;verticalAlign=middle;fontStyle=1;fontSize=13;"
)
S_NOTE = (
    "rounded=0;whiteSpace=wrap;html=1;"
    "strokeColor=#888888;fontColor=#cccccc;fillColor=#000000;"
    "align=left;verticalAlign=top;spacingLeft=6;spacingTop=4;fontSize=10;"
    "dashed=1;"
)
S_EDGE = (
    "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;"
    "jettySize=auto;html=1;strokeColor=#ffffff;fontColor=#ffffff;"
    "endArrow=classicThin;startArrow=none;"
)


@dataclass
class Node:
    nid: str
    text: str
    x: int
    y: int
    w: int
    h: int
    style: str = S_RECT


class Diagram:
    def __init__(self, page_w: int = 3400, page_h: int = 2600) -> None:
        self.page_w = page_w
        self.page_h = page_h
        self._id = 2
        self.nodes: Dict[str, Node] = {}
        self.edges: List[Tuple[str, str, Optional[str]]] = []

    def _next_id(self) -> str:
        i = self._id
        self._id += 1
        return str(i)

    def add(self, key: str, text: str, x: int, y: int, w: int, h: int, style: str = S_RECT) -> str:
        nid = self._next_id()
        self.nodes[key] = Node(nid, text, x, y, w, h, style)
        return nid

    def link(self, src: str, dst: str, label: Optional[str] = None) -> None:
        self.edges.append((src, dst, label))

    def to_xml(self) -> str:
        cells: List[str] = [
            '<mxfile host="app.diagrams.net" agent="gen_functional_scheme.py" version="22.1.0">',
            '  <diagram name="Функциональная схема" id="main">',
            f'    <mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" guides="1"'
            f' connect="1" arrows="1" fold="1" page="1" pageScale="1"'
            f' pageWidth="{self.page_w}" pageHeight="{self.page_h}"'
            f' background="#000000" math="0" shadow="0">',
            "      <root>",
            '        <mxCell id="0"/>',
            '        <mxCell id="1" parent="0"/>',
        ]
        for n in self.nodes.values():
            val = html.escape(n.text).replace("\n", "&#xa;")
            cells.append(
                f'        <mxCell id="{n.nid}" value="{val}" style="{n.style}"'
                f' vertex="1" parent="1">'
                f'          <mxGeometry x="{n.x}" y="{n.y}" width="{n.w}" height="{n.h}" as="geometry"/>'
                f"        </mxCell>"
            )
        for src_k, dst_k, label in self.edges:
            src = self.nodes[src_k].nid
            dst = self.nodes[dst_k].nid
            eid = self._next_id()
            lbl = ""
            if label:
                lbl = f' value="{html.escape(label)}"'
            cells.append(
                f'        <mxCell id="{eid}" style="{S_EDGE}" edge="1" parent="1"'
                f' source="{src}" target="{dst}"{lbl}>'
                f'          <mxGeometry relative="1" as="geometry"/>'
                f"        </mxCell>"
            )
        cells.extend(["      </root>", "    </mxGraphModel>", "  </diagram>", "</mxfile>"])
        return "\n".join(cells)


def build() -> Diagram:
    d = Diagram(page_w=3600, page_h=2800)

    # ── Верх: главное меню ─────────────────────────────────────────
    d.add("start", "Старт", 1680, 30, 100, 50, S_OVAL)
    d.add("menu", "Главное меню\nmain_menu.tscn", 1580, 110, 300, 56)

    d.add("new_game", "Новая игра", 1180, 220, 160, 44)
    d.add("continue", "Продолжить", 1580, 220, 160, 44)
    d.add("settings_btn", "Настройки", 1980, 220, 160, 44)
    d.add("tutorial_btn", "Обучение", 2280, 220, 140, 44)
    d.add("exit_btn", "Выход", 2480, 220, 120, 44)

    d.add("has_save", "Есть\nсохранение?", 1160, 310, 120, 80, S_DIAMOND)
    d.add("confirm", "Диалог\nподтверждения", 980, 430, 160, 48)
    d.add("loading", "new_game_loading\nPOST задач", 980, 520, 200, 52)
    d.add("wipe_db", "wipe БД → insert\n20 задач (4×5)", 980, 610, 200, 52)
    d.add("level1", "level_1.tscn", 980, 710, 160, 44)

    d.add("cont_save", "Есть\nсохранение?", 1560, 310, 120, 80, S_DIAMOND)
    d.add("restore", "SaveManager\nвосстановление", 1540, 430, 200, 48)
    d.add("inactive", "Кнопка\nнеактивна", 1780, 430, 140, 48)

    d.add("exit_end", "Выход\nпрограммы", 2460, 320, 140, 56, S_OVAL)

    d.link("start", "menu")
    d.link("menu", "new_game")
    d.link("menu", "continue")
    d.link("menu", "settings_btn")
    d.link("menu", "tutorial_btn")
    d.link("menu", "exit_btn")
    d.link("new_game", "has_save")
    d.link("has_save", "confirm", "да")
    d.link("confirm", "loading")
    d.link("loading", "wipe_db")
    d.link("wipe_db", "level1")
    d.link("continue", "cont_save")
    d.link("cont_save", "restore", "да")
    d.link("cont_save", "inactive", "нет")
    d.link("exit_btn", "exit_end")

    # ── Левая колонка: runtime (клиент) ─────────────────────────
    d.add(
        "runtime_bar",
        "Фоновые процессы (Godot autoload)",
        40,
        110,
        320,
        36,
        S_BAR,
    )
    autoloads = [
        ("au_theme", "GameUiTheme"),
        ("au_backend", "BackendUrls\n→ kellofff.me /health"),
        ("au_config", "NewGameConfig\nуровни 0–3, count"),
        ("au_db", "DbManager\nSQLite tasks.db"),
        ("au_code", "CodeRunner\nPython subprocess"),
        ("au_ai", "AiCheckerSingleton\nPOST /check_task"),
        ("au_state", "GameState / RunStats"),
        ("au_save", "SaveManager"),
        ("au_death", "DeathFlow"),
        ("au_tut", "TutorialManager"),
        ("au_audio", "audio_manager"),
        ("au_journal", "JournalData"),
    ]
    y = 170
    prev = None
    for key, label in autoloads:
        d.add(key, label, 60, y, 280, 40)
        if prev:
            d.link(prev, key)
        prev = key
        y += 52

    # ── Центр: настройки hub ──────────────────────────────────────
    d.add("settings_hub", "Настройки (hub)", 1320, 820, 220, 48, S_BAR)
    d.link("settings_btn", "settings_hub")

    settings_cols = [
        ("set_general", "Общее", 1080, 920, ["audio_manager", "user_settings", "Master/Music"]),
        ("set_menu", "Главное меню", 1320, 920, ["confirm_dialog", "tutorial toggle"]),
        ("set_pause", "Пауза / уровень", 1560, 920, ["pause_menu", "Save→DB", "Exit→menu"]),
        ("set_term", "Терминал", 1800, 920, ["terminal_ui", "CodeRunner", "freeze input"]),
        ("set_journal", "Журнал", 2040, 920, ["guide.txt", "python_basics", "JournalData"]),
        ("set_db", "База данных", 2280, 920, ["tasks/progress", "levels/doors", "save_data"]),
    ]
    for hub_key, title, sx, sy, items in settings_cols:
        d.add(hub_key, title, sx, sy, 180, 40)
        d.link("settings_hub", hub_key)
        iy = sy + 56
        last = hub_key
        for i, item in enumerate(items):
            ik = f"{hub_key}_i{i}"
            d.add(ik, item, sx + 10, iy, 160, 36)
            d.link(last, ik)
            last = ik
            iy += 44

    # ── Правая колонка: СЕРВЕР (актуально по beck/) ─────────────
    d.add(
        "server_bar",
        "Сервер FastAPI (beck/) — как в коде",
        2680,
        110,
        420,
        40,
        S_BAR,
    )
    d.add("fastapi", "main.py\nFastAPI + startup", 2720, 170, 340, 48)
    d.add("routes", "routes/\nhealth · generate · check", 2720, 240, 340, 48)
    d.link("server_bar", "fastapi")
    d.link("fastapi", "routes")

    api_nodes = [
        ("api_health", "GET /health\npool stats", 2640, 320, 200, 44),
        ("api_gen_m", "POST /generate_tasks_multi\nновая игра (20 задач)", 2860, 320, 260, 52),
        ("api_gen", "POST /generate_tasks\n1 уровень", 2860, 390, 200, 44),
        ("api_check", "POST /check_task\nпроверка кода", 2640, 390, 200, 44),
    ]
    for k, t, x, y, w, h in api_nodes:
        d.add(k, t, x, y, w, h)
    d.link("routes", "api_health")
    d.link("routes", "api_gen_m")
    d.link("routes", "api_gen")
    d.link("routes", "api_check")

    d.add("ctx", "AppContext\nколбэки LLM/refill", 2720, 470, 340, 44)
    d.link("routes", "ctx")

    d.add("gen_flow", "generate_routes", 2520, 550, 200, 40)
    d.add("pool", "task_pool\n tasks_pool.json", 2760, 550, 220, 48)
    d.add("gen_svc", "generate_service\nOllama / OpenAI", 3000, 550, 200, 48)
    d.add("fallback", "tasks_fallback_catalog\nsource=fallback", 2760, 630, 260, 48)
    d.link("api_gen_m", "gen_flow")
    d.link("api_gen", "gen_flow")
    d.link("gen_flow", "pool")
    d.link("gen_flow", "gen_svc")
    d.link("gen_svc", "fallback", "если 503")

    d.add("refill", "pool_refill\nфон → Ollama :11434", 2520, 720, 220, 48)
    d.add("coord", "ollama_coordinator\nпауза refill при check", 2760, 720, 280, 48)
    d.add("check_svc", "check_service\nOllama :11435", 2520, 800, 200, 44)
    d.link("pool", "refill")
    d.link("refill", "coord")
    d.link("api_check", "check_svc")
    d.link("check_svc", "coord")

    d.add("filters", "task_filters\n task_diversity", 3000, 720, 200, 48)
    d.link("pool", "filters")

    # HTTP от клиента к серверу
    d.add("http_bar", "HTTP (BackendUrls)", 2680, 880, 360, 36, S_BAR)
    d.link("au_backend", "http_bar")
    d.link("http_bar", "api_health")
    d.link("loading", "api_gen_m")
    d.link("au_ai", "api_check")

    d.add(
        "server_note",
        "На схеме-черновике было:\n"
        "GameLifter/C# — в проекте нет.\n"
        "Реально: Python FastAPI + Ollama.",
        2520,
        900,
        380,
        72,
        S_NOTE,
    )

    # ── Низ: игровой уровень ──────────────────────────────────────
    d.add(
        "level_bar",
        "Игровой уровень (level_1 — hub сцен)",
        40,
        1180,
        3520,
        40,
        S_BAR,
    )
    d.link("level1", "level_bar")

    cols = [
        ("col_player", "Игрок", ["WASD", "HP/урон", "HP≤0→DeathFlow"]),
        ("col_monster", "Монстр", ["PATROL", "CHASE", "INVESTIGATE"]),
        ("col_pc", "Компьютер", ["E → terminal", "level задачи", "CodeRunner"]),
        ("col_door", "Двери", ["level_door", "computer_door"]),
        ("col_lever", "Рычаги", ["toggle", "связь с дверью"]),
        ("col_npc", "Соседи", ["диалог", "квесты"]),
        ("col_inv", "Инвентарь", ["pickup", "use item"]),
        ("col_notes", "Записи", ["collect", "journal"]),
        ("col_journal", "Журнал UI", ["docs", "DeathFlow"]),
        ("col_pause", "Пауза", ["pause_menu", "save/exit"]),
        ("col_hud", "HUD", ["HP bar", "tasks hint"]),
        ("col_finish", "Финиш", ["level complete", "next level"]),
    ]
    cx = 60
    for col_key, title, items in cols:
        d.add(col_key, title, cx, 1250, 250, 40, S_BAR)
        d.link("level_bar", col_key)
        iy = 1310
        last = col_key
        for i, item in enumerate(items):
            ik = f"{col_key}_{i}"
            d.add(ik, item, cx + 8, iy, 234, 36)
            d.link(last, ik)
            last = ik
            iy += 44
        cx += 290

    # Связь компьютер → check
    d.link("col_pc_2", "au_code")
    d.link("col_pc_2", "au_ai")

    return d


def main() -> None:
    xml = build().to_xml()
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(xml)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()

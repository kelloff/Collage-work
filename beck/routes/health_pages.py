from fastapi import APIRouter
from fastapi.responses import HTMLResponse

import task_pool
from app_context import AppContext


def create_health_router(ctx: AppContext) -> APIRouter:
    router = APIRouter(tags=["meta"])

    @router.get("/health")
    def health():
        out = {"status": "ok", "openai_api_key_set": bool(ctx.openai_api_key)}
        out.update(ctx.settings.health_public())
        out.update(task_pool.stats())
        return out

    @router.get("/", response_class=HTMLResponse)
    def welcome_page():
        return """<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>CollageWork — сервер</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; background: #0f172a; color: #e2e8f0; }
    .card { max-width: 820px; background: #111827; border: 1px solid #334155; border-radius: 14px; padding: 28px 32px; }
    h1 { margin-top: 0; color: #93c5fd; font-size: 1.6rem; }
    h2 { color: #cbd5e1; font-size: 1.05rem; margin: 1.4em 0 0.5em; }
    p, li { line-height: 1.55; }
    ul { padding-left: 1.2em; }
    code { background: #0b1220; padding: 2px 6px; border-radius: 6px; font-size: 0.92em; }
    a { color: #93c5fd; }
    .author { margin-top: 1.8em; padding-top: 1.2em; border-top: 1px solid #334155; color: #94a3b8; font-size: 0.9rem; }
  </style>
</head>
<body>
  <div class="card">
    <h1>CollageWork — backend-сервер</h1>
    <p>
      Это публичный API для учебной игры <strong>The Last Code</strong> (Godot-клиент):
      генерация заданий по Python, проверка кода игрока и фоновый запас задач на диске.
    </p>

    <h2>Зачем этот сервер</h2>
    <ul>
      <li><strong>Новая игра</strong> — клиент запрашивает набор задач (4 уровня × 5) и записывает их в локальную SQLite.</li>
      <li><strong>Терминал в игре</strong> — отправка решения на проверку: сравнение вывода с эталоном и подсказки при ошибке.</li>
      <li><strong>Пул задач</strong> — фоновое пополнение до ~300 заданий через Ollama, чтобы выдача была быстрой без долгого ожидания LLM.</li>
    </ul>

    <h2>Что размещено на хосте</h2>
    <ul>
      <li><strong>Nginx</strong> — HTTPS, прокси на <code>127.0.0.1:8000</code></li>
      <li><strong>FastAPI</strong> (<code>beck/</code>) — REST API проекта</li>
      <li><strong>Ollama</strong> — :11434 генерация/refill, :11435 лёгкая проверка кода</li>
      <li><strong>tasks_pool.json</strong> — кэш сгенерированных заданий</li>
      <li><strong>systemd</strong> — сервис <code>collage-backend</code></li>
    </ul>

    <h2>API (кто вызывает)</h2>
    <ul>
      <li>Статус и пул: <a href="/health"><code>GET /health</code></a> — клиент при проверке сети</li>
      <li>
        <strong>«Новая игра» (Godot):</strong>
        сначала <code>POST /generate_tasks_multi</code> — один запрос, 4 уровня × 5 задач (20 шт.);
        если не ответил — запасной вариант: 4× <code>POST /generate_tasks</code> (по одному уровню)
      </li>
      <li><strong>Терминал в игре:</strong> <code>POST /check_task</code> — проверка кода игрока</li>
      <li>Фон на сервере: пул пополняется без этих POST (refill → Ollama), игрок забирает из пула через multi</li>
    </ul>

    <p class="author">
      Автор: <strong>Пастуханов Владимир Анатольевич</strong>, группа <strong>9-3-ПОИС-22</strong>
    </p>
  </div>
</body>
</html>
"""

    return router

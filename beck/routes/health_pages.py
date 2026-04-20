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
  <title>CollageWork Backend</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; background: #0f172a; color: #e2e8f0; }
    .card { max-width: 760px; background: #111827; border: 1px solid #334155; border-radius: 14px; padding: 24px; }
    h1 { margin-top: 0; color: #93c5fd; }
    p, li { line-height: 1.5; }
    code { background: #0b1220; padding: 2px 6px; border-radius: 6px; }
    a { color: #93c5fd; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Добро пожаловать, я Володя!</h1>
    <p>Backend проекта <strong>CollageWork</strong> успешно работает на сервере.</p>
    <ul>
      <li>Проверка API: <a href="/health"><code>/health</code></a></li>
      <li>Генерация задач: <code>/generate_tasks</code> или быстрее — <code>/generate_tasks_multi</code></li>
      <li>Проверка решения: <code>/check_task</code></li>
    </ul>
    <p>Если ты видишь эту страницу — домен, Nginx, HTTPS и FastAPI настроены правильно.</p>
  </div>
</body>
</html>
"""

    return router

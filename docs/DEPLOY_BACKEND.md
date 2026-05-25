# Деплой бэкенда CollageWork

## Что это

Папка `beck/` — **FastAPI** на порту **8000**, снаружи — **Nginx + HTTPS** (у вас: `https://kellofff.me`).

**Логика пула, Ollama и fallback для игрока:** [SERVER_TASKS.md](SERVER_TASKS.md).

| Эндпоинт | Назначение |
|----------|------------|
| `GET /health` | Статус, настройки Ollama, размер пула задач |
| `GET /` | Приветственная HTML-страница |
| `POST /generate_tasks` | Задачи одного уровня (Ollama) |
| `POST /generate_tasks_multi` | Задачи для нескольких уровней (игра при «Новой игре») |
| `POST /check_task` | Проверка кода студента (уровень 2+ — Ollama) |

**Зависимости на сервере:** Python 3.11+, **Ollama** с моделью `qwen2.5:3b`, ~4 GB RAM для модели.

Игра берёт URL из autoload `BackendUrls` (`scripts/backend_urls.gd`): по умолчанию `https://kellofff.me`, локально — `COLLAGE_BACKEND_URL=http://127.0.0.1:8000`.

---

## Текущий статус (проверка с ПК)

На момент последней проверки:

- `GET https://kellofff.me/health` → **200 OK**, бэкенд жив.
- `POST /check_task` → **200 OK** (детерминированная проверка на level 0).
- `POST /generate_tasks_multi` → **таймаут ~120 с** с клиента — пул задач **пустой** (`task_pool_total: 0`), первый запрос идёт в Ollama и может быть долгим; нужны `proxy_read_timeout 600s` в Nginx и рабочий Ollama на VPS.

---

## Структура на VPS (рекомендуется)

```
/opt/collage-work/
  beck/
    main.py
    .env              # из env.example, chmod 640
    env/              # python -m venv
    tasks_pool.json   # кэш задач (создаётся автоматически)
```

Сервис: `collage-backend.service` (см. `deploy/`).

---

## Первичная установка на сервере

```bash
# 1) Ollama
curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen2.5:3b
systemctl enable ollama

# 2) Код проекта
sudo mkdir -p /opt/collage-work
# scp/rsync репозиторий на сервер, затем:
cd /opt/collage-work
sudo bash deploy/deploy_backend.sh /path/to/Collage-work

# 3) Настроить .env
sudo nano /opt/collage-work/beck/.env
# (скопировать из beck/env.example, проверить OLLAMA_BASE_URL)

# 4) Nginx — фрагмент deploy/nginx-location-proxy-snippet.conf
# proxy_read_timeout 600s обязателен для /generate_tasks_multi

# 5) SSL (certbot) для kellofff.me

# 6) Проверка
curl -s http://127.0.0.1:8000/health
curl -s https://kellofff.me/health
```

---

## Обновление после изменений в git

На сервере:

```bash
cd /opt/collage-work
git pull   # или rsync с вашего ПК
sudo bash deploy/deploy_backend.sh /opt/collage-work
sudo systemctl status collage-backend
```

---

## Прогрев пула задач (важно)

Пока `task_pool_total` в `/health` близок к 0, «Новая игра» ждёт генерацию в Ollama (минуты).

На сервере один раз (долго, в фоне):

```bash
curl -s -X POST http://127.0.0.1:8000/generate_tasks_multi \
  -H "Content-Type: application/json" \
  -d '{"levels":[0,1,2,3],"count_per_level":5}' \
  --max-time 600
```

Либо дождаться фонового `schedule_refill_if_low` после старта сервиса (смотреть логи `journalctl -u collage-backend -f`).

---

## Деплой с Windows (SSH)

```powershell
$env:DEPLOY_SSH_PASSWORD = "your_password"
python scripts/deploy_remote.py
```

Пароль **не храните в репозитории**. После деплоя смените root-пароль на сервере.

## Тест с Windows

```powershell
powershell -File scripts/test_backend_remote.ps1
powershell -File scripts/test_backend_remote.ps1 -BaseUrl "http://127.0.0.1:8000"
```

Локальный бэкенд:

```bat
cd beck
python -m venv env
env\Scripts\activate
pip install -r requirements.txt
copy env.example .env
uvicorn main:app --host 127.0.0.1 --port 8000
```

---

## Логи и типичные проблемы

| Симптом | Что проверить |
|---------|----------------|
| 502 / 504 снаружи | Nginx `proxy_read_timeout`, `systemctl status collage-backend` |
| `task_pool_total: 0` долго | Прогрев пула или Ollama не отвечает |
| Ollama 503 | `curl http://127.0.0.1:11434/api/tags`, `ollama pull qwen2.5:3b` |
| Игра не доходит до API | `BackendUrls.base_url`, HTTPS, файрвол 443 |

```bash
journalctl -u collage-backend -n 100 --no-pager
journalctl -u ollama -n 50 --no-pager
```

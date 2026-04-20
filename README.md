# godote-new-project

Учебная игра на Godot с генерацией заданий через AI (FastAPI + Ollama).

## Требования

### 1) Только игра (без AI-генерации)

Минимум:
- OS: Windows 10/11 (64-bit)
- CPU: 2 ядра (уровень Intel i3 / Ryzen 3)
- RAM: 4 GB
- GPU: любая с поддержкой Vulkan 1.2+ (или совместимая интегрированная)
- Disk: 2 GB свободного места

Рекомендуется:
- CPU: 4+ ядра
- RAM: 8 GB
- GPU: дискретная (или современная встроенная)

### 2) Игра + локальный AI (Ollama, модель `qwen2.5:3b`)

Минимум:
- OS: Windows 10/11 (64-bit)
- CPU: 4 ядра
- RAM: 8 GB (лучше 12+ GB)
- Disk: 8-10 GB свободного места (модель + кэш + проект)
- Internet: нужен для первого `ollama pull`

Рекомендуется:
- CPU: 6+ ядер
- RAM: 16 GB
- GPU: опционально (с GPU ответы обычно быстрее)
- Disk: 15+ GB

## Зависимости

- Godot 4.x
- Плагин SQLite для Godot (godot-sqlite)
- Python 3.11+ (для backend в `beck/`)
- Ollama (для локальной генерации заданий)

Python-зависимости backend:
- `beck/requirements.txt`

## Запуск

Основной запуск:
- `run_game_with_ai_tasks.bat`

Скрипт:
- поднимает backend,
- проверяет `/health`,
- (на первом запуске) генерирует AI-задачи,
- запускает игру.

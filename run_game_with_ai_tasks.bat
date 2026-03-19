@echo off
REM Авто‑запуск backend + генерация заданий + старт Godot проекта

cd /d "%~dp0"

echo [1/3] Запуск backend (FastAPI)...
start "" cmd /c "cd beck && call _env\Scripts\activate && uvicorn main:app --host 127.0.0.1 --port 8000"

REM Дадим backend несколько секунд, чтобы подняться
timeout /t 3 >nul

echo [2/3] Генерация заданий в db/task_data.gd через AI...
cd beck
call _env\Scripts\activate
python generate_tasks_to_gd.py
cd ..

echo [3/3] Запуск Godot проекта...
REM ЗАМЕНИ путь к godot.exe на свой, если другой
"C:\Users\pastu\Desktop\Collage-work\godote_new_project1.exe"

echo Готово. Если Godot не запустился, проверь путь к godot.exe в bat-файле.


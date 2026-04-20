@echo off
setlocal
REM UTF-8 console + Python IO (ASCII-only labels/comments: avoids cmd parsing issues after chcp)
chcp 65001 >nul
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

cd /d "%~dp0"
set "TASKS_LOCK_FILE=%~dp0db\.ai_tasks_locked"

echo [1/3] Starting backend (FastAPI)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\kill_port_8000.ps1"
start "" cmd /c "chcp 65001 >nul && cd /d ""%~dp0beck"" && call env\Scripts\activate && uvicorn main:app --host 127.0.0.1 --port 8000"

set /a _wait=0
set /a _ok=0
:wait_backend
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\check_health_once.ps1"
if %errorlevel%==0 goto backend_connected

set /a _wait+=1
set /a _ok=0
if %_wait% GEQ 8 goto backend_timeout
timeout /t 1 >nul
goto wait_backend

:backend_connected
set /a _ok+=1
if %_ok% GEQ 2 goto backend_ready

set /a _wait+=1
if %_wait% GEQ 8 goto backend_timeout
timeout /t 1 >nul
goto wait_backend

:backend_timeout
echo Warning: backend did not open port 8000 in ~7-8 seconds.
echo Continuing generation anyway (FastAPI may open slightly later).
goto backend_ready

:backend_ready

if exist "%TASKS_LOCK_FILE%" (
	echo [2/3] AI tasks are already generated. Skipping regeneration.
	echo To regenerate: delete "%TASKS_LOCK_FILE%"
) else (
	echo [2/3] First launch detected. Generating AI tasks once...
	pushd beck
	call env\Scripts\activate
	python generate_tasks_to_gd.py
	if errorlevel 1 (
		echo Generation failed or only fallback tasks were returned. Stop launch.
		popd
		goto end_all
	)
	popd
	echo generated_on=%DATE% %TIME%>"%TASKS_LOCK_FILE%"
	echo AI tasks locked for future launches.
)

echo [3/3] Starting Godot project...
"%~dp0godote_new_project1.exe"

echo Done. If Godot did not start, check the Godot exe path in this .bat file.

:end_all
endlocal

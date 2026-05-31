# Установщик The Last Code

## Что попадает игроку

Только папка `release/staging` после экспорта Godot:

- `TheLastCode.exe` + `TheLastCode.pck`
- `libgdsqlite.windows.template_release.x86_64.dll`
- `README.txt`, `SYSTEM_REQUIREMENTS.txt`

**Не включается:** `beck/`, `deploy/`, `scripts/`, `.env`, пароли SSH, исходники.

## Иконка

- В проекте и в `.exe`: `res://assets/fav.png` (`project.godot`, пресет **Windows Desktop 2**).
- В установщике Inno Setup: `fav.ico`, собирается из `assets/fav.png` при `build_release.ps1`.

## Сборка

```powershell
cd installer
.\build_release.ps1
```

Нужно:

- Godot 4.6.x (скрипт может скачать portable в `installer/tools/`)
- Export Templates для 4.6 (Editor → Manage Export Templates)
- Inno Setup 6 (winget: `JRSoftware.InnoSetup`) — для `.exe` установщика

Переменная `GODOT_EXE` — путь к редактору, если Godot не в PATH.

## Результат

| Файл | Описание |
|------|----------|
| `installer/output/TheLastCode_Setup_1.0.0.exe` | Установщик с системными требованиями |
| `installer/output/TheLastCode_1.0.0_portable.zip` | ZIP без инсталлятора |
| `release/staging/` | Распакованная игра |

## Проверка секретов

`secret_scan.ps1` запускается автоматически перед упаковкой.

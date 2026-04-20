# Free TCP port 8000 before starting uvicorn (safe if nothing is listening).
$ErrorActionPreference = 'SilentlyContinue'
Get-NetTCPConnection -LocalPort 8000 -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -ErrorAction SilentlyContinue |
    Sort-Object -Unique |
    ForEach-Object {
        try {
            Stop-Process -Id $_ -Force -ErrorAction Stop
        }
        catch {
            # ignore
        }
    }

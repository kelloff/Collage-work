# Single GET /health check. Exit 0 on HTTP 200, else 1. Used by run_game_with_ai_tasks.bat
try {
    $resp = Invoke-WebRequest -UseBasicParsing -Method GET -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 2
    if ($resp.StatusCode -eq 200) {
        exit 0
    }
    exit 1
}
catch {
    exit 1
}

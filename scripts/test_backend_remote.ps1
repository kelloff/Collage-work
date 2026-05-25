# Quick production backend check (default: https://kellofff.me).
param(
    [string]$BaseUrl = "https://kellofff.me",
    [int]$GenerateTimeoutSec = 300
)

$BaseUrl = $BaseUrl.TrimEnd("/")
$ok = $true

function Test-Endpoint {
    param([string]$Name, [string]$Method, [string]$Uri, [string]$Body, [int]$TimeoutSec = 15)
    Write-Host ""
    Write-Host "=== $Name ==="
    try {
        $params = @{
            Uri = $Uri
            Method = $Method
            TimeoutSec = $TimeoutSec
            UseBasicParsing = $true
        }
        if ($Body) {
            $params.ContentType = "application/json"
            $params.Body = $Body
        }
        $r = Invoke-WebRequest @params
        Write-Host "HTTP $($r.StatusCode)"
        if ($r.Content.Length -le 800) {
            Write-Host $r.Content
        } else {
            Write-Host ($r.Content.Substring(0, 800) + "...")
        }
        return $true
    } catch {
        Write-Host "FAIL: $($_.Exception.Message)"
        return $false
    }
}

if (-not (Test-Endpoint "GET /health" "GET" "$BaseUrl/health")) { $ok = $false }

$checkBody = '{"description":"print 5","expected_output":"5","user_code":"print(5)","level":0}'
if (-not (Test-Endpoint "POST /check_task" "POST" "$BaseUrl/check_task" $checkBody 30)) { $ok = $false }

$genBody = '{"levels":[0],"count_per_level":1}'
if (-not (Test-Endpoint "POST /generate_tasks_multi" "POST" "$BaseUrl/generate_tasks_multi" $genBody $GenerateTimeoutSec)) {
    Write-Host "Hint: empty task_pool or slow Ollama - check server logs and nginx proxy_read_timeout."
    $ok = $false
}

if ($ok) {
    Write-Host ""
    Write-Host "All checks passed."
    exit 0
}
Write-Host ""
Write-Host "Some checks failed."
exit 1

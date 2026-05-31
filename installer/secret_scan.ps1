# Scans a release folder for accidental secrets before packaging.
param(
    [Parameter(Mandatory = $true)][string]$Root
)

$patterns = @(
    "DEPLOY_SSH_PASSWORD\s*=\s*\S+",
    "\`$env:DEPLOY_SSH_PASSWORD\s*=\s*[`"'][^`"']+[`"']",
    "OPENAI_API_KEY\s*=\s*\S+",
    "sk-[a-zA-Z0-9]{20,}",
    "BEGIN (RSA |OPENSSH )?PRIVATE KEY"
)

$skipExt = @(
    ".exe", ".pck", ".dll", ".png", ".jpg", ".ogg", ".mp3", ".wav", ".ttf", ".res", ".import"
)

$hits = @()
Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $ext = $_.Extension.ToLower()
    if ($skipExt -contains $ext) {
        return
    }
    try {
        $text = [IO.File]::ReadAllText($_.FullName)
    } catch {
        return
    }
    foreach ($pat in $patterns) {
        if ($text -match $pat) {
            $hits += [pscustomobject]@{ File = $_.FullName; Pattern = $pat }
        }
    }
}

if ($hits.Count -gt 0) {
    Write-Error "Secret scan FAILED ($($hits.Count) hit(s)):"
    $hits | Format-Table -AutoSize
    exit 1
}

Write-Host "Secret scan OK: $Root"
exit 0

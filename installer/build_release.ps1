# Сборка релиза и установщика The Last Code (без секретов dev-репозитория).
# Usage:
#   cd installer
#   .\build_release.ps1
#   .\build_release.ps1 -GodotExe "C:\path\Godot_v4.6.3-stable_win64.exe"
#   .\build_release.ps1 -SkipExport   # только упаковать уже собранный staging

param(
    [string]$GodotExe = $env:GODOT_EXE,
    [switch]$SkipExport,
    [switch]$SkipInstaller,
    [string]$GodotVersion = "4.6.3"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"
$InstallerRoot = $PSScriptRoot
$ProjectRoot = (Resolve-Path (Join-Path $InstallerRoot "..")).Path
$Staging = Join-Path $ProjectRoot "release\staging"
$ToolsDir = Join-Path $InstallerRoot "tools"
$SqliteDllName = "libgdsqlite.windows.template_release.x86_64.dll"
$SqliteDllInProject = Join-Path $ProjectRoot "addons\godot-sqlite\bin\$SqliteDllName"
$ExportPreset = "Windows Desktop 2"
$AppExe = "TheLastCode.exe"
$AppPck = "TheLastCode.pck"
$PythonVersion = "3.12.10"
$PythonInstallerFile = "python-$PythonVersion-amd64.exe"

function Ensure-Dir([string]$p) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

function Resolve-GodotExe {
    if ($GodotExe -and (Test-Path $GodotExe)) { return (Resolve-Path $GodotExe).Path }
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $portable = Join-Path $ToolsDir "Godot.exe"
    if (Test-Path $portable) { return $portable }
    return $null
}

function Install-GodotPortable {
    Ensure-Dir $ToolsDir
    $zipUrl = "https://github.com/godotengine/godot/releases/download/$GodotVersion-stable/Godot_v$GodotVersion-stable_win64.exe.zip"
    $zipPath = Join-Path $ToolsDir "godot_win64.zip"
    if (-not (Test-Path (Join-Path $ToolsDir "Godot.exe"))) {
        Write-Host "Downloading Godot $GodotVersion ..."
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -LiteralPath $zipPath -DestinationPath $ToolsDir -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    }
    $exe = Get-ChildItem $ToolsDir -Filter "Godot_v*.exe" | Select-Object -First 1
    if (-not $exe) { throw "Godot exe not found after extract" }
    Copy-Item $exe.FullName (Join-Path $ToolsDir "Godot.exe") -Force
    return (Join-Path $ToolsDir "Godot.exe")
}

function Ensure-SqliteDll {
    if (Test-Path $SqliteDllInProject) {
        Write-Host "SQLite DLL OK: $SqliteDllInProject"
        return
    }
    Ensure-Dir (Split-Path $SqliteDllInProject -Parent)
    $zipUrl = "https://github.com/2shady4u/godot-sqlite/releases/download/v4.7/bin.zip"
    $cacheZip = Join-Path $ToolsDir "godot-sqlite-bin.zip"
    $cacheDir = Join-Path $ToolsDir "godot-sqlite-bin"
    Ensure-Dir $ToolsDir
    if (-not (Test-Path $cacheZip)) {
        Write-Host "Downloading godot-sqlite bin.zip ..."
        Invoke-WebRequest -Uri $zipUrl -OutFile $cacheZip -UseBasicParsing
    }
    if (Test-Path $cacheDir) { Remove-Item $cacheDir -Recurse -Force }
    Expand-Archive -Path $cacheZip -DestinationPath $cacheDir -Force
    $found = Get-ChildItem $cacheDir -Recurse -Filter $SqliteDllName | Select-Object -First 1
    if (-not $found) { throw "Missing $SqliteDllName in godot-sqlite bin.zip" }
    Copy-Item $found.FullName $SqliteDllInProject -Force
    Write-Host "Installed $SqliteDllName into addons"
}

function Install-ExportTemplates {
    $templatesRoot = Join-Path $env:APPDATA "Godot\export_templates"
    $dest = Join-Path $templatesRoot "$GodotVersion.stable"
    $marker = Join-Path $dest "version.txt"
    if (Test-Path $marker) {
        Write-Host "Export templates OK: $dest"
        return
    }
    Ensure-Dir $dest
    $tpzUrl = "https://github.com/godotengine/godot/releases/download/$GodotVersion-stable/Godot_v$GodotVersion-stable_export_templates.tpz"
    $tpzPath = Join-Path $ToolsDir "export_templates.tpz"
    $tpzZip = Join-Path $ToolsDir "export_templates.zip"
    Ensure-Dir $ToolsDir
    Write-Host "Downloading Godot export templates $GodotVersion (large, ~1 GB) ..."
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($tpzUrl, $tpzPath)
    $wc.Dispose()
    Write-Host "Downloaded: $tpzPath"
    Copy-Item $tpzPath $tpzZip -Force
    Expand-Archive -Path $tpzZip -DestinationPath $dest -Force
    Remove-Item $tpzPath, $tpzZip -Force -ErrorAction SilentlyContinue
    $nested = Join-Path $dest "templates"
    if ((Test-Path (Join-Path $nested "version.txt")) -and -not (Test-Path $marker)) {
        Get-ChildItem $nested -Force | Move-Item -Destination $dest -Force
        Remove-Item $nested -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $marker)) {
        throw "Export templates install failed (no version.txt in $dest)"
    }
    Write-Host "Installed export templates to $dest"
}

function Prepare-SqliteAddon {
    if (Test-Path $SqliteDllInProject) {
        Write-Host "SQLite DLL OK (skip bin cleanup)"
        return
    }
    Write-Host "Prepare SQLite addon ..."
    $binDir = Split-Path $SqliteDllInProject -Parent
    Ensure-Dir $binDir
    Get-ChildItem $binDir -Filter "~*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem $binDir -Filter "*template_debug*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Ensure-SqliteDll
}

function Resolve-GodotConsole([string]$godot) {
    $dir = Split-Path $godot -Parent
    $console = Get-ChildItem $dir -Filter "*console*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($console) { return $console.FullName }
    return $godot
}

function Get-ExportProjectPath {
    # Junction на ASCII-путь: Godot иногда ломается на кириллице в OneDrive.
    if ($ProjectRoot -match '[^\x00-\x7F]') {
        $linkRoot = "C:\collage-work-export"
        if (Test-Path $linkRoot) { cmd /c rmdir $linkRoot 2>$null }
        cmd /c mklink /J $linkRoot "$ProjectRoot" | Out-Null
        if (Test-Path $linkRoot) {
            Write-Host "Export via junction: $linkRoot"
            return @{ Path = $linkRoot; Cleanup = $true }
        }
        Write-Warning "Could not create junction; exporting from original path."
    }
    return @{ Path = $ProjectRoot; Cleanup = $false }
}

function Invoke-GodotExport([string]$godot) {
    Ensure-Dir $Staging
    if (Test-Path (Join-Path $Staging $AppExe)) { Remove-Item (Join-Path $Staging $AppExe) -Force }
    if (Test-Path (Join-Path $Staging $AppPck)) { Remove-Item (Join-Path $Staging $AppPck) -Force }
    $godotConsole = Resolve-GodotConsole $godot
    $exportOut = Join-Path $Staging $AppExe
    $proj = Get-ExportProjectPath
    try {
        Write-Host "Exporting preset '$ExportPreset' ..."
        Write-Host "Godot console: $godotConsole"
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $importLog = & $godotConsole --headless --path $proj.Path --import 2>&1
            $exportLog = & $godotConsole --headless --path $proj.Path --export-release $ExportPreset $exportOut 2>&1
        } finally {
            $ErrorActionPreference = $prevEap
        }
        $importLog | ForEach-Object { Write-Host $_ }
        $exportLog | ForEach-Object { Write-Host $_ }
        if (-not (Test-Path $exportOut)) {
            throw "Godot export failed: $exportOut not created (exit $LASTEXITCODE)"
        }
        Assert-ExportContainsDocs $exportLog
        Write-Host "Export OK: $exportOut"
    } finally {
        if ($proj.Cleanup -and (Test-Path "C:\collage-work-export")) {
            cmd /c rmdir "C:\collage-work-export" 2>$null
        }
    }
}

function Copy-ReleaseExtras {
    $dll = $SqliteDllInProject
    if (-not (Test-Path $dll)) { throw "SQLite DLL missing: $dll" }
    Copy-Item $dll (Join-Path $Staging $SqliteDllName) -Force
    $sqliteBin = Join-Path $Staging "addons\godot-sqlite\bin"
    Ensure-Dir $sqliteBin
    Copy-Item $dll (Join-Path $sqliteBin $SqliteDllName) -Force
    Write-Host "SQLite DLL: staging root + addons/godot-sqlite/bin"
    Copy-Item (Join-Path $InstallerRoot "PLAYER_README_RU.txt") (Join-Path $Staging "README.txt") -Force
    Copy-Item (Join-Path $InstallerRoot "SYSTEM_REQUIREMENTS_RU.txt") (Join-Path $Staging "SYSTEM_REQUIREMENTS.txt") -Force
    # Удалить dev-артефакты, если попали в staging (см. client_export_excludes.txt)
    $devNames = @(
        "beck", "deploy", "installer", "POOL", "release", ".cursor",
        "scripts"
    )
    foreach ($name in $devNames) {
        $p = Join-Path $Staging $name
        if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
    @("*.console.exe", "*.pdb", ".env", "*.py", "*.ps1", "*.bat", "README.md") | ForEach-Object {
        Get-ChildItem $Staging -Filter $_ -Recurse -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem $Staging -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Build-InstallerIcon {
    $pngPath = Join-Path $ProjectRoot "assets\fav.png"
    $icoPath = Join-Path $InstallerRoot "fav.ico"
    if (-not (Test-Path $pngPath)) {
        Write-Warning "assets/fav.png not found - installer wizard will use default icon."
        return
    }
    Add-Type -AssemblyName System.Drawing
    $bmp = [System.Drawing.Bitmap]::FromFile($pngPath)
    try {
        $hIcon = $bmp.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($hIcon)
        $fs = [System.IO.File]::Open($icoPath, [System.IO.FileMode]::Create)
        try {
            $icon.Save($fs)
        } finally {
            $fs.Close()
        }
        Write-Host "Installer icon: $icoPath (from assets/fav.png)"
    } finally {
        $bmp.Dispose()
    }
}

function Invoke-SecretScan {
    $scan = Join-Path $InstallerRoot "secret_scan.ps1"
    & $scan -Root $Staging
    if ($LASTEXITCODE -ne 0) { throw "Secret scan failed" }
}

function Resolve-InnoSetup {
    @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Ensure-InnoSetup {
    return Resolve-InnoSetup
}

function Ensure-PythonInstaller {
    Ensure-Dir $ToolsDir
    $dest = Join-Path $ToolsDir $PythonInstallerFile
    if (Test-Path $dest) {
        Write-Host "Python installer OK: $dest"
        return $dest
    }
    $url = "https://www.python.org/ftp/python/$PythonVersion/$PythonInstallerFile"
    Write-Host "Downloading Python $PythonVersion from python.org (~25 MB) ..."
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    if (-not (Test-Path $dest)) {
        throw "Python installer download failed: $url"
    }
    Write-Host "Python installer: $dest"
    return $dest
}

function Invoke-InnoSetup {
    $iscc = Ensure-InnoSetup
    if (-not $iscc) {
        Write-Warning "Inno Setup (ISCC.exe) not found. ZIP fallback only."
        return $false
    }
    Push-Location $InstallerRoot
    try {
        # ISS expects staging relative to installer/
        $link = Join-Path $InstallerRoot "staging"
        if (Test-Path $link) { Remove-Item $link -Recurse -Force -ErrorAction SilentlyContinue }
        cmd /c mklink /J staging "$Staging" | Out-Null
        & $iscc "TheLastCode.iss"
        if ($LASTEXITCODE -ne 0) { throw "ISCC failed" }
    } finally {
        Pop-Location
        $link = Join-Path $InstallerRoot "staging"
        if (Test-Path $link) { cmd /c rmdir staging 2>$null }
    }
    return $true
}

function New-PortableZip {
    $outDir = Join-Path $InstallerRoot "output"
    Ensure-Dir $outDir
    $zipPath = Join-Path $outDir "TheLastCode_1.0.0_portable.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $Staging "*") -DestinationPath $zipPath -Force
    return $zipPath
}

function Assert-ExportContainsDocs {
    param([object]$ExportLog)
    $joined = ($ExportLog | Out-String)
    foreach ($needle in @("docs/guide.txt", "docs/python_basics.txt", "docs/notes/note_01.txt")) {
        if ($joined -notmatch [regex]::Escape($needle)) {
            throw "Export missing journal/notes file in pack: $needle (check export_presets include_filter)"
        }
    }
    Write-Host "Export docs OK (guide, python_basics, notes in pack)"
}

function Verify-ExportPrerequisites {
    $shader = Join-Path $ProjectRoot "shaders\outline.gdshader"
    if (-not (Test-Path $shader)) {
        throw "Missing critical asset: shaders/outline.gdshader (tutorial highlights)"
    }
    foreach ($rel in @(
        "docs\guide.txt",
        "docs\python_basics.txt",
        "docs\notes\note_01.txt",
        "docs\notes\note_02.txt",
        "docs\notes\note_03.txt"
    )) {
        $p = Join-Path $ProjectRoot $rel
        if (-not (Test-Path $p)) {
            throw "Missing critical asset: $rel (journal / notes)"
        }
    }
    $font = Join-Path $ProjectRoot "ui\fonts\game_display.ttf"
    if (-not (Test-Path $font)) {
        throw "Missing critical asset: ui/fonts/game_display.ttf"
    }
    $gdext = Join-Path $ProjectRoot "addons\godot-sqlite\gdsqlite.gdextension"
    if (-not (Test-Path $gdext)) {
        throw "Missing godot-sqlite GDExtension (addons/godot-sqlite)"
    }
    if (-not (Test-Path $SqliteDllInProject)) {
        throw "Missing SQLite DLL: $SqliteDllInProject"
    }
    Write-Host "Export prerequisites OK (shader, font, SQLite)"
}

Write-Host "Project: $ProjectRoot"
Verify-ExportPrerequisites
Prepare-SqliteAddon

if (-not $SkipExport) {
    $godot = Resolve-GodotExe
    if (-not $godot) {
        $godot = Install-GodotPortable
    }
    Write-Host "Godot: $godot"
    Install-ExportTemplates
    Invoke-GodotExport $godot
}

if (-not (Test-Path (Join-Path $Staging $AppExe))) {
    throw "Missing $(Join-Path $Staging $AppExe). Run export first or remove -SkipExport."
}

Copy-ReleaseExtras
Invoke-SecretScan

$zip = New-PortableZip
Write-Host "Portable ZIP: $zip"

if (-not $SkipInstaller) {
    Build-InstallerIcon
    Ensure-PythonInstaller
    if (Invoke-InnoSetup) {
        Get-ChildItem (Join-Path $InstallerRoot "output") -Filter "TheLastCode_Setup_*.exe" |
            ForEach-Object { Write-Host "Installer: $($_.FullName)" }
    }
}

Write-Host "Done. Staging: $Staging"

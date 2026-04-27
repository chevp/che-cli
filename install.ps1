# che-cli installer for Windows PowerShell.
#
# Beyond just copying files, this also installs every runtime dependency che
# needs (Git for Windows, Python 3, PyYAML, Ollama, default model) via winget
# (with a direct-download fallback for Ollama).
#
# Usage:
#   .\install.ps1                   # interactive
#   .\install.ps1 -AssumeYes        # unattended -- say yes to everything
#   .\install.ps1 -NoDeps           # skip OS-level installs
#   .\install.ps1 -NoOllama         # don't touch ollama
#   .\install.ps1 -NoModel          # install ollama but skip model pull
#   .\install.ps1 -Prefix "C:\path" # custom install prefix
#   $env:PREFIX = "..."; .\install.ps1
#
# After install: open a new terminal, then run `che doctor`.

[CmdletBinding()]
param(
    [string]$Prefix,
    [string]$Model = $(if ($env:CHE_OLLAMA_MODEL) { $env:CHE_OLLAMA_MODEL } else { 'llama3.2' }),
    [switch]$AssumeYes,
    [switch]$NoDeps,
    [switch]$NoOllama,
    [switch]$NoModel
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Resolve install prefix
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Prefix)) {
    if (-not [string]::IsNullOrWhiteSpace($env:PREFIX)) {
        $Prefix = $env:PREFIX
    } else {
        $Prefix = Join-Path $env:LOCALAPPDATA 'che'
    }
}

$src    = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir = Join-Path $Prefix 'bin'
$libDir = Join-Path (Join-Path $Prefix 'lib') 'che'

Write-Host "che-cli install" -ForegroundColor White
Write-Host "  prefix: $Prefix" -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# 1. Copy dispatcher + lib + wrappers.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Installing files" -ForegroundColor Cyan

if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
if (-not (Test-Path $libDir)) { New-Item -ItemType Directory -Path $libDir -Force | Out-Null }

$srcBin = Join-Path (Join-Path $src 'bin') 'che'
if (Test-Path $srcBin) {
    Copy-Item $srcBin -Destination (Join-Path $binDir 'che') -Force
    Write-Host "  [OK]   bin/che" -ForegroundColor Green
} else {
    Write-Host "  [WARN] bin/che not found at $srcBin" -ForegroundColor Yellow
}

# Prefer the canonical wrappers from installer/wrappers/; fall back to inline.
$srcWrappers = Join-Path $src 'installer\wrappers'
$wrapperBat  = Join-Path $srcWrappers 'che.bat'
$wrapperPs1  = Join-Path $srcWrappers 'che.ps1'
$destBat     = Join-Path $binDir 'che.bat'
$destPs1     = Join-Path $binDir 'che.ps1'

if (Test-Path $wrapperBat) {
    Copy-Item $wrapperBat -Destination $destBat -Force
    Write-Host "  [OK]   bin/che.bat (from installer/wrappers/)" -ForegroundColor Green
} else {
    @'
@echo off
REM che-cli batch wrapper for Windows
setlocal enabledelayedexpansion
for %%I in ("%~dp0.") do set "BATCH_DIR=%%~fI"
powershell -NoProfile -ExecutionPolicy Bypass -File "%BATCH_DIR%\che.ps1" %*
exit /b %ERRORLEVEL%
'@ | Out-File -Encoding ASCII -FilePath $destBat -Force
    Write-Host "  [OK]   bin/che.bat (inline fallback)" -ForegroundColor Green
}

if (Test-Path $wrapperPs1) {
    Copy-Item $wrapperPs1 -Destination $destPs1 -Force
    Write-Host "  [OK]   bin/che.ps1 (from installer/wrappers/)" -ForegroundColor Green
} else {
    @'
$ErrorActionPreference = 'Stop'
function Find-GitBash {
    $candidates = @(
        $env:CHE_GIT_BASH,
        "$env:ProgramW6432\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}
$GitBash = Find-GitBash
if (-not $GitBash) {
    Write-Error "Git Bash not found. Install Git for Windows: https://git-scm.com/download/win"
    exit 1
}
$argList = @()
foreach ($arg in $args) {
    if ($arg -match '\s') { $argList += "`"$arg`"" } else { $argList += $arg }
}
& $GitBash -c "che $($argList -join ' ')"
exit $LASTEXITCODE
'@ | Out-File -Encoding UTF8 -FilePath $destPs1 -Force
    Write-Host "  [OK]   bin/che.ps1 (inline fallback)" -ForegroundColor Green
}

$srcLib = Join-Path (Join-Path $src 'lib') 'che'
if (Test-Path $srcLib) {
    Get-ChildItem $srcLib -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($srcLib.Length + 1)
        $dest     = Join-Path $libDir $relative
        if ($_.PSIsContainer) {
            if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
        } else {
            $destParent = Split-Path -Parent $dest
            if (-not (Test-Path $destParent)) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
            Copy-Item $_.FullName -Destination $dest -Force
        }
    }
    Write-Host "  [OK]   lib/che/  (full tree)" -ForegroundColor Green
} else {
    Write-Host "  [WARN] lib/che not found at $srcLib" -ForegroundColor Yellow
}

# Pin the install to the source repo's exact commit. `che ship` reads this
# file to decide whether the running install is stale (see lib/che/self_update.sh).
$installedSha      = 'unknown'
$installedDescribe = 'unknown'
try {
    Push-Location $src
    $sha = (& git rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $sha) { $installedSha = $sha.Trim() }
    $desc = (& git describe --tags --always --dirty 2>$null)
    if ($LASTEXITCODE -eq 0 -and $desc) { $installedDescribe = $desc.Trim() }
} catch { } finally { Pop-Location }
$versionFile = Join-Path $libDir '.installed-version'
$versionLines = @(
    "source_repo=$src",
    "installed_sha=$installedSha",
    "installed_describe=$installedDescribe",
    "installed_at=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
)
# Use UTF-8 (no BOM) so bash can read this without surprises.
[System.IO.File]::WriteAllLines($versionFile, $versionLines, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  [OK]   lib/che/.installed-version" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 2. Install runtime dependencies (Git, Python, Ollama, model).
# ---------------------------------------------------------------------------
$depsScript = Join-Path $src 'installer\lib\install-deps.ps1'
if (Test-Path $depsScript) {
    $depsArgs = @('-Model', $Model)
    if ($AssumeYes) { $depsArgs += '-AssumeYes' }
    if ($NoDeps)    { $depsArgs += '-NoDeps' }
    if ($NoOllama)  { $depsArgs += '-NoOllama' }
    if ($NoModel)   { $depsArgs += '-NoModel' }

    # Re-launch in a child PowerShell so $ErrorActionPreference and exit codes
    # don't bleed back into this installer.
    & powershell -NoProfile -ExecutionPolicy Bypass -File $depsScript @depsArgs
} else {
    Write-Host ""
    Write-Host "(installer/lib/install-deps.ps1 not found -- skipping dependency install)" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 3. PATH wiring.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> PATH" -ForegroundColor Cyan

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathArr  = if ($userPath) { $userPath -split ';' } else { @() }
if ($pathArr -contains $binDir) {
    Write-Host "  [OK]   $binDir already on user PATH" -ForegroundColor Green
} else {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $binDir } else { "$binDir;$userPath" }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "  [OK]   added $binDir to user PATH" -ForegroundColor Green
    Write-Host "         restart your terminal for the change to take effect" -ForegroundColor DarkGray
}
# Make it visible inside this session too.
if (";$env:Path;" -notlike "*;$binDir;*") { $env:Path = "$binDir;$env:Path" }

# ---------------------------------------------------------------------------
# 4. Final verification -- run `che doctor` if Git Bash is available.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Verification" -ForegroundColor Cyan

# Make sure ✓ / ✗ from `che doctor` survive the trip back through PowerShell.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding           = [System.Text.Encoding]::UTF8
} catch { }
$bash = $null
foreach ($c in @(
    $env:CHE_GIT_BASH,
    "$env:ProgramW6432\Git\bin\bash.exe",
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
)) {
    if ($c -and (Test-Path $c)) { $bash = $c; break }
}
$chePs1 = Join-Path $binDir 'che.ps1'
$cheBat = Join-Path $binDir 'che.bat'
# Verification is best-effort. If we got here, files were copied successfully;
# `che doctor` running under multiple nested shells (powershell -> bat ->
# powershell -> bash) sometimes mangles arg forwarding in ways that don't
# affect normal use. Wrap in try/catch and downgrade failures to a hint.
$verified = $false
try {
    if (Test-Path $chePs1) {
        # Direct .ps1 call: skips the .bat -> powershell.exe re-entry that
        # is the source of most arg-forwarding glitches during install.
        & $chePs1 doctor 2>&1 | ForEach-Object { Write-Host $_ }
        $verified = $true
    } elseif ($bash) {
        # Fallback: invoke the bash dispatcher directly. Use `$PATH (backtick)
        # so PowerShell preserves the literal $PATH for bash to expand -- not
        # \$PATH, which PowerShell does NOT treat as an escape.
        & $bash -c "PATH='$($binDir -replace '\\','/')':`$PATH che doctor" 2>&1 | ForEach-Object { Write-Host $_ }
        $verified = $true
    }
} catch {
    Write-Host "  [WARN] verification step errored: $($_.Exception.Message)" -ForegroundColor Yellow
}
if (-not $verified) {
    Write-Host "  [INFO] verification skipped -- run 'che doctor' manually after opening a new terminal" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "done. open a new terminal and try: che commit" -ForegroundColor Green

# che-cli -- Windows dependency installer.
#
# Used by install.ps1 (script-based install) and the Inno Setup post-install
# step. Installs Git for Windows, Python 3, Ollama via winget (with a direct
# Ollama-installer fallback), then PyYAML via pip and the default model via
# `ollama pull`.
#
# Usage:
#   .\install-deps.ps1                # interactive
#   .\install-deps.ps1 -AssumeYes     # unattended
#   .\install-deps.ps1 -NoDeps        # skip OS package installs
#   .\install-deps.ps1 -NoOllama      # skip ollama altogether
#   .\install-deps.ps1 -NoModel       # install ollama but skip model pull
#   .\install-deps.ps1 -Model llama3  # override default model

[CmdletBinding()]
param(
    [switch]$AssumeYes,
    [switch]$NoDeps,
    [switch]$NoOllama,
    [switch]$NoModel,
    [string]$Model = $(if ($env:CHE_OLLAMA_MODEL) { $env:CHE_OLLAMA_MODEL } else { 'llama3.2' }),
    [string]$OllamaHost = $(if ($env:CHE_OLLAMA_HOST) { $env:CHE_OLLAMA_HOST } else { 'http://localhost:11434' })
)

# Env-var overrides (so the Inno Setup [Run] step can pass flags via env).
if ($env:CHE_ASSUME_YES -eq '1') { $AssumeYes = $true }
if ($env:CHE_NO_DEPS    -eq '1') { $NoDeps    = $true }
if ($env:CHE_NO_OLLAMA  -eq '1') { $NoOllama  = $true }
if ($env:CHE_NO_MODEL   -eq '1') { $NoModel   = $true }

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------
function Write-Step($msg)  { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Fail($msg)  { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Warn($msg)  { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Info($msg)  { Write-Host "         $msg" -ForegroundColor DarkGray }

function Confirm-Action {
    param([string]$Prompt)
    if ($AssumeYes) { return $true }
    if (-not [Environment]::UserInteractive) { return $true }
    $reply = Read-Host "  $Prompt [Y/n]"
    if ([string]::IsNullOrWhiteSpace($reply)) { return $true }
    return ($reply -match '^[Yy]')
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    # Re-read PATH from registry so freshly-installed tools become visible
    # in this PowerShell session without restarting the shell.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

# ---------------------------------------------------------------------------
# winget helpers
# ---------------------------------------------------------------------------
function Test-Winget {
    return (Test-Command 'winget')
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-Winget-Pkg {
    param(
        [Parameter(Mandatory)] [string]$Id,
        [string]$Name = $Id,
        # Some packages (Git, Ollama) install fine to user scope without UAC.
        # When the installer runs unelevated, force user scope so winget never
        # blocks waiting for an elevation prompt that nobody can answer.
        [switch]$AllowMachineScope
    )
    if (-not (Test-Winget)) {
        Write-Fail "winget not available -- cannot auto-install $Name"
        Write-Info "install winget via the Microsoft Store ('App Installer')"
        return $false
    }

    $scopeArgs = @()
    if (-not $AllowMachineScope -and -not (Test-IsAdmin)) {
        $scopeArgs = @('--scope', 'user')
    }

    Write-Info "winget install --id $Id $($scopeArgs -join ' ')  (this may take a while)"
    # Stream output directly to the console -- DO NOT pipe through
    # ForEach-Object. winget prints non-newline progress chars and a pipe
    # buffers them indefinitely, making the installer appear to hang.
    & winget install --id $Id `
        @scopeArgs `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity
    $exit = $LASTEXITCODE
    Refresh-Path
    if ($exit -eq 0) {
        Write-Ok "$Name installed via winget"
        return $true
    }
    # winget returns 0x8A150010 if the package is already installed -- treat as success.
    if ($exit -eq -1978335214) {
        Write-Ok "$Name already installed (per winget)"
        return $true
    }
    # If user-scope failed, retry once without --scope user (some packages
    # are machine-scope only).
    if ($scopeArgs.Count -gt 0) {
        Write-Warn "user-scope install failed (exit $exit) -- retrying without --scope"
        & winget install --id $Id `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements `
            --disable-interactivity
        $exit = $LASTEXITCODE
        Refresh-Path
        if ($exit -eq 0) { Write-Ok "$Name installed via winget"; return $true }
        if ($exit -eq -1978335214) { Write-Ok "$Name already installed"; return $true }
    }
    Write-Fail "winget install $Id failed (exit $exit)"
    return $false
}

# ---------------------------------------------------------------------------
# Git for Windows
# ---------------------------------------------------------------------------
function Find-GitBash {
    $candidates = @(
        $env:CHE_GIT_BASH,
        "$env:ProgramW6432\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($c in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path $c)) { return $c }
    }
    return $null
}

function Ensure-Git {
    Write-Step "Git for Windows (provides bash.exe + git, required by every che command)"
    $bash = Find-GitBash
    if ($bash) {
        Write-Ok "Git Bash present: $bash"
        return $true
    }
    if ($NoDeps) { Write-Warn "Git missing (skipped: -NoDeps)"; return $false }
    if (-not (Confirm-Action "install Git for Windows via winget?")) {
        Write-Warn "skipped Git install"
        return $false
    }
    if (Install-Winget-Pkg -Id 'Git.Git' -Name 'Git for Windows') {
        Refresh-Path
        $bash = Find-GitBash
        if ($bash) { Write-Ok "Git Bash now at: $bash"; return $true }
        Write-Warn "Git installed but bash.exe not found yet -- restart your terminal"
    }
    return $false
}

# ---------------------------------------------------------------------------
# Python
# ---------------------------------------------------------------------------
function Find-Python {
    foreach ($cand in 'python3', 'python', 'py') {
        $cmd = Get-Command $cand -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        # Skip the Microsoft Store execution-alias stub which lives in WindowsApps
        # and exits without doing anything.
        if ($cmd.Source -like '*\WindowsApps\*' -and -not (Test-Path $cmd.Source)) { continue }
        try {
            & $cand -c "import sys; sys.exit(0)" 2>$null
            if ($LASTEXITCODE -eq 0) { return $cand }
        } catch { }
    }
    return $null
}

function Ensure-Python {
    Write-Step "Python 3 (required for che workflow / che run)"
    $py = Find-Python
    if ($py) {
        $ver = & $py -c "import sys;print(sys.version.split()[0])" 2>$null
        Write-Ok "$py ($ver)"
    } else {
        if ($NoDeps) { Write-Warn "Python missing (skipped: -NoDeps)"; return $false }
        if (-not (Confirm-Action "install Python 3.12 via winget?")) {
            Write-Warn "skipped Python install"
            return $false
        }
        if (-not (Install-Winget-Pkg -Id 'Python.Python.3.12' -Name 'Python 3.12')) { return $false }
        Refresh-Path
        $py = Find-Python
        if (-not $py) { Write-Fail "python still not on PATH after install"; return $false }
        $ver = & $py -c "import sys;print(sys.version.split()[0])" 2>$null
        Write-Ok "$py ($ver)"
    }

    # PyYAML
    & $py -c "import yaml" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $yver = & $py -c "import yaml;print(yaml.__version__)" 2>$null
        Write-Ok "PyYAML present ($yver)"
        return $true
    }
    if ($NoDeps) { Write-Warn "PyYAML missing (skipped: -NoDeps)"; return $false }
    if (-not (Confirm-Action "install PyYAML via pip?")) {
        Write-Warn "skipped PyYAML install"
        return $false
    }
    & $py -m pip install --user --upgrade pip *> $null
    & $py -m pip install --user pyyaml
    if ($LASTEXITCODE -eq 0) { Write-Ok "PyYAML installed via pip --user"; return $true }
    Write-Fail "pip install pyyaml failed"
    return $false
}

# ---------------------------------------------------------------------------
# Ollama
# ---------------------------------------------------------------------------
function Find-Ollama {
    $cmd = Get-Command 'ollama' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "$env:ProgramFiles\Ollama\ollama.exe"
    )) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Install-Ollama-Direct {
    # Fallback when winget is unavailable: download OllamaSetup.exe and run it.
    $url = 'https://ollama.com/download/OllamaSetup.exe'
    $dest = Join-Path $env:TEMP 'OllamaSetup.exe'
    Write-Info "downloading $url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    } catch {
        Write-Fail "download failed: $($_.Exception.Message)"
        return $false
    }
    Write-Info "running OllamaSetup.exe (silent)"
    $proc = Start-Process -FilePath $dest -ArgumentList '/SILENT' -Wait -PassThru
    Refresh-Path
    if ($proc.ExitCode -eq 0) { return $true }
    Write-Fail "OllamaSetup.exe exited with $($proc.ExitCode)"
    return $false
}

function Ensure-Ollama-Binary {
    $existing = Find-Ollama
    if ($existing) {
        Write-Ok "ollama binary present: $existing"
        return $true
    }
    if ($NoDeps) { Write-Warn "ollama missing (skipped: -NoDeps)"; return $false }
    if (-not (Confirm-Action "install Ollama (Windows installer)?")) {
        Write-Warn "skipped Ollama install"
        return $false
    }

    $installed = $false
    if (Test-Winget) {
        $installed = Install-Winget-Pkg -Id 'Ollama.Ollama' -Name 'Ollama'
    }
    if (-not $installed) {
        Write-Info "winget path failed or unavailable -- trying direct installer"
        $installed = Install-Ollama-Direct
    }
    Refresh-Path
    $existing = Find-Ollama
    if ($installed -and $existing) {
        Write-Ok "ollama installed: $existing"
        # Make sure the install dir is on PATH for this session.
        $dir = Split-Path -Parent $existing
        if (";$env:Path;" -notlike "*;$dir;*") { $env:Path = "$dir;$env:Path" }
        return $true
    }
    Write-Fail "ollama still not on PATH after install"
    return $false
}

function Test-Ollama-Server {
    try {
        $r = Invoke-WebRequest -Uri "$OllamaHost/api/tags" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        return ($r.StatusCode -eq 200)
    } catch {
        return $false
    }
}

function Start-Ollama-Server {
    if (Test-Ollama-Server) {
        Write-Ok "ollama server already reachable at $OllamaHost"
        return $true
    }
    Write-Info "starting 'ollama serve' in the background..."
    try {
        Start-Process -FilePath 'ollama' -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
    } catch {
        Write-Fail "could not start 'ollama serve': $($_.Exception.Message)"
        return $false
    }
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Ollama-Server) {
            Write-Ok "ollama server started at $OllamaHost"
            return $true
        }
    }
    Write-Fail "could not reach $OllamaHost after starting 'ollama serve'"
    Write-Info "start it manually: ollama serve"
    return $false
}

function Pull-Ollama-Model {
    if ($NoModel) { Write-Info "skipping model pull (-NoModel)"; return $true }
    $list = ''
    try { $list = & ollama list 2>$null } catch { }
    if ($list -match "(?m)^$([regex]::Escape($Model))(:\S+)?\s") {
        Write-Ok "model already present: $Model"
        return $true
    }
    if (-not (Confirm-Action "pull the default model '$Model' (this can be a few GB)?")) {
        Write-Warn "skipped model pull"
        return $true
    }
    & ollama pull $Model
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "model pulled: $Model"
        return $true
    }
    Write-Fail "ollama pull $Model failed"
    return $false
}

function Ensure-Ollama {
    if ($NoOllama) { Write-Info "skipping ollama setup (-NoOllama)"; return $true }
    Write-Step "Ollama (default LLM provider for che commit / che ship)"
    if (-not (Ensure-Ollama-Binary)) { return $false }
    if (-not (Start-Ollama-Server))  { return $false }
    if (-not (Pull-Ollama-Model))    { return $false }
    return $true
}

# ---------------------------------------------------------------------------
# Top-level
# ---------------------------------------------------------------------------
function Invoke-Che-Install-Deps {
    Write-Host "che-cli -- installing dependencies" -ForegroundColor White
    $wingetState = if (Test-Winget) { 'available' } else { 'NOT FOUND' }
    Write-Host "  winget: $wingetState   model: $Model" -ForegroundColor DarkGray

    $rc = 0
    if (-not (Ensure-Git))    { $rc = 1 }
    if (-not (Ensure-Python)) { $rc = 1 }
    if (-not (Ensure-Ollama)) { $rc = 1 }

    Write-Host ""
    if ($rc -eq 0) {
        Write-Host "all dependencies ready" -ForegroundColor Green
    } else {
        Write-Host "some dependencies were skipped or failed" -ForegroundColor Yellow
        Write-Host "  run 'che doctor' afterwards to see what's still missing" -ForegroundColor DarkGray
    }
    return $rc
}

# When dot-sourced, just expose the functions. When invoked directly, run.
if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-Che-Install-Deps)
}

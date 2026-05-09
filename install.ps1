# che-cli installer for Windows PowerShell.
#
# Runs `npm install` (which fetches and builds the chi dep) and adds bin/ to
# the user PATH so that `che` is available in new terminals.
#
# Usage:
#   .\install.ps1              # interactive
#   .\install.ps1 -AssumeYes   # unattended
#
# Requires: node 20+, npm.
#
# Tip: easier install path — `npm install -g github:chevp/che-cli`.

[CmdletBinding()]
param([switch]$AssumeYes)

$ErrorActionPreference = 'Stop'

$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir = Join-Path $src 'bin'

Write-Host "che-cli install"
Write-Host "  source: $src" -ForegroundColor DarkGray

try {
    $nodeVersion = (& node -e "process.stdout.write(process.versions.node)" 2>$null)
} catch { Write-Error "node not found. Install Node.js 20+: https://nodejs.org/"; exit 1 }
if (-not $nodeVersion) { Write-Error "node not on PATH. Install Node.js 20+"; exit 1 }
$nodeMajor = [int]($nodeVersion -split '\.')[0]
if ($nodeMajor -lt 20) { Write-Error "node $nodeVersion found, che requires node 20+"; exit 1 }

try { & npm --version | Out-Null } catch { Write-Error "npm not on PATH"; exit 1 }

Push-Location $src
try {
    & npm install --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
} finally { Pop-Location }

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$paths = if ($userPath) { $userPath -split ';' } else { @() }
if ($paths -notcontains $binDir) {
    if ($AssumeYes -or (Read-Host "add $binDir to your user PATH? [Y/n]") -ne 'n') {
        [Environment]::SetEnvironmentVariable('Path', ($userPath + ';' + $binDir).TrimStart(';'), 'User')
        Write-Host "  path  + $binDir on user PATH (open a new terminal)"
    }
}

Write-Host "→ ready. next: che status" -ForegroundColor Green

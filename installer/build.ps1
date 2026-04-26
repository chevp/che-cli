# Build the che-cli Windows installer with Inno Setup.
# Usage: .\build.ps1 [-Version 0.1.0]

param(
    [string]$Version = ""
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

$candidates = @(
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)
$iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
    Write-Error "ISCC.exe not found. Install Inno Setup 6 from https://jrsoftware.org/isdl.php"
    exit 1
}

$args = @("che-cli.iss")
if ($Version) {
    $args += "/DMyAppVersion=$Version"
}

Write-Host "Building installer with: $iscc $($args -join ' ')" -ForegroundColor Cyan
& $iscc @args
if ($LASTEXITCODE -ne 0) {
    Write-Error "ISCC failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

$out = Join-Path $here "Output"
Write-Host ""
Write-Host "Built installer in: $out" -ForegroundColor Green
Get-ChildItem $out -Filter *.exe | ForEach-Object {
    Write-Host "  $($_.Name)  ($([math]::Round($_.Length / 1KB)) KB)"
}

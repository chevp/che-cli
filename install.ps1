# che-cli installer for Windows PowerShell
# Usage: .\install.ps1 [prefix]

param(
    [string]$prefix = $null
)

# Determine the prefix - use environment variable, parameter, or default
if ([string]::IsNullOrWhiteSpace($prefix)) {
    if (![string]::IsNullOrWhiteSpace($env:PREFIX)) {
        $prefix = $env:PREFIX
    } else {
        # Windows default: %APPDATA%\Local\che
        if ([Environment]::Is64BitProcess) {
            $prefix = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData) + "\che"
        } else {
            $prefix = $env:LOCALAPPDATA + "\che"
        }
    }
}

$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir = Join-Path $prefix "bin"
$libDir = Join-Path (Join-Path $prefix "lib") "che"

Write-Host "Installing che-cli to: $prefix" -ForegroundColor Green
Write-Host ""

# Create directories
if (!(Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force > $null
    Write-Host "Created: $binDir"
}

if (!(Test-Path $libDir)) {
    New-Item -ItemType Directory -Path $libDir -Force > $null
    Write-Host "Created: $libDir"
}

# Copy bin/che
$srcBin = Join-Path (Join-Path $src "bin") "che"
$destBin = Join-Path $binDir "che"

if (Test-Path $srcBin) {
    Copy-Item $srcBin -Destination $destBin -Force
    Write-Host "Copied: bin/che → $destBin"
} else {
    Write-Host "WARNING: bin/che not found at $srcBin" -ForegroundColor Yellow
}

# Create Windows wrapper scripts for PowerShell compatibility
$destBat = Join-Path $binDir "che.bat"
$destPs1 = Join-Path $binDir "che.ps1"

# Create che.bat wrapper
@'
@echo off
REM che-cli batch wrapper for Windows PowerShell
REM This file routes che commands through Git Bash

setlocal enabledelayedexpansion

REM Get the directory where this batch file is located
for %%I in ("%~dp0.") do set "BATCH_DIR=%%~fI"

REM Call PowerShell with the wrapper script
powershell -NoProfile -ExecutionPolicy Bypass -File "%BATCH_DIR%\che.ps1" %*
exit /b %ERRORLEVEL%
'@ | Out-File -Encoding ASCII -FilePath $destBat -Force
Write-Host "Created: bin/che.bat → $destBat"

# Create che.ps1 wrapper
@'
# che-cli PowerShell wrapper for Windows
# Routes bash commands through Git Bash instead of WSL

$GitBashPath = "C:\Program Files\Git\bin\bash.exe"

if (-not (Test-Path $GitBashPath)) {
    Write-Error "Git Bash not found at $GitBashPath. Please install Git for Windows with bash support."
    exit 1
}

# Build the bash command with all arguments
$argList = @()
foreach ($arg in $args) {
    if ($arg -match '\s') {
        $argList += "`"$arg`""
    } else {
        $argList += $arg
    }
}
$BashCmd = "che $($argList -join ' ')"

# Execute through Git Bash
& $GitBashPath -c $BashCmd
exit $LASTEXITCODE
'@ | Out-File -Encoding UTF8 -FilePath $destPs1 -Force
Write-Host "Created: bin/che.ps1 → $destPs1"

# Copy lib tree
$srcLib = Join-Path (Join-Path $src "lib") "che"
if (Test-Path $srcLib) {
    Get-ChildItem $srcLib -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($srcLib.Length + 1)
        $dest = Join-Path $libDir $relative
        
        if ($_.PSIsContainer) {
            if (!(Test-Path $dest)) {
                New-Item -ItemType Directory -Path $dest -Force > $null
            }
        } else {
            $destParent = Split-Path -Parent $dest
            if (!(Test-Path $destParent)) {
                New-Item -ItemType Directory -Path $destParent -Force > $null
            }
            Copy-Item $_.FullName -Destination $dest -Force
        }
    }
    Write-Host "Copied: lib/che tree → $libDir"
} else {
    Write-Host "WARNING: lib/che not found at $srcLib" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Installed:" -ForegroundColor Green
Write-Host "  $destBin"
Write-Host "  $libDir (full tree)"
Write-Host ""

# Add to PATH if not already there
$pathEntry = $binDir
$userPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
$pathArray = $userPath -split ";"

if ($pathArray -contains $pathEntry) {
    Write-Host "PATH already contains $pathEntry" -ForegroundColor Green
    Write-Host "Try: che doctor" -ForegroundColor Cyan
} else {
    # Add to user PATH
    $newPath = $pathEntry + ";" + $userPath
    [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
    Write-Host "Added $pathEntry to user PATH" -ForegroundColor Green
    Write-Host ""
    Write-Host "⚠️  Restart your PowerShell or terminal for the PATH change to take effect." -ForegroundColor Yellow
    Write-Host "Then run: che doctor" -ForegroundColor Cyan
}

# Check for PowerShell profile (optional)
$profile = $PROFILE.CurrentUserAllHosts
if (Test-Path $profile) {
    Write-Host ""
    Write-Host "PowerShell profile found at: $profile" -ForegroundColor Cyan
    Write-Host "You can optionally add custom che aliases there." -ForegroundColor Gray
}

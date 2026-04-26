@echo off
REM che-cli batch wrapper for Windows
REM Routes che commands through Git Bash via the PowerShell wrapper.

setlocal enabledelayedexpansion

for %%I in ("%~dp0.") do set "BATCH_DIR=%%~fI"

powershell -NoProfile -ExecutionPolicy Bypass -File "%BATCH_DIR%\che.ps1" %*
exit /b %ERRORLEVEL%

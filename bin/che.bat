@echo off
REM che-cli batch wrapper for Windows PowerShell
REM This file routes che commands through Git Bash

setlocal enabledelayedexpansion

REM Get the directory where this batch file is located
for %%I in ("%~dp0.") do set "BATCH_DIR=%%~fI"

REM Call PowerShell with the wrapper script
powershell -NoProfile -ExecutionPolicy Bypass -File "%BATCH_DIR%\che.ps1" %*
exit /b %ERRORLEVEL%

# Forwards `che reinstall` to the repo's own install.ps1.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
& "$root\install.ps1" @args

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

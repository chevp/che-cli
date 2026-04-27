# che-cli PowerShell wrapper for Windows
# Routes bash commands through Git Bash (instead of WSL).

$ErrorActionPreference = 'Stop'

# Force UTF-8 so the ✓ / ✗ glyphs that bash emits aren't mojibake'd into
# Ô£ô / Ô£ù when PowerShell decodes them through the default OEM code page.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding           = [System.Text.Encoding]::UTF8
} catch {
    # Some hosts (e.g. ISE) won't allow this; fall through silently.
}

function Find-GitBash {
    # ProgramW6432 always points at the 64-bit Program Files, even when this
    # script is running inside a 32-bit PowerShell (e.g. spawned by the Inno
    # Setup post-install runner). Without it, $env:ProgramFiles would point
    # to "C:\Program Files (x86)" under WoW64 and we'd miss the real Git.
    $candidates = @(
        $env:CHE_GIT_BASH,
        "$env:ProgramW6432\Git\bin\bash.exe",
        "$env:ProgramW6432\Git\usr\bin\bash.exe",
        "$env:ProgramFiles\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\usr\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($c in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path $c)) {
            return $c
        }
    }
    return $null
}

$GitBash = Find-GitBash
if (-not $GitBash) {
    Write-Error @"
Git Bash not found. che-cli requires Git for Windows.
Install from: https://git-scm.com/download/win
Or set CHE_GIT_BASH to the full path of bash.exe.
"@
    exit 1
}

# Build the bash command with all arguments, quoting any with whitespace.
$argList = @()
foreach ($arg in $args) {
    if ($arg -match '\s') {
        $argList += "`"$arg`""
    } else {
        $argList += $arg
    }
}
$BashCmd = "che $($argList -join ' ')"

& $GitBash -c $BashCmd
exit $LASTEXITCODE

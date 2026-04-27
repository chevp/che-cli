# Forwards `che reinstall` to the repo's own install.ps1, translating
# bash-style flags (--no-deps, --no-ollama, ...) to the PowerShell-named
# parameters install.ps1 expects (-NoDeps, -NoOllama, ...). This way
# `che reinstall --no-deps` works the same on Windows and macOS/Linux.
#
# Important: PowerShell array splatting (@arr) passes elements positionally,
# so '-NoDeps' would bind to the first positional parameter ($Prefix). We
# build a hashtable and splat that instead, which routes by parameter name.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$params = @{}
$passthrough = @()
$i = 0
while ($i -lt $args.Count) {
    $a = $args[$i]
    switch -Regex ($a) {
        '^(--yes|-y)$'      { $params['AssumeYes'] = $true }
        '^--no-deps$'       { $params['NoDeps']    = $true }
        '^--no-ollama$'     { $params['NoOllama']  = $true }
        '^--no-model$'      { $params['NoModel']   = $true }
        '^--no-path-edit$'  { } # install.ps1 does not edit PATH; accept and drop
        '^--prefix$'        {
            $i++
            if ($i -lt $args.Count) { $params['Prefix'] = $args[$i] }
        }
        '^--help$|^-h$'     { Get-Help "$root\install.ps1" -Full | Out-Host; exit 0 }
        default             { $passthrough += $a } # leave PS-style flags alone
    }
    $i++
}

& "$root\install.ps1" @params @passthrough

# FORGE Security — PowerShell wrapper for forge-security.sh
# Usage: .\forge-security.ps1 --enroll [--channel <id>]
#        .\forge-security.ps1 --status
#        .\forge-security.ps1 --revoke <key-id>
#        .\forge-security.ps1 --unlock

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BashScript = Join-Path $ScriptDir "forge-security.sh"

$GitBash = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "$env:ProgramFiles\Git\usr\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LocalAppData\Programs\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $GitBash) {
    Write-Error "Git Bash not found. Install Git for Windows: https://git-scm.com"
    exit 1
}

$Content = [System.IO.File]::ReadAllText($BashScript)
$Content = $Content -replace '\r\n', "`n"
$Content = $Content -replace '(?m)^{%[^\n]*\n', ''

$TempFile = Join-Path $env:TEMP "forge-security-$PID.sh"
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($TempFile, $Content, $Utf8NoBom)

try {
    $BashPath = $TempFile -replace '\\', '/'
    $env:FORGE_SCRIPT_DIR = ($ScriptDir -replace '\\', '/')
    & $GitBash $BashPath @args
} finally {
    Remove-Item $TempFile -ErrorAction SilentlyContinue
}

# forge-status.ps1 — PowerShell wrapper for forge-status.sh

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BashScript = Join-Path $ScriptDir "forge-status.sh"

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

$TempFile = Join-Path $env:TEMP "forge-status-$PID.sh"
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($TempFile, $Content, $Utf8NoBom)

try {
    $BashPath = $TempFile -replace '\\', '/'
    $env:FORGE_SCRIPT_DIR = ($ScriptDir -replace '\\', '/')
    & $GitBash $BashPath @args
    exit $LASTEXITCODE
} finally {
    Remove-Item $TempFile -ErrorAction SilentlyContinue
}

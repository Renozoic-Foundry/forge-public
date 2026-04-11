# FORGE NanoClaw Prerequisites Installer — PowerShell wrapper
# Usage: .\forge-setup-nanoclaw.ps1 [--check-only]
#
# Requires Git Bash (bash.exe) — included with Git for Windows.

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BashScript = Join-Path $ScriptDir "forge-setup-nanoclaw.sh"

# Find Git Bash specifically (WSL bash uses Linux paths and wrong platform detection)
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

# Read the .sh file, strip Jinja2 raw/endraw tags, normalize to Unix line endings
$Content = [System.IO.File]::ReadAllText($BashScript)
$Content = $Content -replace '\r\n', "`n"
$Content = $Content -replace '(?m)^{%[^\n]*\n', ''

# Write cleaned script to temp file (UTF-8 no BOM — BOM breaks bash shebang)
$TempFile = Join-Path $env:TEMP "forge-setup-nanoclaw-$PID.sh"
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($TempFile, $Content, $Utf8NoBom)

try {
    # Git Bash understands C:/ paths with forward slashes
    $BashPath = $TempFile -replace '\\', '/'
    # Pass real script directory so FORGE_DIR resolves correctly from temp file
    $env:FORGE_SCRIPT_DIR = ($ScriptDir -replace '\\', '/')
    & $GitBash $BashPath @args
} finally {
    Remove-Item $TempFile -ErrorAction SilentlyContinue
}

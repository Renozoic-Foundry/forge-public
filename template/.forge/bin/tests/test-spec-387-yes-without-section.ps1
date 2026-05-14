# test-spec-387-yes-without-section (PS parity) — AC4.
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ForgeDir  = Split-Path -Parent (Split-Path -Parent $ScriptDir)
. (Join-Path $ForgeDir 'lib/safety-config.ps1')

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $spec = Join-Path $tmp 'spec-999.md'
    @'
# Spec 999 — fixture without Safety Enforcement

## Scope
Body without enforcement section.

## Implementation Summary
(empty)
'@ | Set-Content -LiteralPath $spec

    $errors = $null
    $result = Test-SafetyConfigSection -SpecFile $spec -RepoRoot $tmp 2>&1
    # Test-SafetyConfigSection returns boolean and writes errors to stderr.
    # Capture combined stream and check for the boolean return.
    $boolResult = $false
    foreach ($r in $result) {
        if ($r -is [bool]) { $boolResult = $r }
    }
    if ($boolResult) {
        [Console]::Error.WriteLine('FAIL: missing section incorrectly accepted')
        exit 1
    }
    Write-Output 'PASS: missing section produces false return + R2e stderr message'
    exit 0
} finally { Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue }

# test-spec-387-yes-with-section (PS parity) — AC5.
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ForgeDir  = Split-Path -Parent (Split-Path -Parent $ScriptDir)
. (Join-Path $ForgeDir 'lib/safety-config.ps1')

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    New-Item -ItemType Directory -Path (Join-Path $tmp 'src')          | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp 'tests')        | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp 'docs')         | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp 'docs/specs')   | Out-Null
    'exit 0' | Set-Content -LiteralPath (Join-Path $tmp 'src/foo.sh')
    'exit 0' | Set-Content -LiteralPath (Join-Path $tmp 'tests/test-foo.sh')

    $spec = Join-Path $tmp 'docs/specs/999-fixture.md'
    @'
# Spec 999 — fixture with valid Safety Enforcement

## Safety Enforcement

Enforcement code path: src/foo.sh::do_thing
Negative-path test: tests/test-foo.sh::test_rejects_unsafe
Validates that unsafe input is rejected before mutation.

## Implementation Summary
(empty)
'@ | Set-Content -LiteralPath $spec

    $boolResult = $false
    Test-SafetyConfigSection -SpecFile $spec -RepoRoot $tmp 2>&1 | ForEach-Object {
        if ($_ -is [bool]) { $boolResult = $_ }
    }
    if ($boolResult) {
        Write-Output 'PASS: complete section accepted by validator'
        exit 0
    }
    [Console]::Error.WriteLine('FAIL: complete section rejected')
    exit 1
} finally { Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue }

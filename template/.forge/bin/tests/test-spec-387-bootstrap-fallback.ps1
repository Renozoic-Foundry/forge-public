# test-spec-387-bootstrap-fallback (PowerShell parity) — AC9.
# When .forge/safety-config-paths.yaml is added or deleted, fallback fires (R1c).
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ForgeDir  = Split-Path -Parent (Split-Path -Parent $ScriptDir)
. (Join-Path $ForgeDir 'lib/safety-config.ps1')

$fails = 0

# Case A: A-status on registry → fallback fires
$inA = @("A`t.forge/safety-config-paths.yaml", "M`tREADME.md")
if (Test-SafetyConfigBootstrap -DiffStatus $inA) {
    Write-Output 'PASS: A-status on registry triggers bootstrap fallback'
} else {
    [Console]::Error.WriteLine('FAIL: A-status did NOT trigger fallback'); $fails++
}

# Case B: D-status on registry → fallback fires
$inB = @("D`t.forge/safety-config-paths.yaml")
if (Test-SafetyConfigBootstrap -DiffStatus $inB) {
    Write-Output 'PASS: D-status on registry triggers bootstrap fallback'
} else {
    [Console]::Error.WriteLine('FAIL: D-status did NOT trigger fallback'); $fails++
}

# Case C: M-status on registry → fallback does NOT fire
$inC = @("M`t.forge/safety-config-paths.yaml")
if (Test-SafetyConfigBootstrap -DiffStatus $inC) {
    [Console]::Error.WriteLine('FAIL: M-status incorrectly triggered fallback'); $fails++
} else {
    Write-Output 'PASS: M-status correctly skips fallback'
}

# Case D: unrelated diff
$inD = @("M`tAGENTS.md", "A`tdocs/specs/123-foo.md")
if (Test-SafetyConfigBootstrap -DiffStatus $inD) {
    [Console]::Error.WriteLine('FAIL: unrelated diff incorrectly triggered fallback'); $fails++
} else {
    Write-Output 'PASS: unrelated diff correctly skips fallback'
}

if ($fails -gt 0) {
    [Console]::Error.WriteLine("RESULT: $fails case(s) failed")
    exit 1
}
Write-Output 'RESULT: all 4 cases passed'
exit 0

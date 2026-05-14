# test-spec-387-override-validation (PowerShell parity) — AC7.
# Reason validation per R4b: ≥50 chars, non-trivial, case-insensitive trivial-string match.
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ForgeDir  = Split-Path -Parent (Split-Path -Parent $ScriptDir)
. (Join-Path $ForgeDir 'lib/safety-config.ps1')

$fails = 0

# Case A: too short
if (Test-SafetyConfigOverride -Reason 'Too short reason.' 2>$null) {
    [Console]::Error.WriteLine('FAIL: short reason should be rejected'); $fails++
} else {
    Write-Output 'PASS: short reason rejected (length-gate)'
}

# Case B: trivial 'wip'
if (Test-SafetyConfigOverride -Reason 'wip' 2>$null) {
    [Console]::Error.WriteLine("FAIL: 'wip' should be rejected"); $fails++
} else {
    Write-Output "PASS: trivial 'wip' rejected (length-gate fires first)"
}

# Case C: trivial 'OK' (case-insensitive)
if (Test-SafetyConfigOverride -Reason 'OK' 2>$null) {
    [Console]::Error.WriteLine("FAIL: 'OK' should be rejected"); $fails++
} else {
    Write-Output "PASS: case-insensitive trivial 'OK' rejected"
}

# Case D: valid 50+ chars
$valid = 'This onboarding YAML edit only renames the frontmatter pretty-print key — no safety property changes.'
if (Test-SafetyConfigOverride -Reason $valid 2>$null) {
    Write-Output 'PASS: valid 50+ char reason accepted'
} else {
    [Console]::Error.WriteLine('FAIL: valid reason rejected unexpectedly'); $fails++
}

# Case E: exactly 50 chars boundary
$fifty = 'abcdefghij abcdefghij abcdefghij abcdefghij abcde.'
if ($fifty.Length -ne 50) {
    [Console]::Error.WriteLine("FAIL: fixture setup error — case E reason is $($fifty.Length) chars"); $fails++
} elseif (Test-SafetyConfigOverride -Reason $fifty 2>$null) {
    Write-Output 'PASS: 50-char boundary reason accepted'
} else {
    [Console]::Error.WriteLine('FAIL: 50-char boundary rejected'); $fails++
}

# Case F: 49 chars (boundary-1)
$fortynine = 'abcdefghij abcdefghij abcdefghij abcdefghij abcd.'
if ($fortynine.Length -ne 49) {
    [Console]::Error.WriteLine("FAIL: fixture setup error — case F reason is $($fortynine.Length) chars"); $fails++
} elseif (Test-SafetyConfigOverride -Reason $fortynine 2>$null) {
    [Console]::Error.WriteLine('FAIL: 49-char should be rejected'); $fails++
} else {
    Write-Output 'PASS: 49-char rejected at boundary-1'
}

# Case G: whitespace-padded
$padded = "    $valid   "
if (Test-SafetyConfigOverride -Reason $padded 2>$null) {
    Write-Output 'PASS: whitespace-padded reason accepted (trim works)'
} else {
    [Console]::Error.WriteLine('FAIL: whitespace-padded rejected'); $fails++
}

if ($fails -gt 0) {
    [Console]::Error.WriteLine("RESULT: $fails case(s) failed")
    exit 1
}
Write-Output 'RESULT: all 7 cases passed'
exit 0

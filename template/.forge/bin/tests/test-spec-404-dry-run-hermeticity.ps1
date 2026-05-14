# test-spec-404-dry-run-hermeticity.ps1
#
# PowerShell parity tests for Spec 404 hermeticity helper.

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Helper = Join-Path $ScriptDir 'lib/assert-hermetic-dry-run.ps1'

if (-not (Test-Path -LiteralPath $Helper)) {
    Write-Error "Helper not found at $Helper"
    exit 1
}

. $Helper

$Pass = 0
$Fail = 0

function PassTest([string]$msg) { $script:Pass++; Write-Host "  PASS: $msg" }
function FailTest([string]$msg) { $script:Fail++; Write-Host "  FAIL: $msg" -ForegroundColor Red }

function New-StageDir {
    $p = Join-Path ([System.IO.Path]::GetTempPath()) ("spec404-" + [System.Guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    return $p
}

# Test 1: empty dir, no-op
Write-Host "Test 1: no-op against empty dir"
$dir = New-StageDir
try {
    $hermetic = Assert-HermeticDryRun -StagingDir $dir -Command { } 2>$null
    if ($hermetic) { PassTest "no-op hermetic" } else { FailTest "no-op flagged" }
} finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

# Test 2: mutating command
Write-Host "Test 2: mutating command against empty dir"
$dir = New-StageDir
try {
    $leak = Join-Path $dir 'leak.txt'
    $hermetic = Assert-HermeticDryRun -StagingDir $dir -Command { Set-Content -LiteralPath $script:leak -Value 'mutation' } 2>$null
    if ($hermetic) { FailTest "mutation NOT detected" } else { PassTest "mutation detected" }
} finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

# Test 3: no-op against populated dir
Write-Host "Test 3: no-op against pre-populated dir"
$dir = New-StageDir
try {
    Set-Content -LiteralPath (Join-Path $dir 'a.txt') -Value 'alpha'
    New-Item -ItemType Directory -Path (Join-Path $dir 'sub') | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'sub/b.txt') -Value 'beta'
    $hermetic = Assert-HermeticDryRun -StagingDir $dir -Command { } 2>$null
    if ($hermetic) { PassTest "no-op hermetic on populated dir" } else { FailTest "no-op flagged on populated dir" }
} finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

# Test 4: content mutation
Write-Host "Test 4: content mutation"
$dir = New-StageDir
try {
    $a = Join-Path $dir 'a.txt'
    Set-Content -LiteralPath $a -Value 'alpha'
    $hermetic = Assert-HermeticDryRun -StagingDir $dir -Command { Set-Content -LiteralPath $script:a -Value 'altered' } 2>$null
    if ($hermetic) { FailTest "content mutation NOT detected" } else { PassTest "content mutation detected" }
} finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

# Test 5: nonexistent dir → throws
Write-Host "Test 5: nonexistent staging dir"
$threw = $false
try {
    Assert-HermeticDryRun -StagingDir 'C:\this\does\not\exist-spec-404' -Command { } 2>$null | Out-Null
} catch {
    $threw = $true
}
if ($threw) { PassTest "nonexistent dir threw" } else { FailTest "nonexistent dir did not throw" }

# Test 6: mtime-only change
Write-Host "Test 6: mtime-only change does NOT trip helper"
$dir = New-StageDir
try {
    $a = Join-Path $dir 'a.txt'
    Set-Content -LiteralPath $a -Value 'stable'
    $hermetic = Assert-HermeticDryRun -StagingDir $dir -Command {
        (Get-Item -LiteralPath $script:a).LastWriteTime = (Get-Date)
    } 2>$null
    if ($hermetic) { PassTest "mtime-only change is hermetic (correctly)" } else { FailTest "mtime-only flagged incorrectly" }
} finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "Spec 404 helper tests: $Pass passed, $Fail failed"
if ($Fail -eq 0) { exit 0 } else { exit 1 }

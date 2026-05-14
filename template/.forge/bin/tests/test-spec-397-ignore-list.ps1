# Spec 397 — safety-config audit ignore-list fixture (PowerShell parity).
#
# Covers AC4 — see test-spec-397-ignore-list.sh for the full description.
# Uses the PS audit script + helper directly; tests are functionally identical
# assertions to the bash fixture so AC4 holds on both platforms.

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir '../../..')
$Audit     = Join-Path $RepoRoot 'scripts/safety-backfill-audit.ps1'

if (-not (Test-Path -LiteralPath $Audit -PathType Leaf)) {
    Write-Output "FAIL — safety-backfill-audit.ps1 not found at $Audit"
    exit 1
}

$TmpRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("forge-spec-397-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TmpRepo | Out-Null
try {
    New-Item -ItemType Directory -Path (Join-Path $TmpRepo 'scripts') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TmpRepo '.forge/lib') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TmpRepo '.forge/state') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TmpRepo 'docs/specs') | Out-Null

    Copy-Item -LiteralPath $Audit                                       -Destination (Join-Path $TmpRepo 'scripts/safety-backfill-audit.ps1')
    Copy-Item -LiteralPath (Join-Path $RepoRoot '.forge/lib/safety-config.ps1') -Destination (Join-Path $TmpRepo '.forge/lib/safety-config.ps1')

    $synthCfg = Join-Path $TmpRepo 'test-config.yaml'
    @"
# Synthetic config for Spec 397 fixture
require_fixture_token: true
guard_real_safety: true
"@ | Set-Content -LiteralPath $synthCfg -Encoding utf8

    @"
patterns:
  - test-config.yaml
"@ | Set-Content -LiteralPath (Join-Path $TmpRepo '.forge/safety-config-paths.yaml') -Encoding utf8

    @"
version: 1
ignore:
  - token: require_fixture_token
    reason: "Spec 397 fixture token - not a real safety property."
    added: 2026-05-08
    spec: 397
"@ | Set-Content -LiteralPath (Join-Path $TmpRepo '.forge/safety-config-ignore.yaml') -Encoding utf8

    $pass = 0
    $fail = 0
    function Mark-Pass($n) { Write-Output "  PASS - $n"; $script:pass++ }
    function Mark-Fail($n) { Write-Output "  FAIL - $n"; $script:fail++ }

    Push-Location $TmpRepo
    try {
        # AC4a + AC4b: dry-run output.
        $dryOut = & pwsh -NoProfile -File (Join-Path $TmpRepo 'scripts/safety-backfill-audit.ps1') -DryRun 2>&1 | Out-String

        if ($dryOut -match '(?m)^MISSING:.*require_fixture_token') {
            Mark-Fail 'AC4a - require_fixture_token must NOT appear in list (ii) MISSING'
        } else {
            Mark-Pass 'AC4a - require_fixture_token suppressed from list (ii)'
        }

        if ($dryOut -match '(?m)^IGNORED:.*require_fixture_token.*Spec 397 fixture token') {
            Mark-Pass 'AC4b - require_fixture_token in list (iii) with reason text'
        } else {
            Mark-Fail 'AC4b - require_fixture_token must appear in list (iii) with reason'
            $dryOut -split "`n" | ForEach-Object { Write-Output "    $_" }
        }

        if ($dryOut -match '(?m)^MISSING:.*guard_real_safety') {
            Mark-Pass 'control - non-ignored token still appears in (ii) MISSING'
        } else {
            Mark-Fail 'control - guard_real_safety should appear in (ii) MISSING'
        }

        # AC4c: --check-only must be silent for ignored tokens.
        $chkOut = & pwsh -NoProfile -File (Join-Path $TmpRepo 'scripts/safety-backfill-audit.ps1') -CheckOnly 2>&1 | Out-String

        if ($chkOut -match 'require_fixture_token') {
            Mark-Fail 'AC4c - --check-only must NOT mention require_fixture_token'
            $chkOut -split "`n" | ForEach-Object { Write-Output "    $_" }
        } else {
            Mark-Pass 'AC4c - --check-only silent on ignored token'
        }

        if ($chkOut -match '(?m)^MISSING:.*guard_real_safety') {
            Mark-Pass 'control - --check-only emits MISSING for guard_real_safety'
        } else {
            Mark-Fail 'control - --check-only should emit MISSING for guard_real_safety'
        }
    } finally {
        Pop-Location
    }

    Write-Output ''
    Write-Output "Spec 397 fixture: $pass pass / $fail fail"
    if ($fail -ne 0) { exit 1 }
    exit 0
} finally {
    Remove-Item -LiteralPath $TmpRepo -Recurse -Force -ErrorAction SilentlyContinue
}

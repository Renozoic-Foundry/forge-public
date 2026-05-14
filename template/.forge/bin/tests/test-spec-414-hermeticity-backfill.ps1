# test-spec-414-hermeticity-backfill.ps1 — Spec 414
#
# PowerShell parity for test-spec-414-hermeticity-backfill.sh.
# Tests the .ps1 variants of FORGE-shipped scripts identified as non-compliant
# by Spec 404's audit. Five of the six in-scope scripts ship a .ps1 variant
# (backfill-valid-until.sh has no .ps1), so the in-scope set here is 5.
#
# Per Spec 414:
#   AC2: emits one trace line per in-scope script regardless of outcome.
#   AC3/AC4: per-script PASS/FAIL/SKIP. SKIP requires a specific
#            missing-dependency reason. SKIP cap scales with in-scope count
#            (2 of 5 here, matching the 2 of 6 bash cap).
#
# Hermeticity definition: same as the bash helper — staging dir hashed
# before/after; mutation = FAIL.

$ErrorActionPreference = 'Stop'

$ForgeSrc = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Helper = Join-Path $ForgeSrc '.forge\bin\tests\lib\assert-hermetic-dry-run.ps1'
. $Helper

$TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("spec-414-hermetic-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null

$script:Pass = 0
$script:Fail = 0
$script:Skip = 0
$Results = New-Object System.Collections.ArrayList

function Stage-Tree {
    param([string] $Dest)
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    # robocopy on Windows; fall back to Copy-Item -Recurse
    if (Get-Command robocopy -ErrorAction SilentlyContinue) {
        # robocopy returns nonzero on success; suppress and check explicitly
        & robocopy $ForgeSrc $Dest /E /XD .git node_modules tmp .forge\state /NFL /NDL /NJH /NJS /NP /NS /NC | Out-Null
    } else {
        Get-ChildItem -LiteralPath $ForgeSrc -Force | Where-Object {
            $_.Name -notin @('.git', 'node_modules', 'tmp')
        } | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $Dest -Recurse -Force
        }
        # Strip .forge/state if present (cross-platform exclusion)
        $stateDir = Join-Path $Dest '.forge\state'
        if (Test-Path -LiteralPath $stateDir) {
            Remove-Item -LiteralPath $stateDir -Recurse -Force
        }
    }
}

function Trace-Result {
    param([string] $Script, [string] $Outcome, [string] $Detail)
    if ($Detail) {
        Write-Host ("TEST {0} — {1} — {2}" -f $Script, $Outcome, $Detail)
    } else {
        Write-Host ("TEST {0} — {1}" -f $Script, $Outcome)
    }
}

function Record-Pass {
    param([string] $Script)
    $script:Pass = $script:Pass + 1
    [void]$Results.Add(@{ Outcome = 'PASS'; Script = $Script; Reason = '' })
    Trace-Result -Script $Script -Outcome 'PASS' -Detail ''
}

function Record-Fail {
    param([string] $Script, [string] $Reason)
    $script:Fail = $script:Fail + 1
    [void]$Results.Add(@{ Outcome = 'FAIL'; Script = $Script; Reason = $Reason })
    Trace-Result -Script $Script -Outcome 'FAIL' -Detail $Reason
}

function Record-Skip {
    param([string] $Script, [string] $Reason)
    $script:Skip = $script:Skip + 1
    [void]$Results.Add(@{ Outcome = 'SKIP'; Script = $Script; Reason = $Reason })
    Trace-Result -Script $Script -Outcome 'SKIP' -Detail $Reason
}

function Test-Hermetic {
    param([string] $RelScript, [string] $StageName, [string[]] $ExtraArgs = @())
    $stage = Join-Path $TmpRoot $StageName
    Stage-Tree -Dest $stage
    $stagedScript = Join-Path $stage $RelScript
    $logf = Join-Path $TmpRoot ("$StageName.log")
    # PowerShell scripts take -DryRun (switch), not --dry-run (bash style).
    # Capture closure-scoped vars so the scriptblock sees them.
    $invokeScript = $stagedScript
    $invokeArgs = $ExtraArgs
    $invokeLog = $logf
    try {
        $hermetic = Assert-HermeticDryRun -StagingDir $stage -Command {
            & pwsh -NoProfile -File $invokeScript -DryRun @invokeArgs *>&1 | Tee-Object -FilePath $invokeLog | Out-Null
        }.GetNewClosure()
        if ($hermetic) {
            Record-Pass -Script $RelScript
        } else {
            Record-Fail -Script $RelScript -Reason "staging dir mutated; see $logf"
        }
    } catch {
        Record-Fail -Script $RelScript -Reason ("invocation error: {0}" -f $_.Exception.Message)
    }
}

Write-Host "=== Spec 414 dry-run hermeticity backfill (PowerShell) ==="
Write-Host "FORGE_SRC: $ForgeSrc"
Write-Host "TMPROOT:   $TmpRoot"
Write-Host ""

# 1. scripts/safety-backfill-audit.ps1
Test-Hermetic -RelScript 'scripts\safety-backfill-audit.ps1' -StageName 'stage-safety-audit'

# 2. .forge/bin/forge-sync-commands.ps1
Test-Hermetic -RelScript '.forge\bin\forge-sync-commands.ps1' -StageName 'stage-sync-commands' -ExtraArgs @('-Scope', 'project')

# 3. .forge/bin/forge-sync-cross-level.ps1
Test-Hermetic -RelScript '.forge\bin\forge-sync-cross-level.ps1' -StageName 'stage-sync-crosslevel'

# 4. .forge/bin/forge-orchestrate.ps1 — SKIP
Record-Skip -Script '.forge\bin\forge-orchestrate.ps1' -Reason 'requires --spec NNN argument plus .forge\sessions\ session-state initialization outside CI scope; specific blocker = orchestrator session-init prerequisite (Spec 269)'

# 5. .forge/bin/forge-install.ps1 — SKIP
Record-Skip -Script '.forge\bin\forge-install.ps1' -Reason 'requires Copier-rendered target directory with .copier-answers.yml; specific blocker = target-dir bootstrap outside FORGE source tree (Spec 077)'

Write-Host ""
Write-Host "=== Summary ==="
Write-Host ("PASS: {0}  FAIL: {1}  SKIP: {2}  (of 5 .ps1 variants in scope)" -f $script:Pass, $script:Fail, $script:Skip)

# Self-verification per AC2 (parity): every .ps1 variant in scope must appear.
$Expected = @(
    'scripts\safety-backfill-audit.ps1',
    '.forge\bin\forge-sync-commands.ps1',
    '.forge\bin\forge-sync-cross-level.ps1',
    '.forge\bin\forge-orchestrate.ps1',
    '.forge\bin\forge-install.ps1'
)
foreach ($e in $Expected) {
    if (-not ($Results | Where-Object { $_.Script -eq $e })) {
        Write-Error "SELF-VERIFY FAIL: missing trace for $e"
        Remove-Item -LiteralPath $TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        exit 3
    }
}

# SKIP cap scales with in-scope size: 2 of 5 (matches 2 of 6 bash cap).
if ($script:Skip -gt 2) {
    Write-Error ("HARNESS FAIL: SKIP count ({0}) exceeds Spec 414 cap (2 of 5 for .ps1 variants)." -f $script:Skip)
    Remove-Item -LiteralPath $TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    exit 2
}

if ($script:Fail -gt 0) {
    Write-Error ("Hermeticity FAIL recorded for {0} script(s). Per AC5, file follow-up bug-fix specs and record their IDs in each owning spec's Revision Log before /close." -f $script:Fail)
    Remove-Item -LiteralPath $TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "All in-scope .ps1 variants PASS or SKIP-with-reason."
Remove-Item -LiteralPath $TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
exit 0

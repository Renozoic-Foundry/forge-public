<#
FORGE Lane-Ceiling Check (PowerShell parity) — Spec 611 Requirement 5 / AC9

Compares a spec's DECLARED `Change-Lane:` against OBJECTIVE diff signals (files touched,
LOC delta, dependency-manifest changes) and FLAGS a mismatch for operator/DA attention.

FLAG-ONLY — LOAD-BEARING CONSTRAINT (Spec 611 Constraints): this script MUST NOT reclassify
the lane and MUST NOT write to the spec file at all. Auto-correcting the lane would recreate
the self-authorization surface the check exists to close. The script only ever READS the spec.
Spec 611 AC7 asserts this mechanically (frontmatter bytes compared before and after a run).

Posture: advisory by default (flag, exit 0). -Strict makes a mismatch exit 1 for CI use.

Exit codes: 0 = no mismatch, or mismatch in advisory mode. 1 = mismatch under -Strict.
            2 = usage/input error.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)] [string] $SpecFile,
  [string] $Base = 'HEAD',
  [switch] $Strict,
  [string] $ChangedFilesFrom,
  [string] $Repo = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SpecFile -PathType Leaf)) {
  Write-Error "lane-ceiling-check: spec file missing or unreadable: '$SpecFile'"
  exit 2
}

# ---- Read the declared lane (READ-ONLY; this script never writes the spec) ----------------
$declaredLane = $null
foreach ($line in (Get-Content -LiteralPath $SpecFile)) {
  if ($line -match '^- Change-Lane:\s*(.+?)\s*$') {
    $declaredLane = $Matches[1] -replace '`', ''
    $declaredLane = $declaredLane.Trim()
    break
  }
}
if ([string]::IsNullOrWhiteSpace($declaredLane)) {
  Write-Error "lane-ceiling-check: no 'Change-Lane:' found in $SpecFile"
  exit 2
}

# ---- Collect objective diff signals -------------------------------------------------------
$changedFiles = @()
if (-not [string]::IsNullOrWhiteSpace($ChangedFilesFrom)) {
  if (-not (Test-Path -LiteralPath $ChangedFilesFrom -PathType Leaf)) {
    Write-Error "lane-ceiling-check: -ChangedFilesFrom path unreadable: '$ChangedFilesFrom'"
    exit 2
  }
  $changedFiles = @(Get-Content -LiteralPath $ChangedFilesFrom | Where-Object { $_.Trim() -ne '' })
} else {
  $tracked = @()
  $untracked = @()
  try { $tracked = @(& git -C $Repo diff --name-only $Base 2>$null) } catch { $tracked = @() }
  try { $untracked = @(& git -C $Repo ls-files --others --exclude-standard 2>$null) } catch { $untracked = @() }
  $changedFiles = @(($tracked + $untracked) | Where-Object { $_ -and $_.Trim() -ne '' } | Sort-Object -Unique)
}

$fileCount = $changedFiles.Count

$locDelta = 0
if ([string]::IsNullOrWhiteSpace($ChangedFilesFrom)) {
  try {
    foreach ($row in (& git -C $Repo diff --numstat $Base 2>$null)) {
      $parts = $row -split "`t"
      if ($parts.Count -ge 2) {
        $a = 0; $d = 0
        if ($parts[0] -ne '-') { [void][int]::TryParse($parts[0], [ref]$a) }
        if ($parts[1] -ne '-') { [void][int]::TryParse($parts[1], [ref]$d) }
        $locDelta += $a + $d
      }
    }
  } catch { $locDelta = 0 }
}

$depPattern = '(^|/)(package\.json|requirements([-.].*)?\.txt|pyproject\.toml|Cargo\.toml|go\.mod|Gemfile|pom\.xml|build\.gradle(\.kts)?)$'
$depHits = @($changedFiles | Where-Object { $_ -match $depPattern })
$depTouched = [int]($depHits.Count -gt 0)

$nonDocsHits = @($changedFiles | Where-Object { $_ -match '\.(sh|ps1|py|js|ts|jinja)$' })

# ---- Lane ceilings ------------------------------------------------------------------------
# Bands derive from the scoring-rubric E anchors and the AGENTS.md lane definitions. They are
# advisory thresholds for FLAGGING, not lane law. Kept in sync with lane-ceiling-check.sh.
$mismatches = New-Object System.Collections.Generic.List[string]

switch ($declaredLane) {
  'hotfix' {
    if ($fileCount -gt 3) {
      $mismatches.Add("declared ``hotfix`` but the diff touches $fileCount files (ceiling 3). AGENTS.md: a hotfix edits only files within an already-open spec's scope.")
    }
    if ($locDelta -gt 100) {
      $mismatches.Add("declared ``hotfix`` but the diff changes $locDelta lines (ceiling 100).")
    }
    if ($depTouched -eq 1) {
      $mismatches.Add("declared ``hotfix`` but a dependency manifest changed: $($depHits -join ' ')")
    }
  }
  'small-change' {
    if ($fileCount -gt 5) {
      $mismatches.Add("declared ``small-change`` but the diff touches $fileCount files (ceiling 5).")
    }
    if ($locDelta -gt 300) {
      $mismatches.Add("declared ``small-change`` but the diff changes $locDelta lines (ceiling 300).")
    }
    if ($depTouched -eq 1) {
      $mismatches.Add("declared ``small-change`` but a dependency manifest changed: $($depHits -join ' ')")
    }
  }
  'process-only' {
    if ($nonDocsHits.Count -gt 0) {
      $mismatches.Add("declared ``process-only`` (docs/tracking only) but the diff touches executable/template files: $($nonDocsHits -join ' ')")
    }
    if ($depTouched -eq 1) {
      $mismatches.Add("declared ``process-only`` but a dependency manifest changed: $($depHits -join ' ')")
    }
  }
  'standard-feature' {
    # widest lane — no upper ceiling to flag against
  }
  default {
    $mismatches.Add("unrecognized Change-Lane '``$declaredLane``' (expected hotfix | small-change | standard-feature | process-only).")
  }
}

# ---- Report -------------------------------------------------------------------------------
if ($mismatches.Count -eq 0) {
  Write-Output "GATE [lane-ceiling]: PASS — declared ``$declaredLane`` is consistent with the diff ($fileCount file(s), $locDelta line(s) changed)."
  exit 0
}

Write-Output "GATE [lane-ceiling]: FLAG — declared lane ``$declaredLane`` does not match the diff signals."
foreach ($m in $mismatches) { Write-Output "  - $m" }
Write-Output "  Signals: files=$fileCount lines=$locDelta dependency-manifest-touched=$depTouched"
Write-Output "  This is ADVISORY and FLAG-ONLY — the lane was NOT changed and this spec file was NOT written to."
Write-Output "  Remediation: either widen Change-Lane via /revise (operator decision), or record why the"
Write-Output "  declared lane is still correct. Auto-reclassification is deliberately not implemented"
Write-Output "  (Spec 611: it would recreate the self-authorization surface this check exists to close)."

if ($Strict) { exit 1 }
exit 0

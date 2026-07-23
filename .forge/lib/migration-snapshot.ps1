# FORGE phase-D migration snapshot/restore (Spec 489 D6 / R7 / AC6), PowerShell parity.
# Snapshot rollback-critical files before rendered-hook removal; restore verbatim on rollback.
# NEVER re-renders from Copier — restore reads only from the snapshot and refuses if it is absent.
#
# Project-root resolution (Spec 597 — explicit parameter wins over any location inference;
# NEVER falls back to guessing from this script's own physical path):
#   1. -Root DIR         explicit parameter (highest priority)
#   2. $env:PROJECT_ROOT explicit env var (used only if -Root is not given)
#   3. `git -C <cwd> rev-parse --show-toplevel` — last-resort fallback for direct manual
#      invocation only (operator running the script by hand from inside their project)
#   4. neither resolves -> clear error, exit non-zero (never silently falls through to a
#      script-location guess)
param(
  [Parameter(Mandatory)][ValidateSet('snapshot','restore')][string]$Action,
  [string]$Root
)
$ErrorActionPreference = 'Stop'

if ($Root) {
  $projectRoot = $Root
} elseif ($env:PROJECT_ROOT) {
  $projectRoot = $env:PROJECT_ROOT
} else {
  $cwd = (Get-Location).Path
  $toplevel = git -C $cwd rev-parse --show-toplevel 2>$null
  if ($LASTEXITCODE -eq 0 -and $toplevel) {
    $projectRoot = $toplevel.Trim()
  } else {
    Write-Error "migration-snapshot: no -Root/PROJECT_ROOT given and '$cwd' is not inside a git repository - cannot resolve the project root. Pass -Root DIR or set PROJECT_ROOT."
    exit 2
  }
}

if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
  Write-Error "migration-snapshot: resolved PROJECT_ROOT '$projectRoot' is not a directory."
  exit 2
}
$projectRoot = (Resolve-Path -LiteralPath $projectRoot).Path

$snapDir = Join-Path $projectRoot '.forge/state/migration-snapshot'
$files = @('.claude/settings.json', 'CLAUDE.md', 'AGENTS.md')

if ($Action -eq 'snapshot') {
  New-Item -ItemType Directory -Force -Path $snapDir | Out-Null
  $n = 0
  foreach ($f in $files) {
    $src = Join-Path $projectRoot $f
    if (Test-Path -LiteralPath $src) {
      $dst = Join-Path $snapDir $f
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
      Copy-Item -LiteralPath $src $dst -Force
      $n++
    }
  }
  Write-Output "migration-snapshot: snapshotted $n rollback-critical path(s) -> $snapDir"
} else {
  if (-not (Test-Path -LiteralPath $snapDir)) {
    Write-Error "migration-snapshot: no snapshot at $snapDir - refusing (rollback restores from the snapshot, never re-renders)."
    exit 1
  }
  $n = 0
  foreach ($f in $files) {
    $src = Join-Path $snapDir $f
    if (Test-Path -LiteralPath $src) {
      $dst = Join-Path $projectRoot $f
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
      Copy-Item -LiteralPath $src $dst -Force
      $n++
    }
  }
  Write-Output "migration-snapshot: restored $n path(s) verbatim from snapshot (no re-render)."
}

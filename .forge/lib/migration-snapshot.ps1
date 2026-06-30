# FORGE phase-D migration snapshot/restore (Spec 489 D6 / R7 / AC6), PowerShell parity.
# Snapshot rollback-critical files before rendered-hook removal; restore verbatim on rollback.
# NEVER re-renders from Copier — restore reads only from the snapshot and refuses if it is absent.
param([Parameter(Mandatory)][ValidateSet('snapshot','restore')][string]$Action)
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Resolve-Path (Join-Path $scriptDir '../..')).Path
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

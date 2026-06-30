#!/usr/bin/env pwsh
# Spec 494 — stash-reintroduction lint (PowerShell parity of forge-stash-lint.sh).
# FAILs if any command body introduces a stashing `git stash` lacking
# --include-untracked / -u (the EA-086 / EA-424 WIP-loss class). Forward guard:
# no such instruction exists today, so this passes clean on the current tree.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dirs = @(
  (Join-Path $root '.forge/commands'),
  (Join-Path $root '.claude/commands'),
  (Join-Path $root 'template/.forge/commands'),
  (Join-Path $root 'template/.claude/commands')
)
$violations = 0
foreach ($d in $dirs) {
  if (-not (Test-Path $d)) { continue }
  $hits = Select-String -Path (Join-Path $d '*.md') -Pattern 'git stash' -ErrorAction SilentlyContinue
  foreach ($h in $hits) {
    $line = $h.Line
    if ($line -match 'git stash\b' -and
        $line -notmatch 'git stash (pop|apply|list|show|drop|clear|branch)' -and
        $line -notmatch '(--include-untracked|\s-u\b)') {
      Write-Output ("  VIOLATION: {0}:{1}:{2}" -f $h.Path, $h.LineNumber, $line)
      $violations++
    }
  }
}
if ($violations -gt 0) {
  Write-Output "GATE [stash-reintroduction]: FAIL — $violations unsafe git stash (no --include-untracked) in command bodies."
  exit 1
}
Write-Output "GATE [stash-reintroduction]: PASS — no unsafe git stash in command bodies."
exit 0

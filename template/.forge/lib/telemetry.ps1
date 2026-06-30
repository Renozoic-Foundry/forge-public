#!/usr/bin/env pwsh
# FORGE telemetry helper — durable security-gate verdict ledger (Spec 495), PowerShell parity.
# Records security-gate PASS/FAIL verdicts to a TRACKED ledger (survives clean clone).
# Advisory: failures emit a warning but always exit 0. Telemetry only — not tamper-evident,
# never a security authority. See docs/process-kit/telemetry-capture-guide.md.
#
# Usage: telemetry.ps1 record-security-gate <gate_name> <PASS|FAIL> <exit_code> [sha]

$ErrorActionPreference = 'Continue'
$LedgerFile = if ($env:FORGE_SECURITY_GATE_FILE) { $env:FORGE_SECURITY_GATE_FILE } else { '.forge/state/security-gate.jsonl' }

function Get-IsoTs { (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
function Get-GitSha { try { (git rev-parse HEAD 2>$null) ?? 'unknown' } catch { 'unknown' } }
function ConvertTo-JsonEscaped([string]$s) {
  if ($null -eq $s) { return '' }
  $s = $s -replace '\\','\\\\' -replace '"','\"' -replace "`n",'\n' -replace "`t",'\t' -replace "`r",'\r'
  return $s
}

function Record-SecurityGate {
  param([string]$Gate, [string]$Result, [string]$ExitCode, [string]$Sha)
  if (-not $Gate -or -not $Result -or -not $ExitCode) {
    Write-Warning "record-security-gate needs <gate_name> <PASS|FAIL> <exit_code> [sha] (advisory; skipping)"; return
  }
  if ($Result -notin @('PASS','FAIL')) { Write-Warning "result must be PASS or FAIL (got: $Result); skipping"; return }
  if (-not $Sha) { $Sha = Get-GitSha }
  try {
    $dir = Split-Path -Parent $LedgerFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $rec = '{{"timestamp":"{0}","gate":"{1}","result":"{2}","exit_code":"{3}","sha":"{4}"}}' -f `
      (Get-IsoTs), (ConvertTo-JsonEscaped $Gate), $Result, (ConvertTo-JsonEscaped $ExitCode), (ConvertTo-JsonEscaped $Sha)
    Add-Content -Path $LedgerFile -Value $rec -Encoding utf8 -ErrorAction Stop
  } catch {
    Write-Warning "security-gate append failed (advisory; caller continues): $_"
  }
}

$cmd = if ($args.Count -ge 1) { $args[0] } else { '' }
$rest = if ($args.Count -ge 2) { $args[1..($args.Count-1)] } else { @() }
switch ($cmd) {
  'record-security-gate' { Record-SecurityGate -Gate $rest[0] -Result $rest[1] -ExitCode $rest[2] -Sha $rest[3] }
  default { Write-Warning "unknown telemetry subcommand: $cmd (advisory; no-op)" }
}
exit 0

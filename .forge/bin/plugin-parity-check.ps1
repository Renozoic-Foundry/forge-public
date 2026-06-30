#!/usr/bin/env pwsh
# FORGE plugin-parity-check (Spec 463, P1=C two-source parity gate) — PowerShell mirror.
#
# Verifies byte-level parity between the two payload sources over the common subset:
#   - template/.claude/  (Copier source)
#   - .claude/           (plugin payload source, referenced by .claude-plugin/plugin.json)
# Common subset: commands/, agents/, skills/.
#
# Exit codes: 0 = no drift; 1 = drift detected or error.
[CmdletBinding()]
param(
  [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
  Write-Output @'
Usage: plugin-parity-check.ps1

Spec 463 (P1=C) plugin parity gate. Verifies byte-level parity between the two
payload sources over the common subset (commands/, agents/, skills/):
  - template/.claude/  (Copier source)
  - .claude/           (plugin payload source)
Exit 0 on parity; exit 1 on any byte-level drift.
'@
  exit 0
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = (Resolve-Path (Join-Path $ScriptDir '..' '..')).Path

$PluginSrc = Join-Path $RepoRoot '.claude'
$CopierSrc = Join-Path $RepoRoot 'template/.claude'
$SubDirs   = @('commands', 'agents', 'skills')

# Single source of truth for intentional FORGE-self-vs-consumer divergence: the same
# escape-hatch the cross-level generator uses (Spec 270). Commands listed there are
# OUT of the parity common subset by design.
$EscapeHatch = Join-Path $RepoRoot '.forge/state/expected-cross-level-drift.txt'
$ExpectedDriftBasename = New-Object System.Collections.Generic.HashSet[string]
if (Test-Path -LiteralPath $EscapeHatch -PathType Leaf) {
  foreach ($line in Get-Content -LiteralPath $EscapeHatch) {
    if ($line -match '^\s*#') { continue }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $pathPart = ($line -split '\|')[0].Trim()
    if ($pathPart -like '.forge/commands/*.md') {
      [void]$ExpectedDriftBasename.Add((Split-Path $pathPart -Leaf))
    }
  }
}

Write-Output '## plugin-parity-check (Spec 463 / P1=C)'
Write-Output ''
Write-Output "Plugin payload source : $PluginSrc"
Write-Output "Copier source         : $CopierSrc"
Write-Output ''

if (-not (Test-Path -LiteralPath $PluginSrc -PathType Container)) {
  Write-Error "plugin payload source not found: $PluginSrc"
  exit 1
}
if (-not (Test-Path -LiteralPath $CopierSrc -PathType Container)) {
  Write-Error "Copier source not found: $CopierSrc"
  exit 1
}

$Drift = New-Object System.Collections.Generic.List[string]

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

foreach ($sub in $SubDirs) {
  $pluginDir = Join-Path $PluginSrc $sub
  $copierDir = Join-Path $CopierSrc $sub

  $pluginExists = Test-Path -LiteralPath $pluginDir -PathType Container
  $copierExists = Test-Path -LiteralPath $copierDir -PathType Container

  if (-not $pluginExists -and -not $copierExists) { continue }
  if (-not $pluginExists) { $Drift.Add("$sub/ — present in Copier source, MISSING from plugin source"); continue }
  if (-not $copierExists) { $Drift.Add("$sub/ — present in plugin source, MISSING from Copier source"); continue }

  # Exclusions (all intentional): .jinja variations (Spec 281/390); a plugin-side
  # <name>.md whose Copier counterpart is <name>.md.jinja; and commands on the
  # expected-cross-level-drift escape-hatch (Spec 270).
  $rels = New-Object System.Collections.Generic.HashSet[string]
  Get-ChildItem -LiteralPath $pluginDir -Recurse -File | Where-Object { $_.Name -notlike '*.jinja' } | ForEach-Object {
    $r = $_.FullName.Substring($pluginDir.Length).TrimStart('\','/')
    $rNorm = $r -replace '\\','/'
    if ($sub -eq 'commands' -and (Test-Path -LiteralPath (Join-Path $copierDir "$r.jinja"))) { return }
    if ($sub -eq 'commands' -and $ExpectedDriftBasename.Contains($rNorm)) { return }
    [void]$rels.Add($rNorm)
  }
  Get-ChildItem -LiteralPath $copierDir -Recurse -File | Where-Object { $_.Name -notlike '*.jinja' } | ForEach-Object {
    $r = $_.FullName.Substring($copierDir.Length).TrimStart('\','/')
    $rNorm = $r -replace '\\','/'
    if ($sub -eq 'commands' -and $ExpectedDriftBasename.Contains($rNorm)) { return }
    [void]$rels.Add($rNorm)
  }

  foreach ($rel in $rels) {
    $pf = Join-Path $pluginDir $rel
    $cf = Join-Path $copierDir $rel
    $pfExists = Test-Path -LiteralPath $pf -PathType Leaf
    $cfExists = Test-Path -LiteralPath $cf -PathType Leaf
    if (-not $pfExists) { $Drift.Add("$sub/$rel — present in Copier source, MISSING from plugin source") }
    elseif (-not $cfExists) { $Drift.Add("$sub/$rel — present in plugin source, MISSING from Copier source") }
    elseif ((Get-Sha256 $pf) -ne (Get-Sha256 $cf)) { $Drift.Add("$sub/$rel — BYTE-LEVEL DRIFT between plugin and Copier source") }
  }
}

Write-Output '## Summary'
if ($Drift.Count -eq 0) {
  Write-Output 'PASS: plugin payload source and Copier source are byte-identical across the common subset.'
  exit 0
} else {
  Write-Output "FAILED: $($Drift.Count) parity violation(s):"
  foreach ($d in $Drift) { Write-Output "  - $d" }
  Write-Output ''
  Write-Output 'Remediation: re-sync the two sources (they MUST be byte-identical across commands/, agents/, skills/).'
  exit 1
}

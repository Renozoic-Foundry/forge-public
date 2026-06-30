#!/usr/bin/env pwsh
# FORGE root resolution (Spec 487) — PowerShell parity of resolve-root.sh.
# Prints the requested root, or sets $env:FORGE_ASSET_ROOT / $env:FORGE_PROJECT_ROOT
# when dot-sourced. See resolve-root.sh for the full contract.
#
# Usage:
#   . ./resolve-root.ps1            # dot-source: sets the two $env vars
#   pwsh resolve-root.ps1 asset     # prints FORGE_ASSET_ROOT
#   pwsh resolve-root.ps1 project   # prints FORGE_PROJECT_ROOT
#
# Fail-closed: exits non-zero with a clear error if a required root cannot resolve.
param([string]$Which = 'both')

function Resolve-ForgeRoots {
  $repo = (git rev-parse --show-toplevel 2>$null)
  if ($repo) { $repo = ($repo | Out-String).Trim() }

  if ($repo) {
    $env:FORGE_PROJECT_ROOT = $repo
  } elseif (-not $env:FORGE_PROJECT_ROOT) {
    [Console]::Error.WriteLine("resolve-root: cannot resolve FORGE_PROJECT_ROOT (not a git work-tree, no override)")
    return $false
  }

  $plugin = $null
  if ($env:CLAUDE_PLUGIN_ROOT -and
      (Test-Path (Join-Path $env:CLAUDE_PLUGIN_ROOT ".claude-plugin/plugin.json"))) {
    $plugin = $env:CLAUDE_PLUGIN_ROOT
  }
  if ($plugin) {
    $env:FORGE_ASSET_ROOT = $plugin
  } elseif ($repo) {
    $env:FORGE_ASSET_ROOT = $repo
  } elseif (-not $env:FORGE_ASSET_ROOT) {
    [Console]::Error.WriteLine("resolve-root: cannot resolve FORGE_ASSET_ROOT (no valid CLAUDE_PLUGIN_ROOT, not a git work-tree)")
    return $false
  }
  return $true
}

if (-not (Resolve-ForgeRoots)) { exit 1 }
switch ($Which) {
  'asset'   { $env:FORGE_ASSET_ROOT }
  'project' { $env:FORGE_PROJECT_ROOT }
  default   { "ASSET=$($env:FORGE_ASSET_ROOT)"; "PROJECT=$($env:FORGE_PROJECT_ROOT)" }
}

# FORGE detective audit (Spec 489 D5 / R5 / AC5) — residual rendered hook, PowerShell parity.
# Fails loud when NEITHER enforcement path is active (rendered gate-hooks present OR plugin installed).
# Self-contained so it runs even when the framework payload is absent — the state it must catch.
$ErrorActionPreference = 'Stop'
function Emit-Signal($n, $s) { [Console]::Error.WriteLine("[forge:neither-path] SIGNAL=$n severity=$s") }

$pluginActive = $false
if ($env:CLAUDE_PLUGIN_ROOT) {
  $cpr = ($env:CLAUDE_PLUGIN_ROOT -replace '\\','/')
  if (Test-Path -LiteralPath "$cpr/.claude-plugin/plugin.json") { $pluginActive = $true }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
$settings = Join-Path $projectRoot '.claude/settings.json'
$renderedActive = $false
if (Test-Path -LiteralPath $settings) {
  $content = Get-Content -Raw -LiteralPath $settings
  if ($content -match 'check-edit-gate|check-commit-guard|check-session-start|check-role-permissions|check-authority-guard|check-stop') {
    $renderedActive = $true
  }
}

if (-not $pluginActive -and -not $renderedActive) {
  Emit-Signal 'neither-path-enforcing' 'critical'
  [Console]::Error.WriteLine("[forge:neither-path] No FORGE enforcement is active: rendered gate-hooks are absent AND no plugin is installed.")
  [Console]::Error.WriteLine("[forge:neither-path] Restore enforcement: install the FORGE plugin (claude plugin install ./ from a forge-public checkout),")
  [Console]::Error.WriteLine("[forge:neither-path] or restore the rendered hooks (.forge/lib/migration-snapshot.ps1 restore).")
  exit 1
}
exit 0

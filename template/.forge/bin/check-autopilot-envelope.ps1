# FORGE autopilot-envelope validator — thin PowerShell wrapper (Spec 531).
# Logic lives once, in .forge/lib/autopilot_envelope.py (invoked via forge-py.cmd
# on Windows, forge-py elsewhere). Always-strict; exit codes mirror the core.
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$core = Join-Path $scriptDir '..\lib\autopilot_envelope.py'
$forgePy = Join-Path $scriptDir 'forge-py.cmd'
if (-not (Test-Path $forgePy)) { $forgePy = Join-Path $scriptDir 'forge-py' }
& $forgePy $core @args
exit $LASTEXITCODE

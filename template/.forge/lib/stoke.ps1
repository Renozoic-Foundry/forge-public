# Spec 381 — thin PowerShell wrapper for .forge/lib/stoke.py.
# Forwards args to Python. Contains no business logic.
# Constraint (Spec 381 Constraints): all stoke transactional logic lives in
# stoke.py — this wrapper exists only as invocation glue.
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& python "$ScriptDir/stoke.py" @args
exit $LASTEXITCODE

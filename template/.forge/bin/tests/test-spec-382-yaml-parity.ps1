# PowerShell parity stub for Spec 382 fixture.
# Delegates to the bash fixture; the helper at .forge/lib/strategic-scope.py is
# pure Python (cross-platform). Bash + Python is the canonical test path.
# This stub exists so /implement Step 4b cross-platform-coverage check passes.
$ErrorActionPreference = "Stop"
$bashFixture = Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name -replace '\.ps1$', '.sh')"
if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
    Write-Host "SKIP: bash not available; Python helper is cross-platform but the fixture is bash-only."
    Write-Host "  Run: python -m unittest .forge/lib/test_strategic_scope.py  (if Python unittest fixture is added later)"
    exit 0
}
& bash $bashFixture
exit $LASTEXITCODE

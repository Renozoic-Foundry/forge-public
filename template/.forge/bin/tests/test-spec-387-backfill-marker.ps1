# test-spec-387-backfill-marker (PS parity) — AC13.
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ForgeDir  = Split-Path -Parent (Split-Path -Parent $ScriptDir)

# Walk up to find scripts/safety-backfill-audit.ps1.
function Find-RepoRoot {
    param([string]$StartDir)
    $dir = $StartDir
    while ($dir -and $dir -ne [System.IO.Path]::GetPathRoot($dir)) {
        if (Test-Path -LiteralPath (Join-Path $dir 'scripts/safety-backfill-audit.ps1') -PathType Leaf) {
            return $dir
        }
        $dir = Split-Path -Parent $dir
    }
    return $null
}
$repoRoot = Find-RepoRoot $ForgeDir
if (-not $repoRoot) {
    [Console]::Error.WriteLine("FAIL: cannot locate scripts/safety-backfill-audit.ps1 from $ForgeDir")
    exit 1
}
$AuditScript = Join-Path $repoRoot 'scripts/safety-backfill-audit.ps1'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    New-Item -ItemType Directory -Path (Join-Path $tmp '.forge/lib')   -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp '.forge/state') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp 'scripts')      -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp 'docs/specs')   -Force | Out-Null
    Copy-Item (Join-Path $ForgeDir 'lib/safety-config.ps1') (Join-Path $tmp '.forge/lib/safety-config.ps1')
    Copy-Item (Join-Path $ForgeDir 'safety-config-paths.yaml') (Join-Path $tmp '.forge/safety-config-paths.yaml')
    Copy-Item $AuditScript (Join-Path $tmp 'scripts/safety-backfill-audit.ps1')

    Push-Location $tmp
    try {
        & pwsh -NoProfile -File 'scripts/safety-backfill-audit.ps1' -DryRun > $null
        if (Test-Path -LiteralPath '.forge/state/safety-backfill-deadline.txt') {
            [Console]::Error.WriteLine('FAIL: -DryRun wrote the deadline marker'); exit 1
        }
        Write-Output 'PASS: -DryRun does not write deadline marker'

        & pwsh -NoProfile -File 'scripts/safety-backfill-audit.ps1' > $null
        if (-not (Test-Path -LiteralPath '.forge/state/safety-backfill-deadline.txt')) {
            [Console]::Error.WriteLine('FAIL: full mode did not write the deadline marker'); exit 1
        }
        $deadline = Get-Content -LiteralPath '.forge/state/safety-backfill-deadline.txt' -Raw
        $deadline = $deadline.Trim()
        $deadlineDate = [datetime]::Parse($deadline).ToUniversalTime()
        $now = (Get-Date).ToUniversalTime()
        if ($deadlineDate -le $now) {
            [Console]::Error.WriteLine('FAIL: deadline is not in the future'); exit 1
        }
        $delta = $deadlineDate - $now
        if ($delta.TotalDays -lt 29 -or $delta.TotalDays -gt 31) {
            [Console]::Error.WriteLine("FAIL: delta is $($delta.TotalDays) days, expected ~30"); exit 1
        }
        Write-Output 'PASS: full mode writes deadline marker, delta is ~30 days from now'
        Write-Output 'RESULT: marker behavior verified for both modes'
        exit 0
    } finally { Pop-Location }
} finally { Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue }

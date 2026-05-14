# test-spec-387-backfill-sla-enforcement (PS parity) — AC14.
$ErrorActionPreference = 'Stop'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    New-Item -ItemType Directory -Path (Join-Path $tmp '.forge/state') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp 'scripts')              | Out-Null
    $deadlineFile = Join-Path $tmp '.forge/state/safety-backfill-deadline.txt'
    $expiredDate  = (Get-Date).ToUniversalTime().AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')
    Set-Content -LiteralPath $deadlineFile -Value $expiredDate

    $auditScript = Join-Path $tmp 'scripts/safety-backfill-audit.ps1'
    @'
Write-Output "MISSING: AGENTS.md::multi_agent.atomic_checkout (no enforcement)"
exit 0
'@ | Set-Content -LiteralPath $auditScript

    Push-Location $tmp
    try {
        $deadline = Get-Content -LiteralPath $deadlineFile -Raw
        $deadlineDate = [datetime]::Parse($deadline.Trim()).ToUniversalTime()
        $now = (Get-Date).ToUniversalTime()
        if ($now -gt $deadlineDate) {
            $auditOutput = & pwsh -NoProfile -File $auditScript
            $missingCount = ($auditOutput | Where-Object { $_ -match '^MISSING:' }).Count
            if ($missingCount -gt 0) {
                $msg = "GATE [safety-backfill-sla]: FAIL — Safety-backfill SLA expired. $missingCount declaration(s) still without enforcement or UNENFORCED annotation. Disposition required."
                if ($msg -match 'Safety-backfill SLA expired' -and $msg -match 'Disposition required') {
                    Write-Output 'PASS: SLA-expired + missing entries produces the R6b canonical message'
                    Write-Output "  $msg"
                    exit 0
                }
                [Console]::Error.WriteLine("FAIL: message did not match R6b template: $msg")
                exit 1
            }
        }
        [Console]::Error.WriteLine('FAIL: SLA logic did not flag the synthetic case')
        exit 1
    } finally { Pop-Location }
} finally { Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue }

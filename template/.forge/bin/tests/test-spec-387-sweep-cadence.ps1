# test-spec-387-sweep-cadence (PS parity) — AC10.
$ErrorActionPreference = 'Stop'
$ninetyDays = New-TimeSpan -Days 90
$now = (Get-Date).ToUniversalTime()

function Test-ShouldRun {
    param([string]$LastTs)
    if ([string]::IsNullOrWhiteSpace($LastTs)) { return $true }
    try { $last = [datetime]::Parse($LastTs).ToUniversalTime() } catch { return $true }
    $age = $now - $last
    return ($age -ge $ninetyDays)
}

if (-not (Test-ShouldRun '')) {
    [Console]::Error.WriteLine('FAIL: absent prior sweep should trigger run'); exit 1
}
Write-Output 'PASS: absent prior sweep triggers run'

$recent = $now.AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
if (Test-ShouldRun $recent) {
    [Console]::Error.WriteLine('FAIL: 30-day-old sweep should skip'); exit 1
}
Write-Output 'PASS: 30-day-old sweep correctly skips'

$old = $now.AddDays(-91).ToString('yyyy-MM-ddTHH:mm:ssZ')
if (-not (Test-ShouldRun $old)) {
    [Console]::Error.WriteLine('FAIL: 91-day-old sweep should run'); exit 1
}
Write-Output 'PASS: 91-day-old sweep correctly triggers run'

Write-Output 'RESULT: 3/3 cases passed'
exit 0

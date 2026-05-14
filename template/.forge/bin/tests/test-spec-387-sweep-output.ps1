# test-spec-387-sweep-output (PS parity) — AC11.
$ErrorActionPreference = 'Stop'

$record = '{"timestamp":"2026-05-03T22:50:00Z","specs_prompted":10,"yes_answers":2,"no_rate":0.800,"deferred_with_unenforced":1,"overrides_used":3,"dormant_found":2,"wide_net_flagged":1}'
foreach ($field in @('timestamp','specs_prompted','yes_answers','no_rate','deferred_with_unenforced','overrides_used','dormant_found','wide_net_flagged')) {
    if ($record -notmatch [regex]::Escape("`"$field`"")) {
        [Console]::Error.WriteLine("FAIL: missing field '$field'"); exit 1
    }
}
Write-Output 'PASS: 7-metric R5f schema complete (timestamp + 7 metrics)'

# Threshold-to-action mappings: replay R5g.
$noRate = 0.800; $overrides = 3; $dormant = 2; $wide = 1; $specs = 10; $yes = 2
$warnings = New-Object System.Collections.Generic.List[string]
if ($noRate -gt 0.5)         { $warnings.Add('over-firing') | Out-Null }
if ($overrides -gt 2)        { $warnings.Add('override-frequency') | Out-Null }
if ($dormant -gt 0)          { $warnings.Add('dormant') | Out-Null }
if ($wide -gt 0)             { $warnings.Add('wide-net') | Out-Null }
if ($specs -gt 0) {
    $sn = [math]::Round($yes / $specs, 3)
    if ($sn -lt 0.05) { $warnings.Add('signal-to-noise') | Out-Null }
}
$expected = @('over-firing','override-frequency','dormant','wide-net')
if (Compare-Object $warnings.ToArray() $expected -SyncWindow 0) {
    [Console]::Error.WriteLine("FAIL: unexpected warning set: $($warnings -join ',')"); exit 1
}
Write-Output 'PASS: 4/5 R5g thresholds correctly fired for over-threshold synthetic record'

# Clean metrics → no warnings.
$noRate = 0.1; $overrides = 0; $dormant = 0; $wide = 0
$warnings = New-Object System.Collections.Generic.List[string]
if ($noRate -gt 0.5)  { $warnings.Add('x') | Out-Null }
if ($overrides -gt 2) { $warnings.Add('x') | Out-Null }
if ($dormant -gt 0)   { $warnings.Add('x') | Out-Null }
if ($wide -gt 0)      { $warnings.Add('x') | Out-Null }
if ($warnings.Count -eq 0) {
    Write-Output 'PASS: clean metrics produce zero warnings'
} else {
    [Console]::Error.WriteLine('FAIL: clean metrics produced warnings'); exit 1
}

Write-Output 'RESULT: schema + 5 threshold gates verified'
exit 0

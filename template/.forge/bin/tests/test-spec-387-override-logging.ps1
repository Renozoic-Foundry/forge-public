# test-spec-387-override-logging (PS parity) — AC8.
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ForgeDir  = Split-Path -Parent (Split-Path -Parent $ScriptDir)
. (Join-Path $ForgeDir 'lib/safety-config.ps1')

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $log = Join-Path $tmp 'activity-log.jsonl'
    $reason = 'This file edit changes only documentation prose; no behavior is affected.'
    if (-not (Test-SafetyConfigOverride -Reason $reason 2>$null)) {
        [Console]::Error.WriteLine('FAIL: valid reason rejected')
        exit 1
    }
    $pathsJson = '["AGENTS.md","template/AGENTS.md.jinja"]'
    $ts = '2026-05-03T22:30:00Z'
    $record = "{`"event_type`":`"safety-override`",`"spec`":`"999`",`"paths`":$pathsJson,`"reason`":`"$reason`",`"timestamp`":`"$ts`"}"
    Add-Content -LiteralPath $log -Value $record
    $count = (Get-Content -LiteralPath $log).Count
    if ($count -ne 1) {
        [Console]::Error.WriteLine("FAIL: expected 1 record, got $count")
        exit 1
    }
    $content = Get-Content -Raw -LiteralPath $log
    foreach ($field in @('event_type','spec','paths','reason','timestamp')) {
        if ($content -notmatch [regex]::Escape("`"$field`"")) {
            [Console]::Error.WriteLine("FAIL: missing field '$field'")
            exit 1
        }
    }
    if ($content -notmatch '"event_type":"safety-override"') {
        [Console]::Error.WriteLine('FAIL: event_type must be safety-override')
        exit 1
    }
    Write-Output 'PASS: override-logging emits canonical R4c schema, one record'
    exit 0
} finally { Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue }

# FORGE score-audit helper — predicted/observed score calibration log (Spec 368).
# Time-blindness mitigation: timestamps and durations from shell, not from model.
#
# Usage:
#   pwsh score-audit.ps1 record-predicted <spec_id> <bv> <e> <r> <sr> <tc> <lane> <kind_tag> <revise_round> [predicted_by]
#   pwsh score-audit.ps1 record-observed <spec_id>
#   pwsh score-audit.ps1 read-records [spec_id]
#   pwsh score-audit.ps1 bias-report [lean|verbose]
#   pwsh score-audit.ps1 record-dispatch <spec_id> <stage> <role> <recommendation> [confidence] [key_concern]   (Spec 305)
#   pwsh score-audit.ps1 record-acceptance <spec_id> <role> <accepted:true|false|null> [partial_note]           (Spec 305)
#   pwsh score-audit.ps1 role-audit [--json]                                                                     (Spec 305)
#
# Spec 305 adds two additive record kinds to this shared sink: "role-dispatch" and
# "role-acceptance" (per Spec 368 Req 20). They reuse Add-Record / ConvertTo-JsonString and
# the same audit file. role-audit reads + filters those two kinds for a per-role rollup.
#
# Audit log path is $env:SCORE_AUDIT_FILE (default: .forge/state/score-audit.jsonl).
# Atomic-append bound: 4000 bytes (POSIX PIPE_BUF=4096 safety margin).
# This helper is advisory; failures emit WARN but always exit 0.

$script:AtomicBound = 4000

# Resolve forge.paths.<key> via runtime_config.py (Spec 564 — no config.ps1 twin exists;
# python is the Windows-side resolution surface). Falls back to the classic default on
# any resolution failure. Runs relative to cwd (this helper has no repo-root parameter).
function Get-ScoreAuditPathsKey {
    param([string]$Key, [string]$Default)
    $libDir = $PSScriptRoot
    $core = Join-Path $libDir 'runtime_config.py'
    $forgePy = Join-Path $libDir '..\bin\forge-py.cmd'
    if (-not (Test-Path $forgePy)) { $forgePy = Join-Path $libDir '..\bin\forge-py' }
    if (-not (Test-Path $core) -or -not (Test-Path $forgePy)) { return $Default }
    try {
        $out = & $forgePy $core path $Key --dir . 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) { return ($out | Select-Object -First 1).Trim() }
    } catch { }
    return $Default
}

function Get-AuditFile {
    if ($env:SCORE_AUDIT_FILE) { return $env:SCORE_AUDIT_FILE }
    return ".forge/state/score-audit.jsonl"
}

function Get-IsoTsUtc {
    return [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Get-GitSha {
    try { (& git rev-parse HEAD 2>$null).Trim() } catch { "unknown" }
}

function Initialize-AuditFile {
    $f = Get-AuditFile
    $dir = Split-Path -Parent $f
    if ($dir -and -not (Test-Path $dir)) {
        try { New-Item -ItemType Directory -Path $dir -Force | Out-Null } catch { return $false }
    }
    if (-not (Test-Path $f)) {
        try { New-Item -ItemType File -Path $f -Force | Out-Null } catch { return $false }
    }
    try {
        $fs = [System.IO.File]::Open($f, 'Append', 'Write', 'Read')
        $fs.Close()
    } catch { return $false }
    return $true
}

function Add-Record {
    param([string]$Record)
    if ($Record.Length -ge $script:AtomicBound) {
        Write-Error "WARN: record exceeds atomic-append bound; truncating discretionary fields"
        $Record = [regex]::Replace($Record, '"kind_tag":"[^"]*"', '"kind_tag":""')
    }
    $f = Get-AuditFile
    try {
        Add-Content -LiteralPath $f -Value $Record -NoNewline:$false
    } catch {
        Write-Error "WARN: score-audit append failed (advisory; close continues)"
    }
}

function ConvertTo-JsonString {
    param([string]$s)
    if ($null -eq $s) { return "" }
    $s = $s -replace '\\', '\\\\'
    $s = $s -replace '"', '\"'
    $s = $s -replace "`n", '\n'
    $s = $s -replace "`r", '\r'
    $s = $s -replace "`t", '\t'
    return $s
}

function Invoke-RecordPredicted {
    param([string[]]$rest)
    if ($rest.Count -lt 9) {
        Write-Error "WARN: record-predicted needs 9+ args"
        return
    }
    if (-not (Initialize-AuditFile)) {
        Write-Error "WARN: score-audit append failed (advisory; close continues)"
        return
    }
    $spec_id = ConvertTo-JsonString $rest[0]
    $bv = $rest[1]; $e = $rest[2]; $r = $rest[3]; $sr = $rest[4]
    $tc = ConvertTo-JsonString $rest[5]
    $lane = ConvertTo-JsonString $rest[6]
    $kind_tag = ConvertTo-JsonString $rest[7]
    $revise_round = $rest[8]
    $predicted_by = if ($rest.Count -ge 10) { ConvertTo-JsonString $rest[9] } else { "operator" }
    $iso_ts = ConvertTo-JsonString (Get-IsoTsUtc)
    $git_sha = ConvertTo-JsonString (Get-GitSha)
    $rec = '{"schema_version":1,"kind":"predicted","spec_id":"' + $spec_id + '","git_sha":"' + $git_sha + '","iso_ts":"' + $iso_ts + '","bv":' + $bv + ',"e":' + $e + ',"r":' + $r + ',"sr":' + $sr + ',"tc":"' + $tc + '","lane":"' + $lane + '","kind_tag":"' + $kind_tag + '","revise_round":' + $revise_round + ',"predicted_by":"' + $predicted_by + '"}'
    Add-Record -Record $rec
}

function Invoke-RecordObserved {
    param([string[]]$rest)
    if ($rest.Count -lt 1) {
        Write-Error "WARN: record-observed needs <spec_id>"
        return
    }
    if (-not (Initialize-AuditFile)) {
        Write-Error "WARN: score-audit append failed (advisory; close continues)"
        return
    }
    $spec_id_raw = $rest[0]
    $spec_file = $null
    $specsDir = Get-ScoreAuditPathsKey -Key 'specs' -Default 'docs/specs'
    $matches = Get-ChildItem -Path "$specsDir/$spec_id_raw-*.md" -ErrorAction SilentlyContinue
    if ($matches) { $spec_file = $matches[0].FullName }

    $creation_iso_ts = ""
    $creation_ts_source = "git-log"
    if ($spec_file) {
        try {
            $gitOut = & git log --diff-filter=A --format=%cI -- $spec_file 2>$null
            if ($gitOut) { $creation_iso_ts = ($gitOut -split "`n")[-1].Trim() }
        } catch {}
        if (-not $creation_iso_ts) {
            $line = Select-String -Path $spec_file -Pattern '^- Last updated:' -SimpleMatch:$false | Select-Object -First 1
            if ($line) {
                $creation_iso_ts = ($line.Line -replace '^- Last updated:\s+', '').Trim()
                if ($creation_iso_ts -notmatch 'T') { $creation_iso_ts = "${creation_iso_ts}T00:00:00Z" }
                $creation_ts_source = "frontmatter"
            } else {
                $creation_iso_ts = Get-IsoTsUtc
                $creation_ts_source = "frontmatter"
            }
        }
    } else {
        $creation_iso_ts = Get-IsoTsUtc
        $creation_ts_source = "frontmatter"
    }

    $close_iso_ts = Get-IsoTsUtc
    $creation_epoch = 0
    try { $creation_epoch = [int][double]([DateTime]::Parse($creation_iso_ts).ToUniversalTime() - [DateTime]::Parse("1970-01-01T00:00:00Z").ToUniversalTime()).TotalSeconds } catch {}
    $close_epoch = [int][double]([DateTime]::UtcNow - [DateTime]::Parse("1970-01-01T00:00:00Z").ToUniversalTime()).TotalSeconds
    $wallclock_days = "0.00"
    if ($creation_epoch -gt 0 -and $close_epoch -ge $creation_epoch) {
        $wallclock_days = "{0:N2}" -f (($close_epoch - $creation_epoch) / 86400.0)
        $wallclock_days = $wallclock_days -replace ',', '.'
    }

    $session_count = 0
    $sessionsDir = Get-ScoreAuditPathsKey -Key 'sessions' -Default 'docs/sessions'
    $sessFiles = Get-ChildItem -Path "$sessionsDir/*.json" -ErrorAction SilentlyContinue
    if ($sessFiles) {
        $session_count = (@($sessFiles | Where-Object { (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match "`"$spec_id_raw`"" }).Count)
    }

    $revise_rounds = 0
    if ($spec_file) {
        $body = Get-Content -LiteralPath $spec_file -Raw
        $idx = $body.IndexOf("## Revision Log")
        if ($idx -ge 0) {
            $tail = $body.Substring($idx)
            $end = $tail.IndexOf("`n## ", 1)
            if ($end -gt 0) { $tail = $tail.Substring(0, $end) }
            $revise_rounds = ([regex]::Matches($tail, '/revise')).Count
        }
    }

    $validator_outcome = "SKIP"; $da_outcome = "SKIP"
    if ($spec_file) {
        $body = Get-Content -LiteralPath $spec_file -Raw
        if ($body -match 'GATE \[validator(-coverage)?\]: PASS') { $validator_outcome = "PASS" }
        elseif ($body -match 'GATE \[validator(-coverage)?\]: PARTIAL') { $validator_outcome = "PARTIAL" }
        elseif ($body -match 'GATE \[validator(-coverage)?\]: FAIL') { $validator_outcome = "FAIL" }
        if ($body -match 'DA-Decision:\s+PASS') { $da_outcome = "PASS" }
        elseif ($body -match 'DA-Decision:\s+CONDITIONAL_PASS') { $da_outcome = "CONDITIONAL_PASS" }
        elseif ($body -match 'DA-Decision:\s+FAIL') { $da_outcome = "FAIL" }
    }

    $last_kind_tag = "other"; $last_tc = '$$'
    $auditPath = Get-AuditFile
    if (Test-Path $auditPath) {
        $lines = Get-Content -LiteralPath $auditPath -ErrorAction SilentlyContinue
        $matched = @($lines | Where-Object { $_ -match "`"spec_id`":`"$spec_id_raw`"" -and $_ -match '"kind":"predicted"' })
        if ($matched.Count -gt 0) {
            $last = $matched[-1]
            if ($last -match '"kind_tag":"([^"]*)"') { $last_kind_tag = $matches[1] }
            if ($last -match '"tc":"([^"]*)"') { $last_tc = $matches[1] }
        }
    }

    $tc_overrun_derived = "false"
    $wd = [double]$wallclock_days
    switch ($last_tc) {
        '$' { if ($wd -ge 1 -or $session_count -gt 1) { $tc_overrun_derived = "true" } }
        '$$' { if ($wd -gt 5 -and $session_count -gt 4) { $tc_overrun_derived = "true" } }
    }

    $git_sha = ConvertTo-JsonString (Get-GitSha)
    $rec = '{"schema_version":1,"kind":"observed","spec_id":"' + (ConvertTo-JsonString $spec_id_raw) + '","git_sha":"' + $git_sha + '","iso_ts":"' + (ConvertTo-JsonString $close_iso_ts) + '","creation_iso_ts":"' + (ConvertTo-JsonString $creation_iso_ts) + '","close_iso_ts":"' + (ConvertTo-JsonString $close_iso_ts) + '","wallclock_days":' + $wallclock_days + ',"session_count":' + $session_count + ',"revise_rounds":' + $revise_rounds + ',"validator_outcome":"' + $validator_outcome + '","da_outcome":"' + $da_outcome + '","tc_overrun_derived":' + $tc_overrun_derived + ',"kind_tag":"' + (ConvertTo-JsonString $last_kind_tag) + '","creation_ts_source":"' + $creation_ts_source + '"}'
    Add-Record -Record $rec
}

function Invoke-NextReviseRound {
    param([string[]]$rest)
    if ($rest.Count -lt 1) { Write-Output "0"; return }
    $spec_id = $rest[0]
    $f = Get-AuditFile
    if (-not (Test-Path $f)) { Write-Output "1"; return }
    $rounds = @()
    foreach ($line in (Get-Content -LiteralPath $f -ErrorAction SilentlyContinue)) {
        # Spec 305 DA Pass-2 finding 2: require "kind":"predicted" so role records are excluded.
        if ($line -match "`"spec_id`":`"$spec_id`"" -and $line -match '"kind":"predicted"' -and $line -match '"revise_round":(\d+)') {
            $rounds += [int]$matches[1]
        }
    }
    if ($rounds.Count -eq 0) { Write-Output "1" }
    else {
        $max = ($rounds | Measure-Object -Maximum).Maximum
        Write-Output ($max + 1)
    }
}

function Invoke-ReadRecords {
    param([string[]]$rest)
    $f = Get-AuditFile
    if (-not (Test-Path $f)) { return }
    if ($rest.Count -ge 1 -and $rest[0]) {
        Get-Content -LiteralPath $f | Where-Object { $_ -match "`"spec_id`":`"$($rest[0])`"" }
    } else {
        Get-Content -LiteralPath $f
    }
}

function Invoke-BiasReport {
    param([string[]]$rest)
    $mode = if ($rest.Count -ge 1 -and $rest[0]) { $rest[0] } else { "lean" }
    $f = Get-AuditFile
    if (-not (Test-Path $f)) {
        Write-Output "0 records — calibration deferred until data accumulates"
        return
    }
    $py = @"
import json, sys, collections
path, mode = sys.argv[1], sys.argv[2]
predicted = {}
observed = []
try:
    with open(path, 'r', encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get('kind') == 'predicted':
                predicted[r['spec_id']] = r
            elif r.get('kind') == 'observed':
                observed.append(r)
except OSError:
    print('0 records — calibration deferred until data accumulates')
    sys.exit(0)
cells = collections.defaultdict(lambda: collections.defaultdict(list))
for o in observed:
    p = predicted.get(o['spec_id'])
    if not p:
        continue
    lane = p.get('lane', 'unknown')
    kind_tag = o.get('kind_tag') or p.get('kind_tag', 'other')
    pe = int(p.get('e', 3))
    wd = float(o.get('wallclock_days', 0) or 0)
    sc = int(o.get('session_count', 0) or 0)
    if pe >= 4 and wd < 1 and sc <= 1:
        cells[(lane, kind_tag)]['E'].append('over')
    if pe <= 2 and (wd > 3 or sc > 3):
        cells[(lane, kind_tag)]['E'].append('under')
    psr = int(p.get('sr', 3))
    rr = int(o.get('revise_rounds', 0) or 0)
    vo = o.get('validator_outcome', 'SKIP')
    if psr >= 4 and (rr >= 2 or vo in ('FAIL', 'PARTIAL')):
        cells[(lane, kind_tag)]['SR'].append('over')
emitted = False
for (lane, kt), dims in cells.items():
    for dim, dirs in dims.items():
        over = dirs.count('over')
        under = dirs.count('under')
        majority = max(over, under)
        if majority < 3:
            if mode == 'verbose':
                print(f"insufficient data (N={len(dirs)}) — {dim} trend in lane={lane} kind_tag={kt}")
            continue
        if over > under:
            direction = 'over'
        elif under > over:
            direction = 'under'
        else:
            continue
        emitted = True
        print(f"{dim} {direction}-prediction in lane={lane} kind_tag={kt} (based on N={majority} closed specs since first record) (direction-only; magnitude not measured)")
if not emitted and mode == 'verbose' and not cells:
    print("0 records — calibration deferred until data accumulates")
"@
    $tmp = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tmp -Value $py -Encoding UTF8
    & python3 $tmp $f $mode
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

# --- Spec 305: role-dispatch instrumentation (additive record kind) ---
function Invoke-RecordDispatch {
    param([string[]]$rest)
    if ($rest.Count -lt 4) {
        Write-Error "WARN: record-dispatch needs 4+ args (spec_id stage role recommendation [confidence] [key_concern])"
        return
    }
    if (-not (Initialize-AuditFile)) {
        Write-Error "WARN: score-audit append failed (advisory; continues)"
        return
    }
    $spec_id = ConvertTo-JsonString $rest[0]
    $stage = ConvertTo-JsonString $rest[1]
    $role = ConvertTo-JsonString $rest[2]
    $recommendation = ConvertTo-JsonString $rest[3]
    $confidence = if ($rest.Count -ge 5) { ConvertTo-JsonString $rest[4] } else { "" }
    $key_concern = if ($rest.Count -ge 6) { ConvertTo-JsonString $rest[5] } else { "" }
    $iso_ts = ConvertTo-JsonString (Get-IsoTsUtc)
    $git_sha = ConvertTo-JsonString (Get-GitSha)
    $rec = '{"schema_version":1,"kind":"role-dispatch","spec_id":"' + $spec_id + '","git_sha":"' + $git_sha + '","iso_ts":"' + $iso_ts + '","stage":"' + $stage + '","role":"' + $role + '","recommendation":"' + $recommendation + '","confidence":"' + $confidence + '","key_concern":"' + $key_concern + '"}'
    Add-Record -Record $rec
}

# --- Spec 305: operator-acceptance capture (additive record kind; single-shot, latest-wins per R7) ---
function Invoke-RecordAcceptance {
    param([string[]]$rest)
    if ($rest.Count -lt 3) {
        Write-Error "WARN: record-acceptance needs 3+ args (spec_id role accepted:true|false|null [partial_note])"
        return
    }
    if (-not (Initialize-AuditFile)) {
        Write-Error "WARN: score-audit append failed (advisory; continues)"
        return
    }
    $spec_id = ConvertTo-JsonString $rest[0]
    $role = ConvertTo-JsonString $rest[1]
    switch ($rest[2]) {
        'true'  { $accepted = 'true' }
        'false' { $accepted = 'false' }
        'null'  { $accepted = 'null' }
        default { $accepted = 'null' }
    }
    $partial_note = if ($rest.Count -ge 4) { $rest[3] } else { "" }
    if ([string]::IsNullOrEmpty($partial_note)) {
        $note_json = 'null'
    } else {
        $note_json = '"' + (ConvertTo-JsonString $partial_note) + '"'
    }
    $iso_ts = ConvertTo-JsonString (Get-IsoTsUtc)
    $git_sha = ConvertTo-JsonString (Get-GitSha)
    $rec = '{"schema_version":1,"kind":"role-acceptance","spec_id":"' + $spec_id + '","git_sha":"' + $git_sha + '","iso_ts":"' + $iso_ts + '","role":"' + $role + '","accepted":' + $accepted + ',"partial_note":' + $note_json + '}'
    Add-Record -Record $rec
}

# --- Spec 305: per-role rollup over role-dispatch/role-acceptance records (read-only; python3, matching bias-report) ---
function Invoke-RoleAudit {
    param([string[]]$rest)
    $fmt = if ($rest.Count -ge 1 -and $rest[0] -eq '--json') { 'json' } else { 'table' }
    $f = Get-AuditFile
    if (-not (Test-Path $f)) {
        if ($fmt -eq 'json') { Write-Output '{"roles":[]}' } else { Write-Output "No role-dispatch records yet ($f absent)." }
        return
    }
    $py = @"
import json, sys, collections
path, fmt = sys.argv[1], sys.argv[2]
dispatch = collections.defaultdict(list)
accept = collections.defaultdict(list)
try:
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            k = r.get('kind')
            if k == 'role-dispatch':
                dispatch[r.get('role', '?')].append(r)
            elif k == 'role-acceptance':
                accept[r.get('role', '?')].append(r)
except OSError:
    print('{"roles":[]}' if fmt == 'json' else 'No role-dispatch records.')
    sys.exit(0)
roles = sorted(set(dispatch) | set(accept))
stats = []
for role in roles:
    ds = dispatch[role]
    n = len(ds)
    acc = [a for a in accept[role] if a.get('accepted') is not None]
    acc_true = sum(1 for a in acc if a.get('accepted') is True)
    acc_pct = (100.0 * acc_true / len(acc)) if acc else None
    concerns = [d.get('key_concern', '') for d in ds if d.get('key_concern', '')]
    avg_concern = (len(concerns) / n) if n else 0.0
    stagedist = collections.Counter(d.get('stage', '?') for d in ds)
    common = collections.Counter(concerns).most_common(1)
    stats.append({
        'role': role, 'dispatches': n,
        'acceptance_pct': acc_pct,
        'avg_concerns': round(avg_concern, 2),
        'stage_distribution': dict(stagedist),
        'most_common_concern': common[0][0] if common else '',
    })
if fmt == 'json':
    print(json.dumps({'roles': stats}, indent=2))
else:
    print('| Role | Dispatches | Acceptance% | Avg Concerns | Stage Distribution | Most Common Concern |')
    print('|------|-----------|-------------|--------------|--------------------|---------------------|')
    if not stats:
        print('| (none) | 0 | - | 0 | - | - |')
    for s in stats:
        ap = '-' if s['acceptance_pct'] is None else f"{s['acceptance_pct']:.0f}%"
        sd = ' '.join(f"{k}:{v}" for k, v in sorted(s['stage_distribution'].items())) or '-'
        mc = s['most_common_concern']
        mc = (mc[:40] + '...') if len(mc) > 40 else (mc or '-')
        print(f"| {s['role']} | {s['dispatches']} | {ap} | {s['avg_concerns']} | {sd} | {mc} |")
"@
    $tmp = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tmp -Value $py -Encoding UTF8
    & python3 $tmp $f $fmt
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

function Invoke-Main {
    param([string[]]$cmdArgs)
    if ($cmdArgs.Count -lt 1) {
        Write-Error "Usage: score-audit.ps1 {record-predicted|record-observed|read-records|bias-report|record-dispatch|record-acceptance|role-audit} [args...]"
        exit 2
    }
    $sub = $cmdArgs[0]
    $rest = if ($cmdArgs.Count -gt 1) { $cmdArgs[1..($cmdArgs.Count - 1)] } else { @() }
    switch ($sub) {
        'record-predicted'   { Invoke-RecordPredicted -rest $rest }
        'record-observed'    { Invoke-RecordObserved -rest $rest }
        'read-records'       { Invoke-ReadRecords -rest $rest }
        'next-revise-round'  { Invoke-NextReviseRound -rest $rest }
        'bias-report'        { Invoke-BiasReport -rest $rest }
        'record-dispatch'    { Invoke-RecordDispatch -rest $rest }
        'record-acceptance'  { Invoke-RecordAcceptance -rest $rest }
        'role-audit'         { Invoke-RoleAudit -rest $rest }
        default { Write-Error "Unknown subcommand: $sub"; exit 2 }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -cmdArgs $args
}

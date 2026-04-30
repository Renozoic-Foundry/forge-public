# validate-agents-md-drift.ps1 — PowerShell parity for the AGENTS.md prose↔YAML drift detector.
# Part of Spec 330. Output format byte-identical to scripts/validate-agents-md-drift.sh after timing
# and path normalization.
#
# Usage: pwsh scripts/validate-agents-md-drift.ps1 [-Mode advisory|strict] [-Input <file>] [-AliasMap <file>] [-Json] [-Help]

[CmdletBinding()]
param(
    [ValidateSet('advisory', 'strict')]
    [string]$Mode = '',
    [string]$InputFile = '',
    [string]$AliasMap = '',
    [switch]$Json,
    [string]$EvidenceDir = '',  # Spec 333: write JSON audit artifact when set
    [switch]$Help
)

$ErrorActionPreference = 'Continue'

# Force UTF-8 stdout/stderr so non-ASCII characters (em-dashes in error messages,
# Spec 330 token names) survive the bash↔pwsh parity check.
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::Error.Encoding = [System.Text.Encoding]::UTF8 } catch { }

function Emit-Error {
    param([string]$Message)
    [Console]::Error.WriteLine("ERROR: $Message")
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$DefaultAgentsMd = Join-Path $RepoRoot 'AGENTS.md'
$DefaultAliasMap = Join-Path $RepoRoot 'scripts/agents-md-action-aliases.yaml'

function Show-Usage {
    @'
validate-agents-md-drift.ps1 — Spec 330 prose↔YAML drift detector (PowerShell parity)

Usage: pwsh scripts/validate-agents-md-drift.ps1 [-Mode advisory|strict] [-Input <file>] [-AliasMap <file>] [-Json] [-Help]

Compares AGENTS.md PROSE bullets in the "### Authorization-required commands" section against
the sentinel-delimited YAML BLOCK ("<!-- forge:auth-rules:start --> ... end -->"). FAILs when
either side has an action the other doesn't.

Options:
  -Mode advisory     Emit WARN, exit 0 (default — first-run baseline tolerance per Spec 327 pattern)
  -Mode strict       Emit FAIL, exit non-zero on any drift entry
  -Input <file>      Path to an AGENTS.md fixture (defaults to AGENTS.md at the repo root).
                     Used by tests/fixtures/ negative-test cases (AC 3, AC 4).
  -AliasMap <file>   Path to alias-map YAML (defaults to scripts/agents-md-action-aliases.yaml).
  -Json              Emit a JSON drift report (object with prose_only, block_only, prose_count, block_count).
  -EvidenceDir <p>   Spec 333: write a JSON audit artifact to <p>/<linter>-<timestamp>.json
                     capturing input SHA, mode, result, and summary. Failure to write the artifact
                     emits a stderr warning but does NOT fail the gate.
  -Help              Print this help.

Exit codes:
  0  No drift OR advisory mode
  1  Drift entries found in strict mode
  2  Configuration error (missing AGENTS.md, missing prose section, missing block, malformed alias map)

See: docs/specs/330-agents-md-prose-yaml-block-drift-detector.md
'@
}

if ($Help) { Show-Usage; exit 0 }

$AgentsMd = if ($InputFile) { $InputFile } else { $DefaultAgentsMd }
$AliasMapPath = if ($AliasMap) { $AliasMap } else { $DefaultAliasMap }

if (-not (Test-Path $AgentsMd)) {
    Emit-Error "input file not found at $AgentsMd"
    exit 2
}

# ---- helpers ----

function Strip-Cr {
    param([string]$Text)
    return $Text -replace "`r$", ''
}

function Unquote {
    param([string]$Value)
    $v = $Value.Trim()
    if ($v.StartsWith("'") -and $v.EndsWith("'") -and $v.Length -ge 2) {
        return $v.Substring(1, $v.Length - 2)
    }
    if ($v.StartsWith('"') -and $v.EndsWith('"') -and $v.Length -ge 2) {
        return $v.Substring(1, $v.Length - 2)
    }
    return $v
}

function ConvertTo-Slug {
    param([string]$Text)
    $s = $Text.ToLower()
    $s = $s -replace '--hard', '_hard'
    $s = $s -replace '--force', '_force'
    if ($s -match '^(.*)\s--$') { $s = $matches[1] + '_dashes' }
    $s = $s.Trim()
    $s = $s -replace '\s+', '_'
    $s = $s -replace '-', '_'
    $s = $s -replace '_+', '_'
    $s = $s -replace '^_', ''
    $s = $s -replace '_$', ''
    return $s
}

# ---- alias-map parsing ----

$Aliases = @{}        # prose phrase → block action name
$IgnoreProse = @()
$IgnoreBlock = @()

function Parse-AliasMap {
    if (-not (Test-Path $AliasMapPath)) { return }
    $section = ''
    $linenum = 0
    foreach ($rawLine in (Get-Content -LiteralPath $AliasMapPath)) {
        $linenum++
        $line = $rawLine -replace "`r$", ''
        if ($line -match '^\s*$') { continue }
        if ($line -match '^\s*#') { continue }
        $stripped = $line -replace '\s\s#.*$', ''

        if ($stripped -notmatch '^\s' -and $stripped -match '^([a-z_]+):\s*$') {
            $section = $matches[1]
            continue
        }

        if ($section -eq 'aliases') {
            if ($stripped -match '^\s+"([^"]*)":\s*(.*)$' -or $stripped -match "^\s+'([^']*)':\s*(.*)\s*$") {
                $key = $matches[1]
                $value = (Unquote $matches[2]).Trim()
                if ([string]::IsNullOrWhiteSpace($value)) {
                    Emit-Error "malformed alias-map entry at line $linenum — alias '$key' has empty/missing target. Empty targets are rejected to prevent silent drift escape (Spec 330 DA Finding 2 disposition)."
                    exit 2
                }
                $script:Aliases[$key] = $value
            }
        } elseif ($section -eq 'ignore_prose') {
            if ($stripped -match '^\s+-\s+"([^"]*)"\s*$' -or $stripped -match "^\s+-\s+'([^']*)'\s*$") {
                $script:IgnoreProse += $matches[1]
            }
        } elseif ($section -eq 'ignore_block') {
            if ($stripped -match '^\s+-\s+"([^"]*)"\s*$' -or $stripped -match "^\s+-\s+'([^']*)'\s*$") {
                $script:IgnoreBlock += $matches[1]
            }
        }
    }
}

# ---- prose extraction ----

function Get-ProseSection {
    $lines = Get-Content -LiteralPath $AgentsMd
    $capturing = $false
    $out = @()
    foreach ($line in $lines) {
        $clean = $line -replace "`r$", ''
        if (-not $capturing) {
            if ($clean -match '^### Authorization-required commands\s*$') {
                $capturing = $true
                continue
            }
        } else {
            if ($clean -match '^#{2,3}\s') { break }
            $out += $clean
        }
    }
    return $out
}

function Get-ProseActions {
    $section = Get-ProseSection
    if (-not $section -or $section.Count -eq 0 -or (($section -join '').Trim() -eq '')) {
        Emit-Error "'authorization-required-commands' prose section not found in AGENTS.md (heading '### Authorization-required commands' missing or renamed)"
        exit 2
    }

    $actions = New-Object System.Collections.ArrayList
    foreach ($line in $section) {
        if ($line -notmatch '^\s*-\s') { continue }

        # List bullet vs simple bullet: list bullet has ":" before the first backtick
        $isList = $false
        $beforeFirstBacktick = if ($line.Contains('`')) { $line.Substring(0, $line.IndexOf('`')) } else { $line }
        if ($beforeFirstBacktick -match ':') { $isList = $true }

        # Extract every backtick-quoted token from the line, in order
        $tokens = [regex]::Matches($line, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value }
        $extractedFirst = $false
        foreach ($token in $tokens) {
            if (-not $isList -and $extractedFirst) { continue }
            $extractedFirst = $true
            if ($script:IgnoreProse -contains $token) { continue }
            if ($script:Aliases.ContainsKey($token)) {
                [void]$actions.Add($script:Aliases[$token])
            } else {
                $slug = ConvertTo-Slug $token
                if ($slug) { [void]$actions.Add($slug) }
            }
        }
    }
    return $actions
}

# ---- block extraction ----

function Get-BlockSection {
    $lines = Get-Content -LiteralPath $AgentsMd
    $capturing = $false
    $extracted = @()
    foreach ($line in $lines) {
        $clean = $line -replace "`r$", ''
        if ($clean -match '<!-- forge:auth-rules:start -->') { $capturing = $true; continue }
        if ($clean -match '<!-- forge:auth-rules:end -->')   { $capturing = $false; continue }
        if ($capturing) { $extracted += $clean }
    }
    $infence = $false
    $result = @()
    foreach ($line in $extracted) {
        if ($line -match '^```yaml') { $infence = $true; continue }
        if ($line -match '^```')     { $infence = $false; continue }
        if ($infence) { $result += $line }
    }
    return $result
}

# Spec 330 AC 9b — reject alias-map entries whose target is not a declared block action
# (post-ignore_block filter). Catches structural inconsistencies like the dangling
# `branch -D → git_branch_force_delete` entry /consensus 330 surfaced.
# Note: $BlockActions is untyped to tolerate PowerShell's habit of unboxing single-element
# collections to scalars; we re-wrap with @() for the -notcontains check.
function Test-AliasTargets {
    param($BlockActions)
    $list = @($BlockActions)
    foreach ($key in $script:Aliases.Keys) {
        $target = $script:Aliases[$key]
        if ($list -notcontains $target) {
            Emit-Error "alias-map entry '$key' targets '$target' which is not a declared block action (Spec 330 AC 9b). Add the target to the AGENTS.md YAML block, fix the alias target, or remove the alias entry."
            exit 2
        }
    }
}

function Get-BlockActions {
    $section = Get-BlockSection
    if (-not $section -or $section.Count -eq 0 -or (($section -join '').Trim() -eq '')) {
        Emit-Error "AGENTS.md structured block not found between sentinels '<!-- forge:auth-rules:start -->' / '<!-- forge:auth-rules:end -->'"
        exit 2
    }

    $actions = New-Object System.Collections.ArrayList
    $inActions = $false
    foreach ($rawLine in $section) {
        $line = $rawLine
        if ($line -match '^\s*$') { continue }
        if ($line -match '^\s*#') { continue }
        $stripped = $line -replace '\s\s#.*$', ''

        if ($stripped -notmatch '^\s' -and $stripped -match '^actions:\s*$') {
            $inActions = $true
            continue
        }
        if ($stripped -notmatch '^\s' -and $stripped -match '^[a-z_]+:') {
            $inActions = $false
            continue
        }
        if ($inActions -and $stripped -match '^\s+-\s+name:\s+(.*)$') {
            $name = (Unquote $matches[1])
            if ($script:IgnoreBlock -notcontains $name) {
                [void]$actions.Add($name)
            }
        }
    }
    return $actions
}

# ---- main ----

Parse-AliasMap
$blockActions = Get-BlockActions
Test-AliasTargets -BlockActions $blockActions   # Spec 330 AC 9b — reject dangling alias targets
$proseActions = Get-ProseActions

# Dedupe
$proseUnique = @($proseActions | Select-Object -Unique)
$blockUnique = @($blockActions | Select-Object -Unique)

# Drift = symmetric difference
$proseOnly = @($proseUnique | Where-Object { $blockUnique -notcontains $_ })
$blockOnly = @($blockUnique | Where-Object { $proseUnique -notcontains $_ })

$proseCount = $proseUnique.Count
$blockCount = $blockUnique.Count
$driftCount = $proseOnly.Count + $blockOnly.Count

$EffectiveMode = if ($Mode) { $Mode } else { 'advisory' }

# ---- output ----

function ConvertTo-JsonEscape {
    param([string]$Text)
    $t = $Text -replace '\\', '\\\\'
    $t = $t -replace '"', '\"'
    $t = $t -replace "`r", '\r'
    $t = $t -replace "`n", '\n'
    $t = $t -replace "`t", '\t'
    return $t
}

function Write-EvidenceArtifact {
    # Spec 333: PS parity — atomic write (write-to-tmp + Move-Item).
    param(
        [string]$LinterName, [string]$InputFileArg, [string]$ModeValue,
        [string]$ResultLabel, [int]$ExitCodeValue, [string]$StdoutBuf, [string]$SummaryJson
    )
    if ([string]::IsNullOrEmpty($EvidenceDir)) { return }
    try {
        if (-not (Test-Path $EvidenceDir)) {
            New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
        }
    } catch {
        [Console]::Error.WriteLine("WARN: validate-agents-md-drift: failed to create evidence dir '$EvidenceDir' — artifact not written")
        return
    }
    $tsIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $tsFile = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmss') + '-' + $PID
    $inputSha = ''
    if (Test-Path $InputFileArg) {
        try { $inputSha = (& git -C $RepoRoot hash-object $InputFileArg 2>$null).Trim() } catch {}
    }
    $gitCommit = ''
    try { $gitCommit = (& git -C $RepoRoot rev-parse HEAD 2>$null).Trim() } catch {}
    $specId = ''
    if ($EvidenceDir -match 'SPEC-(\d+)-') { $specId = $matches[1] }
    $finalPath = Join-Path $EvidenceDir "$LinterName-$tsFile.json"
    $tmpPath = "$finalPath.tmp"
    $body = @"
{
  "linter": "$LinterName",
  "spec": "$specId",
  "ran_at": "$tsIso",
  "input_file": "$(ConvertTo-JsonEscape $InputFileArg)",
  "input_sha": "$inputSha",
  "mode": "$ModeValue",
  "result": "$ResultLabel",
  "exit_code": $ExitCodeValue,
  "summary": $SummaryJson,
  "stdout": "$(ConvertTo-JsonEscape $StdoutBuf)",
  "stderr": "",
  "git_commit": "$gitCommit"
}
"@
    try {
        Set-Content -Path $tmpPath -Value $body -NoNewline -Encoding UTF8 -ErrorAction Stop
        Move-Item -Path $tmpPath -Destination $finalPath -Force -ErrorAction Stop
    } catch {
        [Console]::Error.WriteLine("WARN: validate-agents-md-drift: failed to write evidence artifact to '$finalPath' ($($_.Exception.Message))")
        if (Test-Path $tmpPath) { Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue }
    }
}

# Spec 333: capture GATE output into a buffer for the audit artifact.
$gateBuf = ''
$resultLabel = ''

if ($Json) {
    $proseList = ($proseOnly | ForEach-Object { '"' + (ConvertTo-JsonEscape $_) + '"' }) -join ','
    $blockList = ($blockOnly | ForEach-Object { '"' + (ConvertTo-JsonEscape $_) + '"' }) -join ','
    $out = '{"prose_count":' + $proseCount + ',"block_count":' + $blockCount + ',"drift_count":' + $driftCount + ',"mode":"' + (ConvertTo-JsonEscape $EffectiveMode) + '","prose_only":[' + $proseList + '],"block_only":[' + $blockList + ']}'
    Write-Output $out
    $gateBuf = $out
    if ($driftCount -eq 0) { $resultLabel = 'PASS' }
    elseif ($EffectiveMode -eq 'strict') { $resultLabel = 'FAIL' }
    else { $resultLabel = 'WARN' }
} else {
    if ($driftCount -eq 0) {
        $gateBuf = "GATE [agents-md-drift]: PASS - $proseCount actions in prose, $blockCount in block, 0 drift entries (mode=$EffectiveMode)"
        $resultLabel = 'PASS'
        Write-Output $gateBuf
    } else {
        $resultLabel = if ($EffectiveMode -eq 'strict') { 'FAIL' } else { 'WARN' }
        $gateBuf = "GATE [agents-md-drift]: $resultLabel - $proseCount in prose, $blockCount in block, $driftCount drift entries (mode=$EffectiveMode):"
        Write-Output $gateBuf
        foreach ($p in $proseOnly) { $line = "  prose-only: $p"; Write-Output $line; $gateBuf += "`n$line" }
        foreach ($b in $blockOnly) { $line = "  block-only: $b"; Write-Output $line; $gateBuf += "`n$line" }
    }
}

# Spec 333: compute exit code, write artifact, then exit.
$exitCodeFinal = 0
if ($driftCount -ne 0 -and $EffectiveMode -eq 'strict') { $exitCodeFinal = 1 }

$proseListJ = ($proseOnly | ForEach-Object { '"' + (ConvertTo-JsonEscape $_) + '"' }) -join ','
$blockListJ = ($blockOnly | ForEach-Object { '"' + (ConvertTo-JsonEscape $_) + '"' }) -join ','
$summaryJson = "{`"prose_count`":$proseCount,`"block_count`":$blockCount,`"drift_count`":$driftCount,`"prose_only`":[$proseListJ],`"block_only`":[$blockListJ]}"
Write-EvidenceArtifact -LinterName 'validate-agents-md-drift' -InputFileArg $AgentsMd -ModeValue $EffectiveMode -ResultLabel $resultLabel -ExitCodeValue $exitCodeFinal -StdoutBuf $gateBuf -SummaryJson $summaryJson

exit $exitCodeFinal

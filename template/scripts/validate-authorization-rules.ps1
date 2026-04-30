# validate-authorization-rules.ps1 — Lint command bodies vs AGENTS.md authorization rules.
# Part of Spec 327 — Standing lint gate for AGENTS.md authorization rules vs command bodies.
#
# PowerShell parity for scripts/validate-authorization-rules.sh. Output format identical.
#
# Usage: pwsh scripts/validate-authorization-rules.ps1 [-Mode advisory|strict] [-Json] [-ScanPaths "a,b"] [-Help]

[CmdletBinding()]
param(
    [ValidateSet('advisory', 'strict')]
    [string]$Mode = '',
    [switch]$Json,
    [string]$ScanPaths = '',
    [string]$EvidenceDir = '',  # Spec 333: write JSON audit artifact when set
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$AgentsMd = Join-Path $RepoRoot 'AGENTS.md'
$Whitelist = Join-Path $RepoRoot 'scripts/auth-rules-whitelist.yaml'
$DefaultRoots = @(
    (Join-Path $RepoRoot '.claude/commands'),
    (Join-Path $RepoRoot '.forge/commands'),
    (Join-Path $RepoRoot 'template/.claude/commands'),
    (Join-Path $RepoRoot 'template/.forge/commands')
)
$MinActions = @('git_push', 'git_push_force', 'git_reset_hard', 'git_checkout_dashes', 'gh_pr_create', 'gh_pr_merge', 'rm_rf')

function Show-Usage {
    @'
validate-authorization-rules.ps1 — Spec 327 lint gate (PowerShell parity)

Usage: pwsh scripts/validate-authorization-rules.ps1 [-Mode advisory|strict] [-Json] [-ScanPaths "a,b"] [-Help]

Reads AGENTS.md sentinel-delimited block (<!-- forge:auth-rules:start --> ... <!-- forge:auth-rules:end -->)
and scans command bodies under .claude/commands/, .forge/commands/, template/.claude/commands/,
template/.forge/commands/ for authorization-required actions without preceding gating tokens.

Whitelist: scripts/auth-rules-whitelist.yaml (entries require file:, action:, reason:).

Options:
  -Mode advisory    Emit WARN, exit 0 (default at first ship per Spec 327 Path B)
  -Mode strict      Emit FAIL, exit non-zero on any violation
  -Json             Emit JSON array of {file, line, action, gating_token_found, whitelist_entry}
  -ScanPaths "a,b"  Comma-separated paths to scan (overrides the 4 default roots; for tests/fixtures)
  -EvidenceDir <p>  Spec 333: write a JSON audit artifact to <p>/<linter>-<timestamp>.json
                    capturing input SHA, mode, result, and summary. Failure to write the artifact
                    emits a stderr warning but does NOT fail the gate.
  -Help             Print this help

Exit codes:
  0  No violations OR advisory mode
  1  Violations found in strict mode
  2  Configuration error (missing/malformed AGENTS.md block, missing required action, malformed whitelist entry)

See: docs/specs/327-agents-md-authorization-rule-lint-gate.md
'@
}

if ($Help) { Show-Usage; exit 0 }

# Helpers

function Strip-Cr {
    param([string]$Text)
    return $Text -replace "`r$", ''
}

function Unquote {
    param([string]$Value)
    $v = $Value.Trim()
    if ($v.StartsWith("'") -and $v.EndsWith("'")) {
        return $v.Substring(1, $v.Length - 2)
    }
    return $v
}

function Extract-Block {
    if (-not (Test-Path $AgentsMd)) {
        Write-Error "AGENTS.md not found at $AgentsMd"
        exit 2
    }
    $lines = Get-Content -LiteralPath $AgentsMd
    $capturing = $false
    $extracted = @()
    foreach ($line in $lines) {
        $clean = $line -replace "`r$", ''
        if ($clean -match '<!-- forge:auth-rules:start -->') { $capturing = $true; continue }
        if ($clean -match '<!-- forge:auth-rules:end -->')   { $capturing = $false; continue }
        if ($capturing) { $extracted += $clean }
    }
    # Strip ```yaml fence
    $infence = $false
    $result = @()
    foreach ($line in $extracted) {
        if ($line -match '^```yaml') { $infence = $true; continue }
        if ($line -match '^```')     { $infence = $false; continue }
        if ($infence) { $result += $line }
    }
    return $result
}

function Parse-Block {
    param([string[]]$Block)
    $script:ModeDefault = ''
    $script:WindowDefault = 10
    $script:GatingDefault = '\(yes/no\)'
    $script:Actions = @()
    $inActions = $false
    $current = $null

    foreach ($rawLine in $Block) {
        $line = $rawLine
        if ($line -match '^\s*$') { continue }
        if ($line -match '^\s*#') { continue }
        # Strip inline comment ("  # ...")
        $stripped = $line -replace '\s\s#.*$', ''

        # Top-level key (no leading whitespace) — match "key: value" OR bare "key:"
        if ($stripped -notmatch '^\s' -and $stripped -match '^([a-z_]+):\s*(.*)?$') {
            $key = $matches[1]
            $value = if ($matches[2]) { (Unquote $matches[2]) } else { '' }
            switch ($key) {
                'mode'                     { $script:ModeDefault = $value; $inActions = $false }
                'proximity_window_default' { $script:WindowDefault = [int]$value; $inActions = $false }
                'gating_token_default'     { $script:GatingDefault = $value; $inActions = $false }
                'actions'                  { $inActions = $true }
                default                    { }
            }
            continue
        }

        if ($inActions) {
            if ($stripped -match '^\s+-\s+name:\s+(.*)$') {
                if ($current) { $script:Actions += $current }
                $current = [ordered]@{
                    name             = (Unquote $matches[1])
                    pattern          = ''
                    gating_token     = ''
                    proximity_window = ''
                }
                continue
            }
            if ($current -and $stripped -match '^\s+([a-z_]+):\s+(.*)$') {
                $key = $matches[1]
                $value = (Unquote $matches[2])
                if ($current.Contains($key)) { $current[$key] = $value }
            }
        }
    }
    if ($current) { $script:Actions += $current }
}

function Parse-Whitelist {
    $script:WhitelistEntries = @()
    $script:MalformedWhitelist = ''
    if (-not (Test-Path $Whitelist)) { return }

    $lines = Get-Content -LiteralPath $Whitelist
    $linenum = 0
    $current = $null
    $entryStart = 0

    foreach ($rawLine in $lines) {
        $linenum++
        $line = $rawLine -replace "`r$", ''
        if ($line -match '^\s*$') { continue }
        if ($line -match '^\s*#') { continue }
        $stripped = $line -replace '\s\s#.*$', ''

        if ($stripped -match '^-\s+file:\s+(.*)$') {
            if ($current) {
                if (-not $current.file -or -not $current.action -or -not $current.reason) {
                    $script:MalformedWhitelist = "entry starting at line $entryStart lacks file/action/reason"
                    return
                }
                $script:WhitelistEntries += $current
            }
            $entryStart = $linenum
            $fileVal = (Unquote $matches[1])
            if ($fileVal -match '[\*\?]') {
                $script:MalformedWhitelist = "entry at line $linenum uses wildcard file pattern (forbidden by Spec 327 R4)"
                return
            }
            $current = [ordered]@{ file = $fileVal; action = ''; reason = '' }
            continue
        }
        if ($current -and $stripped -match '^\s+([a-z_]+):\s+(.*)$') {
            $key = $matches[1]
            $value = (Unquote $matches[2])
            if ($key -in 'file', 'action', 'reason') { $current[$key] = $value }
        }
    }
    if ($current) {
        if (-not $current.file -or -not $current.action -or -not $current.reason) {
            $script:MalformedWhitelist = "entry starting at line $entryStart lacks file/action/reason"
            return
        }
        $script:WhitelistEntries += $current
    }
}

function Test-Whitelisted {
    param([string]$RelPath, [string]$ActionName)
    foreach ($entry in $script:WhitelistEntries) {
        if ($entry.file -eq $RelPath -and $entry.action -eq $ActionName) {
            return $entry.reason
        }
    }
    return $null
}

function Test-GatingTokenBefore {
    param(
        [string]$FilePath,
        [int]$MatchLine,
        [int]$Window,
        [string]$GatingRegex
    )
    $start = [Math]::Max(1, $MatchLine - $Window)
    $lines = Get-Content -LiteralPath $FilePath
    for ($i = $start - 1; $i -lt $MatchLine -and $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $GatingRegex) { return $true }
    }
    return $false
}

function Write-EvidenceArtifact {
    # Spec 333: PS parity — atomic write (write-to-tmp + Move-Item).
    # Inputs: -LinterName, -InputFile, -ModeValue, -ResultLabel, -ExitCodeValue, -StdoutBuf, -SummaryJson
    # Failure modes: warning to stderr, returns 0 (never fails the gate).
    param(
        [string]$LinterName, [string]$InputFile, [string]$ModeValue,
        [string]$ResultLabel, [int]$ExitCodeValue, [string]$StdoutBuf, [string]$SummaryJson
    )
    if ([string]::IsNullOrEmpty($EvidenceDir)) { return }
    try {
        if (-not (Test-Path $EvidenceDir)) {
            New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
        }
    } catch {
        [Console]::Error.WriteLine("WARN: validate-authorization-rules: failed to create evidence dir '$EvidenceDir' — artifact not written")
        return
    }
    $tsIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $tsFile = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmss') + '-' + $PID
    $inputSha = ''
    if (Test-Path $InputFile) {
        try { $inputSha = (& git -C $RepoRoot hash-object $InputFile 2>$null).Trim() } catch {}
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
  "input_file": "$(ConvertTo-JsonEscape $InputFile)",
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
        [Console]::Error.WriteLine("WARN: validate-authorization-rules: failed to write evidence artifact to '$finalPath' ($($_.Exception.Message))")
        if (Test-Path $tmpPath) { Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue }
    }
}

function ConvertTo-JsonEscape {
    param([string]$Text)
    $t = $Text -replace '\\', '\\\\'
    $t = $t -replace '"', '\"'
    $t = $t -replace "`r", '\r'
    $t = $t -replace "`n", '\n'
    $t = $t -replace "`t", '\t'
    return $t
}

# Main

$blockLines = Extract-Block
if (-not $blockLines -or $blockLines.Count -eq 0) {
    Write-Error "AGENTS.md structured block not found between sentinels '<!-- forge:auth-rules:start -->' / '<!-- forge:auth-rules:end -->'"
    exit 2
}

Parse-Block -Block $blockLines
if ($script:Actions.Count -eq 0) {
    Write-Error "AGENTS.md structured block contains no actions (malformed YAML or empty actions list)"
    exit 2
}

# Verify minimum action set
foreach ($required in $MinActions) {
    if (-not ($script:Actions | Where-Object { $_.name -eq $required })) {
        Write-Error "required action '$required' missing from AGENTS.md structured block"
        exit 2
    }
}

Parse-Whitelist
if ($script:MalformedWhitelist) {
    Write-Error "malformed whitelist entry — $script:MalformedWhitelist"
    exit 2
}

# Determine effective mode
$EffectiveMode = if ($Mode) { $Mode } elseif ($script:ModeDefault) { $script:ModeDefault } else { 'advisory' }
if ($EffectiveMode -ne 'advisory' -and $EffectiveMode -ne 'strict') {
    Write-Error "invalid mode '$EffectiveMode' (expected advisory or strict)"
    exit 2
}

# Resolve scan roots
$ScanRoots = $DefaultRoots
if ($ScanPaths) {
    $ScanRoots = @()
    foreach ($p in ($ScanPaths -split ',')) {
        $p = $p.Trim()
        if ([System.IO.Path]::IsPathRooted($p)) {
            $ScanRoots += $p
        } else {
            $ScanRoots += (Join-Path $RepoRoot $p)
        }
    }
}

# Scan
$violations = @()
$scannedFiles = 0
$startTime = Get-Date

foreach ($root in $ScanRoots) {
    if (-not (Test-Path $root)) { continue }
    $files = if ((Get-Item $root).PSIsContainer) {
        Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.md', '*.jinja' -ErrorAction SilentlyContinue
    } else {
        Get-Item -LiteralPath $root
    }
    foreach ($file in $files) {
        $scannedFiles++
        $rel = $file.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
        $content = Get-Content -LiteralPath $file.FullName
        for ($lineIdx = 0; $lineIdx -lt $content.Count; $lineIdx++) {
            $lineNum = $lineIdx + 1
            $lineText = $content[$lineIdx]
            foreach ($action in $script:Actions) {
                if (-not $action.pattern) { continue }
                if ($lineText -match $action.pattern) {
                    $gatingRe = if ($action.gating_token) { $action.gating_token } else { $script:GatingDefault }
                    $window = if ($action.proximity_window) { [int]$action.proximity_window } else { $script:WindowDefault }
                    if (Test-GatingTokenBefore -FilePath $file.FullName -MatchLine $lineNum -Window $window -GatingRegex $gatingRe) {
                        continue
                    }
                    $wl = Test-Whitelisted -RelPath $rel -ActionName $action.name
                    $violations += [ordered]@{
                        file               = $rel
                        line               = $lineNum
                        action             = $action.name
                        gating_token_found = $false
                        whitelist_entry    = $wl
                    }
                }
            }
        }
    }
}

$elapsed = [int]((Get-Date) - $startTime).TotalSeconds
$actionable = ($violations | Where-Object { -not $_.whitelist_entry }).Count

# Spec 333: capture GATE output into a buffer for the audit artifact.
$gateBuf = ''
$resultLabel = ''

if ($Json) {
    $out = '['
    for ($i = 0; $i -lt $violations.Count; $i++) {
        if ($i -gt 0) { $out += ',' }
        $v = $violations[$i]
        $wlField = if ($v.whitelist_entry) { '"' + (ConvertTo-JsonEscape $v.whitelist_entry) + '"' } else { 'null' }
        $out += "`n  {""file"":""$(ConvertTo-JsonEscape $v.file)"",""line"":$($v.line),""action"":""$(ConvertTo-JsonEscape $v.action)"",""gating_token_found"":false,""whitelist_entry"":$wlField}"
    }
    $out += "`n]"
    Write-Output $out
    $gateBuf = $out
    if ($actionable -eq 0) { $resultLabel = 'PASS' }
    elseif ($EffectiveMode -eq 'strict') { $resultLabel = 'FAIL' }
    else { $resultLabel = 'WARN' }
} else {
    if ($actionable -eq 0) {
        $gateBuf = "GATE [authorization-rule-lint]: PASS - $scannedFiles command files clean across $($script:Actions.Count) actions (mode=$EffectiveMode, scanned in ${elapsed}s)"
        $resultLabel = 'PASS'
        Write-Output $gateBuf
    } else {
        $resultLabel = if ($EffectiveMode -eq 'strict') { 'FAIL' } else { 'WARN' }
        $gateBuf = "GATE [authorization-rule-lint]: $resultLabel - $actionable violation(s) across $scannedFiles files (mode=$EffectiveMode, scanned in ${elapsed}s):"
        Write-Output $gateBuf
        foreach ($v in $violations) {
            $tag = if ($v.whitelist_entry) { " [whitelisted: $($v.whitelist_entry)]" } else { '' }
            $line = "  $($v.file):$($v.line) | $($v.action)$tag"
            Write-Output $line
            $gateBuf += "`n$line"
        }
    }
}

# Spec 333: compute exit code, write artifact, then exit.
$exitCodeFinal = 0
if ($actionable -gt 0 -and $EffectiveMode -eq 'strict') { $exitCodeFinal = 1 }

$summaryJson = "{`"actionable`":$actionable,`"scanned_files`":$scannedFiles,`"action_count`":$($script:Actions.Count),`"violations_total`":$($violations.Count),`"elapsed_seconds`":$elapsed}"
Write-EvidenceArtifact -LinterName 'validate-authorization-rules' -InputFile $AgentsMd -ModeValue $EffectiveMode -ResultLabel $resultLabel -ExitCodeValue $exitCodeFinal -StdoutBuf $gateBuf -SummaryJson $summaryJson

exit $exitCodeFinal

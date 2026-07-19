# two-list-bypass-detect.ps1 — PowerShell parity for the Spec 411 coordinated two-list bypass
# detector. Output (GATE line / JSON) and exit codes match two-list-bypass-detect.sh after
# path/encoding normalization.
#
# Threat + matching rule: see two-list-bypass-detect.sh header. For each `ignore_prose` entry,
# normalize via alias-first-then-slugify (identical to validate-agents-md-drift.ps1) and flag a
# coordinated bypass when the normalized name is also in `ignore_block:`.
#
# Usage: pwsh two-list-bypass-detect.ps1 [-AliasMap <file>] [-Json] [-Help]
# Exit:  0 no bypass | 1 bypass found | 2 usage/config error

[CmdletBinding()]
param(
    [string]$AliasMap = '',
    [switch]$Json,
    [switch]$Help
)

$ErrorActionPreference = 'Continue'
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::Error.Encoding = [System.Text.Encoding]::UTF8 } catch { }

function Show-Usage {
    # forge:path-literal-ok (comment/fixture) — heredoc help text below references docs/specs/411-...md
    @'
two-list-bypass-detect.ps1 — Spec 411 coordinated two-list bypass detector (PowerShell parity)

Usage: pwsh two-list-bypass-detect.ps1 [-AliasMap <file>] [-Json] [-Help]

Parses the alias map's aliases:/ignore_prose:/ignore_block: sections. For each ignore_prose
entry it computes the block-action name (alias lookup, else slugify) and reports a COORDINATED
BYPASS when that name is also present in ignore_block:.

Exit codes:
  0  No coordinated bypass (PASS)
  1  One or more coordinated bypasses found (FAIL)
  2  Usage / config error

# forge:path-literal-ok (docstring/prose — classic-default spelling in help text; Spec 575)
See: docs/specs/411-two-list-bypass-detector.md
'@
}

if ($Help) { Show-Usage; exit 0 }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$DefaultAliasMap = Join-Path $RepoRoot 'scripts/agents-md-action-aliases.yaml'
$AliasMapPath = if ($AliasMap) { $AliasMap } else { $DefaultAliasMap }

if (-not (Test-Path $AliasMapPath)) {
    [Console]::Error.WriteLine("ERROR: alias map not found at $AliasMapPath")
    exit 2
}

# ---- helpers (kept identical to validate-agents-md-drift.ps1) ----

function Unquote {
    param([string]$Value)
    $v = $Value.Trim()
    if ($v.StartsWith("'") -and $v.EndsWith("'") -and $v.Length -ge 2) { return $v.Substring(1, $v.Length - 2) }
    if ($v.StartsWith('"') -and $v.EndsWith('"') -and $v.Length -ge 2) { return $v.Substring(1, $v.Length - 2) }
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

# ---- alias-map parsing (mirrors validate-agents-md-drift.ps1::Parse-AliasMap) ----

$Aliases = @{}
$IgnoreProse = @()
$IgnoreBlock = @()

function Parse-AliasMap {
    $section = ''
    foreach ($rawLine in (Get-Content -LiteralPath $AliasMapPath)) {
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
                if ([string]::IsNullOrWhiteSpace($value)) { continue }
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

function Convert-ProseToAction {
    param([string]$Phrase)
    if ($script:Aliases.ContainsKey($Phrase)) { return $script:Aliases[$Phrase] }
    return (ConvertTo-Slug $Phrase)
}

# ---- main ----

Parse-AliasMap

$bypasses = New-Object System.Collections.ArrayList
foreach ($p in $IgnoreProse) {
    $norm = Convert-ProseToAction $p
    if (-not $norm) { continue }
    if ($IgnoreBlock -contains $norm) {
        [void]$bypasses.Add([pscustomobject]@{ ignore_prose = $p; normalized = $norm; ignore_block = $norm })
    }
}

$bypassCount = $bypasses.Count
$proseIgnoreCount = $IgnoreProse.Count
$blockIgnoreCount = $IgnoreBlock.Count

function ConvertTo-JsonEscape {
    param([string]$Text)
    $t = $Text -replace '\\', '\\\\'
    $t = $t -replace '"', '\"'
    return $t
}

if ($Json) {
    $items = ($bypasses | ForEach-Object {
        '{"ignore_prose":"' + (ConvertTo-JsonEscape $_.ignore_prose) + '","normalized":"' + (ConvertTo-JsonEscape $_.normalized) + '","ignore_block":"' + (ConvertTo-JsonEscape $_.ignore_block) + '"}'
    }) -join ','
    Write-Output ('{"bypass_count":' + $bypassCount + ',"prose_ignore_count":' + $proseIgnoreCount + ',"block_ignore_count":' + $blockIgnoreCount + ',"bypasses":[' + $items + ']}')
} else {
    if ($bypassCount -eq 0) {
        Write-Output "GATE [two-list-bypass]: PASS - no coordinated ignore_prose+ignore_block bypass ($proseIgnoreCount prose-ignores, $blockIgnoreCount block-ignores checked)"
    } else {
        [Console]::Error.WriteLine("GATE [two-list-bypass]: FAIL - $bypassCount coordinated bypass(es) detected (an action suppressed on BOTH sides is invisible to drift detection):")
        foreach ($b in $bypasses) {
            [Console]::Error.WriteLine("  bypass: ignore_prose ""$($b.ignore_prose)"" -> ""$($b.normalized)"" also in ignore_block (""$($b.ignore_block)"")")
        }
    }
}

if ($bypassCount -eq 0) { exit 0 } else { exit 1 }

# FORGE safety-config helpers — Spec 387 Component A library (PowerShell parity).
# Sourceable: pure functions, no main execution.
#
# Public functions:
#   Get-SafetyConfigPatterns -YamlFile <path>
#                                     — read patterns array from yaml; emit one per line
#   Get-SafetyConfigMatches -YamlFile <path> -DiffPaths <string[]>
#                                     — emit matching paths (deduplicated, input order)
#   Test-SafetyConfigOverride -Reason <text>
#                                     — return $true/$false; writes error to stderr on $false
#   Test-SafetyConfigBootstrap -DiffStatus <string[]>
#                                     — return $true if registry add/delete detected (R1c)
#   Get-SafetyConfigIgnoreList -YamlFile <path>
#                                     — Spec 397; read ignore yaml, emit one token per line
#                                       on stdout. Verifies version: 1; warns on empty reason;
#                                       returns empty array + stderr error on missing/wrong-version yaml.
#   Get-SafetyConfigSpecFiles -SpecNum <n> -Baseline <rev> [-Head <rev>] [-SpecFile <path>]
#                                     — Spec 542 R1 parity; emit the spec's own changed files via
#                                       commits tagged "Spec <NUM>", falling back to the spec's
#                                       Implementation Summary file list. Returns $null if neither
#                                       source is available (caller falls back to cumulative diff).
#   Test-SafetyConfigRegionTouched -Baseline <rev> -Head <rev> -File <path> -Heading <text>
#                                     — Spec 542 R2 parity; $true if the diff's changed lines
#                                       intersect the named heading's section in File at Head.
#   Get-SafetyConfigRegistryFiles -YamlFile <path>
#                                     — Spec 542 R2 parity; registry patterns with any
#                                       `::<heading>` region suffix stripped, deduplicated.

# Trivial-string patterns that auto-reject as override reasons (R4b).
$script:SafetyTrivialPatterns = @('wip','ok','later','fix','tbd','n/a','na','none','pass','done')

# Load patterns array from a yaml registry file. Emits one pattern per line.
# Resolve forge.paths.<key> via runtime_config.py (Spec 564 — no config.ps1 twin exists;
# python is the Windows-side resolution surface). Falls back to the classic default on
# any resolution failure.
function Get-SafetyConfigPathsKey {
  param([string]$Key, [string]$RepoRoot = '.', [string]$Default)
  $libDir = $PSScriptRoot
  $core = Join-Path $libDir 'runtime_config.py'
  $forgePy = Join-Path $libDir '..\bin\forge-py.cmd'
  if (-not (Test-Path $forgePy)) { $forgePy = Join-Path $libDir '..\bin\forge-py' }
  if (-not (Test-Path $core) -or -not (Test-Path $forgePy)) { return $Default }
  try {
    $out = & $forgePy $core path $Key --dir $RepoRoot 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { return ($out | Select-Object -First 1).Trim() }
  } catch { }
  return $Default
}

function Get-SafetyConfigPatterns {
    param([Parameter(Mandatory)][string]$YamlFile)
    if (-not (Test-Path -LiteralPath $YamlFile -PathType Leaf)) {
        return @()
    }
    $inPatterns = $false
    $patterns = New-Object System.Collections.Generic.List[string]
    Get-Content -LiteralPath $YamlFile | ForEach-Object {
        $line = $_ -replace "`r$", ''
        if ($line -match '^patterns:\s*$') {
            $inPatterns = $true
            return
        }
        if ($inPatterns) {
            if ($line -match '^\s*$' -or $line -match '^\s*#') { return }
            if ($line -match '^\s+-\s+(.+)$') {
                $item = $Matches[1]
                # Strip quotes
                $item = $item -replace '^"', '' -replace '"$', ''
                $item = $item -replace "^'", '' -replace "'$", ''
                $patterns.Add($item) | Out-Null
            } else {
                $inPatterns = $false
            }
        }
    }
    return ,$patterns.ToArray()
}

# Convert a glob pattern to a regex (PowerShell -like is enough for most cases).
# Handles **, *, ? as PowerShell wildcards.
function ConvertTo-SafetyConfigRegex {
    param([Parameter(Mandatory)][string]$Pattern)
    $regex = [regex]::Escape($Pattern)
    # Unescape glob wildcards
    $regex = $regex -replace '\\\*\\\*', '.*'      # ** -> .*
    $regex = $regex -replace '\\\*', '[^/]*'        # *  -> [^/]*
    $regex = $regex -replace '\\\?', '.'            # ?  -> .
    return "^${regex}$"
}

# Match diff paths against registry patterns. Emits matching paths.
# -Baseline/-Head (optional, Spec 542 R2) are required only to evaluate region-scoped
# entries (pattern form `<file>::<heading>`); whole-file entries match regardless.
function Get-SafetyConfigMatches {
    param(
        [Parameter(Mandatory)][string]$YamlFile,
        [Parameter(Mandatory)][string[]]$DiffPaths,
        [string]$Baseline,
        [string]$Head = 'HEAD'
    )
    $patterns = Get-SafetyConfigPatterns -YamlFile $YamlFile
    if ($patterns.Count -eq 0) { return @() }
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $results = New-Object System.Collections.Generic.List[string]
    foreach ($path in $DiffPaths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ($seen.Contains($path)) { continue }
        foreach ($pattern in $patterns) {
            if ($pattern -match '::') {
                $parts = $pattern -split '::', 2
                $regionFile = $parts[0]
                $regionHeading = $parts[1]
                if ($path -eq $regionFile -and $Baseline -and (Test-SafetyConfigRegionTouched -Baseline $Baseline -Head $Head -File $regionFile -Heading $regionHeading)) {
                    $results.Add($path) | Out-Null
                    $seen.Add($path) | Out-Null
                    break
                }
                continue
            }
            $rx = ConvertTo-SafetyConfigRegex -Pattern $pattern
            if ($path -match $rx) {
                $results.Add($path) | Out-Null
                $seen.Add($path) | Out-Null
                break
            }
        }
    }
    return ,$results.ToArray()
}

# Line range (start, end; 1-indexed, inclusive) of a markdown heading's section in
# File as it exists at Rev. Returns $null if the file or heading is not found.
function Get-SafetyConfigRegionLineRange {
    param(
        [Parameter(Mandatory)][string]$Rev,
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string]$Heading
    )
    $content = git show "${Rev}:${File}" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $content) { return $null }
    $lines = $content -split "`n"
    $startLine = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Contains($Heading)) { $startLine = $i + 1; break }
    }
    if ($startLine -eq -1) { return $null }
    $depthMarker = ($Heading -replace '^(#+).*', '$1')
    if (-not $depthMarker -or $depthMarker -eq $Heading) { $depthMarker = '#' }
    $depth = $depthMarker.Length
    $endLine = $lines.Count
    $inFence = $false
    for ($i = $startLine; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^```') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        if ($lines[$i] -match "^#{1,$depth}\s") { $endLine = $i; break }
    }
    return @($startLine, $endLine)
}

# $true if the diff between Baseline and Head touches any changed line inside
# Heading's section of File (per Get-SafetyConfigRegionLineRange at Head).
function Test-SafetyConfigRegionTouched {
    param(
        [Parameter(Mandatory)][string]$Baseline,
        [Parameter(Mandatory)][string]$Head,
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string]$Heading
    )
    $range = Get-SafetyConfigRegionLineRange -Rev $Head -File $File -Heading $Heading
    if (-not $range) { return $false }
    $regionStart = $range[0]
    $regionEnd = $range[1]
    $hunks = git diff --unified=0 $Baseline $Head -- $File 2>$null | Select-String -Pattern '^@@ -\d+(,\d+)? \+(\d+)(,(\d+))? @@'
    foreach ($h in $hunks) {
        $m = $h.Matches[0]
        $newStart = [int]$m.Groups[2].Value
        $newCount = if ($m.Groups[4].Success) { [int]$m.Groups[4].Value } else { 1 }
        $newEnd = if ($newCount -eq 0) { $newStart } else { $newStart + $newCount - 1 }
        if ($newStart -le $regionEnd -and $newEnd -ge $regionStart) { return $true }
    }
    return $false
}

# Registry patterns with any `::<heading>` region suffix stripped (Spec 542 R2),
# deduplicated. Whole-file entries pass through unchanged.
function Get-SafetyConfigRegistryFiles {
    param([Parameter(Mandatory)][string]$YamlFile)
    $patterns = Get-SafetyConfigPatterns -YamlFile $YamlFile
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $results = New-Object System.Collections.Generic.List[string]
    foreach ($pattern in $patterns) {
        $fileOnly = ($pattern -split '::', 2)[0]
        if ($seen.Add($fileOnly)) { $results.Add($fileOnly) | Out-Null }
    }
    return ,$results.ToArray()
}

# Spec 542 R1 parity — emit the spec's own changed files via commits tagged
# "Spec <NUM>" (word-boundary), falling back to the spec file's Implementation
# Summary "Changed files" list. Returns $null if neither source is available.
function Get-SafetyConfigSpecFiles {
    param(
        [Parameter(Mandatory)][string]$SpecNum,
        [Parameter(Mandatory)][string]$Baseline,
        [string]$Head = 'HEAD',
        [string]$SpecFile
    )
    $grepPattern = "Spec ${SpecNum}([^0-9]|`$)"
    $commits = git log --no-merges --pretty=format:%H -E --grep=$grepPattern "${Baseline}..${Head}" 2>$null
    if ($commits) {
        $files = foreach ($c in ($commits -split "`n")) {
            if ($c) { git diff-tree --no-commit-id --name-only -r $c 2>$null }
        }
        return ,($files | Sort-Object -Unique)
    }
    if ($SpecFile -and (Test-Path -LiteralPath $SpecFile -PathType Leaf)) {
        $lines = Get-Content -LiteralPath $SpecFile
        $inSummary = $false
        $summary = New-Object System.Collections.Generic.List[string]
        foreach ($line in $lines) {
            if ($line -match '^## Implementation Summary\s*$') { $inSummary = $true; continue }
            if ($line -match '^## ' -and $inSummary) { $inSummary = $false; continue }
            if ($inSummary) { $summary.Add($line) | Out-Null }
        }
        $files = [regex]::Matches(($summary -join "`n"), '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notmatch '\s' }
        if ($files) { return ,$files }
    }
    return $null
}

# Validate Safety-Override reason text per R4b.
function Test-SafetyConfigOverride {
    param([Parameter(Mandatory)][string]$Reason)
    $trimmed = $Reason.Trim()
    if ($trimmed.Length -lt 50) {
        [Console]::Error.WriteLine("Safety-Override reason too short ($($trimmed.Length) chars, minimum 50). Provide a sentence of reasoning.")
        return $false
    }
    $lower = $trimmed.ToLowerInvariant()
    foreach ($trivial in $script:SafetyTrivialPatterns) {
        if ($lower -eq $trivial) {
            [Console]::Error.WriteLine("Safety-Override reason too trivial (matched: $trivial). Provide a sentence of reasoning.")
            return $false
        }
    }
    return $true
}

# Validate ## Safety Enforcement section in a spec body per R2d.
# Returns $true if valid, $false if invalid (writes detail to stderr on failure).
# Caller can interpret $false as exit 2 per R2e.
function Test-SafetyConfigSection {
    param(
        [Parameter(Mandatory)][string]$SpecFile,
        [string]$RepoRoot = '.'
    )
    if (-not (Test-Path -LiteralPath $SpecFile -PathType Leaf)) {
        [Console]::Error.WriteLine("Test-SafetyConfigSection: spec file not found: $SpecFile")
        return $false
    }
    $lines = Get-Content -LiteralPath $SpecFile
    $section = New-Object System.Collections.Generic.List[string]
    $inSection = $false
    foreach ($line in $lines) {
        if ($line -match '^## Safety Enforcement\s*$') { $inSection = $true; continue }
        if ($line -match '^## ' -and $inSection) { $inSection = $false; continue }
        if ($inSection) { $section.Add($line) | Out-Null }
    }
    if ($section.Count -eq 0) {
        # forge:path-literal-ok (comment) — fixed pointer to the FORGE repo's own template guide, not a consumer forge.paths key
        [Console]::Error.WriteLine('Safety enforcement section incomplete or missing. See template/docs/process-kit/safety-property-gate-guide.md.')
        return $false
    }
    $epLine  = $section | Where-Object { $_ -match '^Enforcement code path: ' } | Select-Object -First 1
    $npLine  = $section | Where-Object { $_ -match '^Negative-path test: ' }    | Select-Object -First 1
    $valLine = $section | Where-Object { $_ -match '^Validates' }                | Select-Object -First 1
    if (-not $epLine -or -not $npLine -or -not $valLine) {
        # forge:path-literal-ok (comment) — fixed pointer to the FORGE repo's own template guide, not a consumer forge.paths key
        [Console]::Error.WriteLine('Safety enforcement section incomplete or missing. See template/docs/process-kit/safety-property-gate-guide.md.')
        return $false
    }
    $valText = $valLine -replace '^Validates', ''
    if ($valText.Length -lt 10) {
        [Console]::Error.WriteLine('Safety-Enforcement Validates description too short (<10 chars).')
        return $false
    }
    $epFile = ($epLine -replace '^Enforcement code path: ([^:]+)::.*', '$1')
    $epSym  = ($epLine -replace '^Enforcement code path: [^:]+::(.*)$', '$1')
    $npFile = ($npLine -replace '^Negative-path test: ([^:]+)::.*', '$1')
    if ($epSym -eq '<placeholder>' -or $npLine -match '<deferred to Spec') {
        $ref = ($section -join "`n") | Select-String -Pattern 'Spec \d{3}' | ForEach-Object { $_.Matches[0].Value } | Select-Object -First 1
        if (-not $ref) {
            [Console]::Error.WriteLine('Placeholder used without Spec NNN reference. Per R3, placeholders require an UNENFORCED-pointer.')
            return $false
        }
        $refNum = $ref -replace 'Spec ', ''
        $specsDir = Get-SafetyConfigPathsKey -Key 'specs' -RepoRoot $RepoRoot -Default 'docs/specs'
        $refFile = Get-ChildItem -Path (Join-Path $RepoRoot $specsDir) -Filter "$refNum-*.md" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $refFile) {
            [Console]::Error.WriteLine("Referenced $ref does not exist.")
            return $false
        }
        $refStatus = Get-Content -LiteralPath $refFile.FullName | Where-Object { $_ -match '^- Status: ' } | ForEach-Object { ($_ -replace '^- Status: ', '').Trim() } | Select-Object -First 1
        if ($refStatus -in @('draft','in-progress','implemented','closed')) { return $true }
        [Console]::Error.WriteLine("Referenced $ref has invalid status ($refStatus). Per R3c, must be draft|in-progress|implemented|closed.")
        return $false
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $epFile) -PathType Leaf)) {
        [Console]::Error.WriteLine("Enforcement code path file not found: $epFile")
        return $false
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $npFile) -PathType Leaf)) {
        [Console]::Error.WriteLine("Negative-path test file not found: $npFile")
        return $false
    }
    return $true
}

# Load ignore-list from a Spec 397 ignore yaml. Emits one token name per line.
# Verifies `version: 1` is present (refuses any other version with stderr error).
# Warns to stderr on entries with empty reason; still emits the token.
function Get-SafetyConfigIgnoreList {
    param([Parameter(Mandatory)][string]$YamlFile)
    if (-not (Test-Path -LiteralPath $YamlFile -PathType Leaf)) {
        [Console]::Error.WriteLine("Get-SafetyConfigIgnoreList: file not found: $YamlFile")
        return @()
    }
    $lines = Get-Content -LiteralPath $YamlFile
    $versionLine = $lines | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
    if (-not $versionLine) {
        [Console]::Error.WriteLine('Get-SafetyConfigIgnoreList: unsupported ignore-list schema version (expected 1)')
        return @()
    }
    $versionVal = ($versionLine -replace '^version:\s*', '').Trim().Trim('"').Trim("'")
    if ($versionVal -ne '1') {
        [Console]::Error.WriteLine('Get-SafetyConfigIgnoreList: unsupported ignore-list schema version (expected 1)')
        return @()
    }
    $inIgnore = $false
    $tokens = New-Object System.Collections.Generic.List[string]
    $reasons = @{}
    $currentToken = ''
    $currentReason = ''
    foreach ($raw in $lines) {
        $line = $raw -replace "`r$", ''
        if ($line -match '^ignore:\s*$') { $inIgnore = $true; continue }
        if (-not $inIgnore) { continue }
        if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }
        if ($line -match '^\s+-\s+token:\s*(.+)$') {
            if ($currentToken) {
                $tokens.Add($currentToken) | Out-Null
                $reasons[$currentToken] = $currentReason
            }
            $currentToken = $Matches[1].Trim().Trim('"').Trim("'")
            $currentReason = ''
            continue
        }
        if ($line -match '^\s+reason:\s*(.*)$') {
            $currentReason = $Matches[1].Trim().Trim('"').Trim("'")
            continue
        }
        if ($line -match '^[^\s]') { $inIgnore = $false }
    }
    if ($currentToken) {
        $tokens.Add($currentToken) | Out-Null
        $reasons[$currentToken] = $currentReason
    }
    foreach ($t in $tokens) {
        if (-not $reasons[$t]) {
            [Console]::Error.WriteLine("Get-SafetyConfigIgnoreList: warning: token $t has empty reason")
        }
        Write-Output $t
    }
}

# Detect registry-file add/delete in diff status output (R1c bootstrap fallback).
# Input: lines from `git diff --name-status` (status TAB path).
function Test-SafetyConfigBootstrap {
    param([Parameter(Mandatory)][string[]]$DiffStatus)
    $registryPath = '.forge/safety-config-paths.yaml'
    foreach ($line in $DiffStatus) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -lt 2) { continue }
        $status = $parts[0]
        $path = $parts[1]
        if ($path -eq $registryPath -and ($status -eq 'A' -or $status -eq 'D')) {
            return $true
        }
    }
    return $false
}

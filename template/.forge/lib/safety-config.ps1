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

# Trivial-string patterns that auto-reject as override reasons (R4b).
$script:SafetyTrivialPatterns = @('wip','ok','later','fix','tbd','n/a','na','none','pass','done')

# Load patterns array from a yaml registry file. Emits one pattern per line.
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
function Get-SafetyConfigMatches {
    param(
        [Parameter(Mandatory)][string]$YamlFile,
        [Parameter(Mandatory)][string[]]$DiffPaths
    )
    $patterns = Get-SafetyConfigPatterns -YamlFile $YamlFile
    if ($patterns.Count -eq 0) { return @() }
    $regexes = foreach ($p in $patterns) { ConvertTo-SafetyConfigRegex -Pattern $p }
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $results = New-Object System.Collections.Generic.List[string]
    foreach ($path in $DiffPaths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ($seen.Contains($path)) { continue }
        foreach ($rx in $regexes) {
            if ($path -match $rx) {
                $results.Add($path) | Out-Null
                $seen.Add($path) | Out-Null
                break
            }
        }
    }
    return ,$results.ToArray()
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
        [Console]::Error.WriteLine('Safety enforcement section incomplete or missing. See template/docs/process-kit/safety-property-gate-guide.md.')
        return $false
    }
    $epLine  = $section | Where-Object { $_ -match '^Enforcement code path: ' } | Select-Object -First 1
    $npLine  = $section | Where-Object { $_ -match '^Negative-path test: ' }    | Select-Object -First 1
    $valLine = $section | Where-Object { $_ -match '^Validates' }                | Select-Object -First 1
    if (-not $epLine -or -not $npLine -or -not $valLine) {
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
        $refFile = Get-ChildItem -Path (Join-Path $RepoRoot 'docs/specs') -Filter "$refNum-*.md" -ErrorAction SilentlyContinue | Select-Object -First 1
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

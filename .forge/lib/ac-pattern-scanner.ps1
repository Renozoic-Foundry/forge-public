# FORGE AC pattern scanner (Spec 540) — PowerShell parity for ac-pattern-scanner.sh.
#
# Single pattern source (AC7) for browser-verb/deferred-AC detection, unifying
# the Spec 349 `/spec` Step 6d behavioral-AC regexes with the Spec 540
# browser-verb set. Two consumers share this one script (bash is the
# mandatory implementation; this PowerShell parity is gated on `pwsh`):
#   - `/spec` Step 6d (authoring-time nudge, non-blocking)
#   - `/close` Step 2b2 / the validator subagent Stage-1 check (close-time gate)
#
# Boundary vs Spec 403: Spec 403's live-smoke gate keys on Test-Plan keywords
# ("smoke test", "live dry-run"). This scanner keys on Acceptance-Criteria
# browser verbs and behavioral phrasing — different sections, no double-fire.
#
# Usage: pwsh ac-pattern-scanner.ps1 <spec-file> [mode]
#   mode: browser (default) | runnable (Spec 548 — shared command-detection source)
# Output: JSON on stdout —
#   browser mode (Spec 618 three-state):
#     {"section_found":true|false,"flagged_acs":[{"ac_number":N,"text":"...","pattern":"..."}]}
#     section_found:false = NO recognized AC heading; the scan read nothing (could-not-check).
#   runnable mode: {"flagged_acs":[...]} — schema unchanged (Spec 618 AC6 byte-parity).
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$SpecFile,
  [Parameter(Position = 1)]
  [string]$Mode = "browser"
)

if (-not (Test-Path -LiteralPath $SpecFile -PathType Leaf)) {
  if ($Mode -eq "runnable") {
    Write-Output '{"flagged_acs":[]}'
  }
  else {
    Write-Output '{"section_found":false,"flagged_acs":[]}'
  }
  exit 0
}

# Pattern list — must stay identical (in content and precedence order) to
# ac-pattern-scanner.sh's PATTERNS array (AC7 unification requirement).
# Spec 550: first NON-EXCLUDED match wins — an excluded weak match falls
# through to later patterns.
$Patterns = @(
  '(running|run|invoke|execute) /[a-z-]+',
  '(fresh|new) (fixture|copy|repo|project)',
  'after .+, the operator (sees|observes)',
  '\b(click|clicks|clicking)\b',
  '\b(hover|hovers|hovering)\b',
  '\b(render|renders|rendering)\b',
  '\b(show|shows|showing)\b',
  '\bvisible\b',
  '\b(display|displays|displaying)\b',
  '\b(scroll|scrolls|scrolling)\b'
)

# Spec 550 — weak patterns + exclusion contexts. Must stay identical to
# ac-pattern-scanner.sh's WEAK_PATTERNS/EXCLUSIONS arrays. "console" is
# deliberately NOT an exclusion (legitimate UI vocabulary).
$WeakPatterns = @(
  '\b(render|renders|rendering)\b',
  '\b(show|shows|showing)\b',
  '\bvisible\b',
  '\b(display|displays|displaying)\b'
)

# Spec 658 — backtick-sensitive patterns: a THIRD class, between strong and
# weak. Must stay identical to ac-pattern-scanner.sh's BACKTICK_SENSITIVE_PATTERNS
# array. Sole member is the slash-command pattern; members get the backtick-strip
# re-test ONLY, never the whole-AC $Exclusions list (adding them to $WeakPatterns
# would inherit '\bfixture(s)?\b' and silently stop flagging a genuine
# "run /close in a fresh fixture" AC — see Spec 658 Requirement 2).
$BacktickSensitivePatterns = @(
  '(running|run|invoke|execute) /[a-z-]+'
)

$Exclusions = @(
  '\bcopier\b',
  '\brender(s|ed|ing)?[ -]test',
  '\brenderer\b',
  '\bci (run|log)s?\b',
  '\bfixture(s)?\b',
  '\b(stdout|stderr|log line|log output|exit code)\b'
)

# Spec 548 — runnable-command pattern set (mode=runnable). Must stay identical
# to ac-pattern-scanner.sh's RUNNABLE_PATTERNS array. Exclusions do not apply.
$RunnablePatterns = @(
  '(bash|sh|pwsh|powershell|python[0-9]*|forge-py|npm|npx|node|copier|shellcheck|grep) [^ ]',
  '\b(validate|test)-[a-z0-9_-]+\.(sh|ps1|py)\b',
  '\b[a-z0-9_-]+\.(sh|ps1|py)\b',
  '\b(suite|suites|shellcheck|lint|linter) (pass|passes|passed|stays green|stay green|green|clean|PASS)',
  '\b(runs?|running|invoke[sd]?|execut(e|es|ed|ing)|re-?runs?) (the )?(suite|test|tests|script|fixture|linter|scanner|post-?check|helper)',
  'exit (code|status)'
)

function Test-ExclusionContext {
  param([string]$Text)
  foreach ($e in $script:Exclusions) {
    if ($Text -match "(?i)$e") { return $true }
  }
  return $false
}

# Spec 618 — strip backticked spans so a weak token matching ONLY inside `...`
# is excluded. Must stay behaviorally identical to strip_backticks in the .sh.
function Remove-BacktickSpans {
  param([string]$Text)
  return ($Text -replace '`[^`]*`', '')
}

# Spec 618 — token-scoped exclusion contexts (browser mode, weak patterns only).
# Must stay identical (in content and token binding) to has_token_exclusion in
# the .sh. NEVER add a bare `render` exclusion (genuine "renders the page/view"
# browser ACs must keep flagging).
function Test-TokenExclusion {
  param([string]$Pattern, [string]$Text)
  if ($Pattern -like '*show*') {
    if ($Text -match '(?i)\b(az|kubectl|gh|docker|git)( [a-z0-9._-]+){0,6} show(s)?\b') { return $true }
  }
  if ($Pattern -like '*visible*') {
    if ($Text -match '(?i)\bvisible\b[^.]{0,16}\boutput\b|\boutput\b[^.]{0,16}\bvisible\b') { return $true }
    if ($Text -match '(?i)\buser-visible\b[^.]{0,30}\bchange\b') { return $true }
  }
  if ($Pattern -like '*render*') {
    if ($Text -match '(?i)\bre-render(s|ed|ing)?\b|\brender (trigger|pipeline|source)s?\b') { return $true }
  }
  return $false
}

function ConvertTo-JsonEscape {
  param([string]$Text)
  # Single-quoted PowerShell strings are literal (no backslash escapes), so
  # this replaces each single backslash char with two backslash chars — the
  # JSON encoding of a backslash. (Do not "simplify" to '\\\\' — that is 4
  # literal chars in a single-quoted string, not 2.)
  $Text = $Text -replace '\\', '\\'
  $Text = $Text -replace '"', '\"'
  return $Text
}

$lines = Get-Content -LiteralPath $SpecFile
$inSection = $false
$sectionFound = $false
$acSectionLines = @()
foreach ($line in $lines) {
  # Spec 618: alternate heading names + trailing parentheticals (prefix match).
  # PowerShell -match is case-insensitive by default, so case variants are
  # covered without an explicit (?i) — the .sh needed tolower(); this side
  # needed only the alternate names (asymmetric baseline, Req 6 note).
  if ($line -match '^## (Acceptance Criteria|Definition of done)') { $inSection = $true; $sectionFound = $true; continue }
  if ($inSection -and $line -match '^## ') { $inSection = $false }
  if ($inSection) { $acSectionLines += $line }
}

$entries = New-Object System.Collections.Generic.List[string]
$acNum = $null
$acText = ""

function Invoke-Flush {
  if ($null -ne $script:acNum) {
    if ($script:Mode -eq "runnable") {
      foreach ($pat in $script:RunnablePatterns) {
        if ($script:acText -match "(?i)$pat") {
          $escapedText = ConvertTo-JsonEscape $script:acText
          $escapedPat = ConvertTo-JsonEscape $pat
          $jsonEntry = '{{"ac_number":{0},"text":"{1}","pattern":"{2}"}}' -f $script:acNum, $escapedText, $escapedPat
          $script:entries.Add($jsonEntry)
          break
        }
      }
      return
    }
    foreach ($pat in $script:Patterns) {
      if ($script:acText -match "(?i)$pat") {
        # Spec 550: excluded weak matches fall through to later patterns.
        if ($script:WeakPatterns -contains $pat) {
          if (Test-ExclusionContext $script:acText) { continue }
          # Spec 618: the weak token must match OUTSIDE backticked spans...
          $stripped = Remove-BacktickSpans $script:acText
          if (-not ($stripped -match "(?i)$pat")) { continue }
          # ...and outside its token-scoped exclusion contexts.
          if (Test-TokenExclusion $pat $stripped) { continue }
        }
        elseif ($script:BacktickSensitivePatterns -contains $pat) {
          # Spec 658: the backtick-strip re-test ONLY — no whole-AC exclusions,
          # no token-scoped exclusions. A backtick-ONLY match is the
          # quoted-command-as-data false positive and falls through to later
          # patterns; a match surviving the strip still flags.
          $stripped = Remove-BacktickSpans $script:acText
          if (-not ($stripped -match "(?i)$pat")) { continue }
        }
        $escapedText = ConvertTo-JsonEscape $script:acText
        $escapedPat = ConvertTo-JsonEscape $pat
        $jsonEntry = '{{"ac_number":{0},"text":"{1}","pattern":"{2}"}}' -f $script:acNum, $escapedText, $escapedPat
        $script:entries.Add($jsonEntry)
        break
      }
    }
  }
}

foreach ($line in $acSectionLines) {
  if ($line -match '^(\d+)\.\s+(.*)$') {
    Invoke-Flush
    $acNum = $Matches[1]
    $acText = $Matches[2]
  }
  elseif ($null -ne $acNum) {
    $trimmed = $line.Trim()
    if ($trimmed -ne "") {
      $acText = "$acText $trimmed"
    }
  }
}
Invoke-Flush

if ($Mode -eq "runnable") {
  # Spec 618 AC6: runnable-mode output schema unchanged (byte-parity for Spec 548
  # consumers) — no section_found key here.
  if ($entries.Count -eq 0) {
    Write-Output '{"flagged_acs":[]}'
  }
  else {
    Write-Output ('{{"flagged_acs":[{0}]}}' -f ($entries -join ','))
  }
}
else {
  $sfJson = if ($sectionFound) { 'true' } else { 'false' }
  if ($entries.Count -eq 0) {
    Write-Output ('{{"section_found":{0},"flagged_acs":[]}}' -f $sfJson)
  }
  else {
    Write-Output ('{{"section_found":{0},"flagged_acs":[{1}]}}' -f $sfJson, ($entries -join ','))
  }
}

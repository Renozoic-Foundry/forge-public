<#
.SYNOPSIS
  generate-sprint-prompt.ps1 — Spec 656. PowerShell twin of generate-sprint-prompt.sh.

.DESCRIPTION
  A PROMPT GENERATOR. Reads the operator-ratified autopilot loop template
  (.forge/prompts/autopilot-loop.md, Spec 528), fills its {{PLACEHOLDER}} blocks from spec
  frontmatter, prints an advisory pre-flight report, and prints the exact /loop line.

  IT NEVER LAUNCHES THE LOOP. No /implement, no /close, no push. The operator launches.
  That boundary is what makes this shippable ahead of the ADR-453 6.1 trust root; Spec 612
  owns the command-logic scope and stays blocked on it.

  CAPABILITY NEUTRALITY IS A DESIGN PROPERTY, NOT A CONTROL ENFORCED HERE. The deny-list
  fixture is a REGRESSION DETECTOR co-editable with this file. The real bound is that this
  script adds no new code-execution path.

  CONTROL-CHARACTER SANITIZATION IS LOAD-BEARING (AC12). Spec frontmatter is agent-writable
  and its values print to a live terminal; a crafted field carrying ANSI/OSC sequences could
  visually spoof the operator's pre-launch review — the one control the capability-neutral
  argument rests on. Every frontmatter-derived value goes through Get-Sanitized before it
  reaches stdout or the artifact. Do not add an output path that bypasses it.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)] [string[]] $SpecIds,
  [string] $Goal = '',
  [string] $End = '',
  [string] $Extra = '',
  [string] $ArtifactDir = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $RepoRoot

$Template = '.forge/prompts/autopilot-loop.md'
$SpecsDir = 'docs/specs'

$ids = @($SpecIds | Where-Object { $_ -match '^\d{3,}$' })
if ($ids.Count -eq 0) {
  Write-Error "generate-sprint-prompt: no spec ids given. Usage: generate-sprint-prompt.ps1 631 632 [-Goal <text>] [-End <text>] [-Extra <text>] [-ArtifactDir <dir>]"
  exit 2
}
if (-not (Test-Path $Template)) { Write-Error "generate-sprint-prompt: template missing at $Template"; exit 1 }

# --- Get-Sanitized: strip control characters except newline and tab (AC12) ------------
# .NET strings are UTF-16 code points, so this class can never split a multi-byte sequence —
# the bug the bash twin hit on its first live run is structurally impossible here. Printable
# UTF-8 (em-dashes, box drawing) is preserved on purpose.
function Get-Sanitized {
  param([AllowEmptyString()][string] $Text)
  if ([string]::IsNullOrEmpty($Text)) { return '' }
  $t = [regex]::Replace($Text, "\e\[[0-9;?]*[ -/]*[@-~]", '')          # CSI
  $t = [regex]::Replace($t,    "\e\][^\a\e]*(?:\a|\e\\)", '')          # OSC
  $t = [regex]::Replace($t,    "\e[@-Z\\-_]", '')                      # Fe escapes
  # Built from code points, not a regex class: every attempt to write an escaped character
  # class through tooling got the escapes normalised away. This form has nothing to mangle.
  $ctrl = [char[]]@(0..8 + 11 + 12 + 14..31 + 127..159)
  $t = -join ($t.ToCharArray() | Where-Object { $ctrl -notcontains $_ })
  return $t
}

function Get-FmField {
  param([string] $File, [string] $Key)
  $line = Select-String -Path $File -Pattern "^- $Key\:" -SimpleMatch:$false | Select-Object -First 1
  if (-not $line) { return '' }
  $v = $line.Line -replace "^- $Key\:\s*", ''
  $v = ($v -split '<!--')[0].TrimEnd()
  return (Get-Sanitized $v)
}

# --- Changed-files extraction (BODY content, NOT frontmatter) -------------------------
# parse_frontmatter breaks at the first '## ' heading by design and cannot reach
# ## Implementation Summary. Body-content readers are exempt from the no-second-parser
# Constraint; this mirrors safety_config_spec_files' extraction (Spec 542).
function Get-ChangedFiles {
  param([string] $File)
  $lines = Get-Content -LiteralPath $File
  $inSec = $false; $out = New-Object System.Collections.Generic.List[string]
  foreach ($l in $lines) {
    if ($l -match '^## Implementation Summary\s*$') { $inSec = $true; continue }
    if ($inSec -and $l -match '^## ') { break }
    if (-not $inSec) { continue }
    foreach ($m in [regex]::Matches($l, '`([^`]+)`')) {
      $p = $m.Groups[1].Value
      if ($p -match '[/\\]' -or $p -match '\.(md|sh|ps1|py|ya?ml|json|js|txt)$') { $out.Add($p) }
    }
  }
  return ($out | Sort-Object -Unique)
}

function Get-SpecPath { param([string] $Id) (Get-ChildItem -Path $SpecsDir -Filter "$Id-*.md" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }

if (-not $ArtifactDir) { $ArtifactDir = "tmp/evidence/sprint-run-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$TemplateSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Template).Hash.ToLower()
$GitSha = (& git rev-parse HEAD 2>$null); if (-not $GitSha) { $GitSha = 'unknown' }

$info = @{}; $preflight = New-Object System.Collections.Generic.List[string]
foreach ($id in $ids) {
  $f = Get-SpecPath $id
  if (-not $f) {
    $preflight.Add("  MISSING   spec ${id}: no file matching $SpecsDir/$id-*.md")
    $info[$id] = @{ status='unknown'; lane='unknown'; deps=''; title='(missing)'; files=@(); malformed=$true }
    continue
  }
  $titleLine = (Select-String -Path $f -Pattern '^# Spec ' | Select-Object -First 1).Line
  $title = Get-Sanitized (($titleLine -replace '^# Spec \d+ \S* ', ''))
  $cf = @(Get-ChangedFiles $f)
  $malformed = ($cf.Count -eq 0)
  if ($malformed) {
    # AC6: report it, bar it from parallel bundling — but KEEP it in the ordered list.
    $preflight.Add("  MALFORMED spec ${id}: no parseable Implementation Summary Changed-files — barred from parallel bundling (stays in the ordered list)")
  }
  if (-not (Get-FmField $f 'Consensus-Review')) { $preflight.Add("  MISSING   spec ${id}: no Consensus-Review field") }
  if (-not (Get-FmField $f 'Token-Cost'))       { $preflight.Add("  MISSING   spec ${id}: no Token-Cost field") }
  $info[$id] = @{
    status = (Get-FmField $f 'Status'); lane = (Get-FmField $f 'Change-Lane')
    deps = (Get-FmField $f 'Dependencies'); title = $title; files = $cf; malformed = $malformed
  }
}
if (& git status --porcelain 2>$null) { $preflight.Add('  DIRTY     working tree has uncommitted changes — the plan reads the tree as-is') }
if ($preflight.Count -eq 0) { $preflight.Add('  clean — no advisory conditions') }

# --- dependency-respecting order (stable topological sort) ----------------------------
$order = New-Object System.Collections.Generic.List[string]
$placed = @{}; $remaining = [System.Collections.ArrayList]@($ids); $guard = 0
while ($remaining.Count -gt 0 -and $guard -lt 100) {
  $guard++; $progress = $false; $next = [System.Collections.ArrayList]@()
  foreach ($id in $remaining) {
    $ready = $true
    foreach ($m in [regex]::Matches([string]$info[$id].deps, '\d{3}')) {
      $d = $m.Value
      if (($ids -contains $d) -and (-not $placed.ContainsKey($d))) { $ready = $false }
    }
    if ($ready) { $order.Add($id) | Out-Null; $placed[$id] = $true; $progress = $true } else { $next.Add($id) | Out-Null }
  }
  $remaining = $next
  if (-not $progress) { foreach ($id in $remaining) { $order.Add($id) | Out-Null }; break }
}

# --- parallel bundling: only declared-file-disjoint, non-malformed specs --------------
$bundles = New-Object System.Collections.Generic.List[string]; $bundled = @{}
foreach ($id in $order) {
  if ($info[$id].malformed -or $bundled.ContainsKey($id)) { continue }
  $b = @($id); $bundled[$id] = $true
  foreach ($o in $order) {
    if ($o -eq $id -or $info[$o].malformed -or $bundled.ContainsKey($o)) { continue }
    # AC5 requires ANY TWO bundle members to be disjoint. Comparing against the SEED only is
    # not sufficient — disjointness is not transitive (A∩B=∅ and A∩C=∅ says nothing about
    # B∩C). On the first live run that put 640/641/655 in one bundle despite all three
    # declaring AGENTS.md. Compare against EVERY member already accepted.
    $collides = $false
    foreach ($m in $b) {
      $ov = @(Compare-Object -ReferenceObject @($info[$m].files) -DifferenceObject @($info[$o].files) -ExcludeDifferent -IncludeEqual -ErrorAction SilentlyContinue)
      if ($ov.Count -ne 0) { $collides = $true; break }
    }
    if (-not $collides) { $b += $o; $bundled[$o] = $true }
  }
  if ($b.Count -gt 1) { $bundles.Add(($b -join ' ')) | Out-Null }
}

$osl = ''; $n = 0
foreach ($id in $order) {
  $n++
  $d = [string]$info[$id].deps
  if ([string]::IsNullOrWhiteSpace($d) -or $d -eq '—' -or $d -eq '-') { $d = 'none' }
  $osl += "$n. Spec $id — $($info[$id].title)`n"
  $osl += "   status: $($info[$id].status) | lane: $($info[$id].lane) | depends: $d`n"
  if ($info[$id].malformed) { $osl += "   NOTE: declared-file list unparseable — run sequentially, never in a parallel bundle.`n" }
}

if (-not $Goal) { $Goal = "specs $($ids -join ' ') all at implemented" }
if (-not $End)  { $End  = "specs $($ids -join ' ') all at implemented (or paused awaiting my gated input)" }

$raw = Get-Content -LiteralPath $Template -Raw
$body = ($raw -split "(?m)^---8<---\r?\n", 2)[1]
$out = [regex]::Replace($body, '\{\{RUN_GOAL.*?\}\}', [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $Goal }, 'Singleline')
$out = [regex]::Replace($out,  '\{\{ORDERED_SPEC_LIST.*?\}\}', [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $osl }, 'Singleline')
$out = [regex]::Replace($out,  '\{\{END_CONDITION.*?\}\}', [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $End }, 'Singleline')
if ($Extra) { $out = [regex]::Replace($out, '\{\{EXTRA_RULES.*?\}\}', [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $Extra }, 'Singleline') }
else        { $out = [regex]::Replace($out, '(?m)^- \{\{EXTRA_RULES.*?\}\}\r?\n', '', 'Singleline') }

$promptFile = Join-Path $ArtifactDir 'prompt.txt'
Set-Content -LiteralPath $promptFile -Value $out -Encoding utf8NoBOM
@(
  "spec-ids: $($ids -join ' ')"
  "generated: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
  "template: $Template"
  "template_sha256: $TemplateSha"
  "git_sha: $GitSha"
  "resolved_order: $($order -join ' ')"
  "parallel_bundles: $(if ($bundles.Count) { $bundles -join ' | ' } else { 'none' })"
  '--- pre-flight ---'
) + $preflight | Set-Content -LiteralPath (Join-Path $ArtifactDir 'plan.txt') -Encoding utf8NoBOM

"== Pre-flight report (ADVISORY — never blocks; exit code is always 0) =="
$preflight | ForEach-Object { $_ }
''
'== Provenance =='
"  template : $Template"
"  sha256   : $TemplateSha"
"  git HEAD : $GitSha"
"  artifact : $ArtifactDir"
''
'== Filled prompt =='
$out
''
'== Launch it yourself (this script does not) =='
"  /loop (Get-Content -Raw $promptFile)"
exit 0

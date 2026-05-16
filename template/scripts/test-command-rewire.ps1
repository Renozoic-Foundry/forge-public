# Spec 439 test harness (PowerShell parity) — verify command-body rewire to derived_state.py.
#
# Mirrors test-command-rewire.sh. See that file for AC narrative.

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $Root

$script:Fail = 0
function Fail($msg) { Write-Host "FAIL: $msg"; $script:Fail++ }
function Pass($msg) { Write-Host "PASS: $msg" }

# AC 1 — /now programmatic reads
foreach ($f in @(
    'template/.forge/commands/now.md',
    'template/.claude/commands/now.md',
    '.forge/commands/now.md',
    '.claude/commands/now.md')) {
    if (-not (Test-Path $f)) { continue }
    $hits = Select-String -Path $f -Pattern 'docs/backlog\.md' |
        Where-Object { $_.Line -notmatch 'See:' -and $_.Line -notmatch 'operator-visible' }
    if ($hits) { Fail "AC 1 — $f has non-See: reference to docs/backlog.md" }
    else { Pass "AC 1 — $f" }
}

# AC 2 — /brainstorm programmatic reads
foreach ($f in @(
    'template/.forge/commands/brainstorm.md',
    'template/.claude/commands/brainstorm.md',
    '.forge/commands/brainstorm.md',
    '.claude/commands/brainstorm.md')) {
    if (-not (Test-Path $f)) { continue }
    $hits = Select-String -Path $f -Pattern '^\s*-\s+`?docs/backlog\.md`?\s*$'
    if ($hits) { Fail "AC 2 — $f has bare bullet-list reference to docs/backlog.md" }
    else { Pass "AC 2 — $f" }
}

# AC 3 — /forge stoke has no backlog refs
foreach ($f in @(
    'template/.forge/commands/forge-stoke.md',
    'template/.claude/commands/forge-stoke.md',
    '.forge/commands/forge-stoke.md',
    '.claude/commands/forge-stoke.md')) {
    if (-not (Test-Path $f)) { continue }
    $hits = Select-String -Path $f -Pattern 'docs/backlog\.md'
    if (-not $hits) { Pass "AC 3 — $f (no references)"; continue }
    $bad = $hits | Where-Object { $_.Line -notmatch 'See:' }
    if ($bad) { Fail "AC 3 — $f has non-See: reference to docs/backlog.md" }
    else { Pass "AC 3 — $f (only See: references)" }
}

# AC 4a — helper delegates
$delegA = Select-String -Path '.forge/lib/derived_state.py' -Pattern 'from render_backlog import render'
$delegB = Select-String -Path 'template/.forge/lib/derived_state.py' -Pattern 'from render_backlog import render'
if ($delegA -and $delegB) { Pass "AC 4a — derived_state.py imports render_backlog.render" }
else { Fail "AC 4a — derived_state.py does NOT import render_backlog" }

# AC 4b — byte-identity
$helperOut = New-TemporaryFile
$renderedTmp = New-TemporaryFile
$renderedOut = New-TemporaryFile
try {
    & .forge/bin/forge-py .forge/lib/render_backlog.py --output $renderedTmp.FullName 2>$null
    & .forge/bin/forge-py .forge/lib/derived_state.py --get-backlog --format=table > $helperOut.FullName

    $flag = $false
    $rows = foreach ($line in Get-Content $renderedTmp.FullName) {
        if (-not $flag) { if ($line -match '^## Ranked backlog$') { $flag = $true }; continue }
        if ($line -match '^\|') { $line }
    }
    Set-Content -Path $renderedOut.FullName -Value $rows -NoNewline:$false

    $a = (Get-Content $helperOut.FullName -Raw) -replace "`r", ""
    $b = (Get-Content $renderedOut.FullName -Raw) -replace "`r", ""
    if ($a -eq $b) { Pass "AC 4b — helper --format=table byte-identical to rendered table rows" }
    else { Fail "AC 4b — helper output differs from rendered table rows" }
} finally {
    Remove-Item -Force $helperOut.FullName, $renderedTmp.FullName, $renderedOut.FullName -ErrorAction SilentlyContinue
}

if ($script:Fail -eq 0) {
    Write-Host ""
    Write-Host "All Spec 439 ACs PASS."
    exit 0
} else {
    Write-Host ""
    Write-Host "$script:Fail failure(s)."
    exit 1
}

# forge-doctor.ps1 — read-only distribution/provenance diagnostic (Spec 520, ADR-502 Phase 1)
#
# PowerShell twin of forge-doctor.sh — emits the SAME five advisory checks with
# equivalent output, and NEVER writes, deletes, blocks, or auto-fixes (guardrail G4).
# The only writes are its own coverage state file under .forge/state/ (gitignored).
#
#   D-PROVENANCE / D-CURRENCY / D-TAXONOMY-COVERAGE /
#   D-CONFIDENTIALITY-CONSISTENCY / D-PUBLIC-CHECKOUT
#
# GRACEFUL DEGRADATION: taxonomy map absent, sync script absent, or the print flag
# failing -> per-check advisory note, still exit 0 (consumer checkouts receive this
# script via the .forge/bin payload without the private dev-repo artifacts).
#
# Usage:
#   pwsh .forge/bin/forge-doctor.ps1              # full run — advisory, always exit 0
#   pwsh .forge/bin/forge-doctor.ps1 -Strict      # exit 1 on HIGH findings or behind>0
#   pwsh .forge/bin/forge-doctor.ps1 -Summary     # one-line currency summary (SessionStart)
#
# Env: FORGE_DOCTOR_ROOT, FORGE_DOCTOR_TAXONOMY, FORGE_DOCTOR_STATE_DIR, FORGE_DOCTOR_NO_FETCH
#
# Spec: 520

[CmdletBinding()]
param(
    [switch]$Strict,
    [switch]$Summary,
    [switch]$Verbose530
)

$ErrorActionPreference = 'SilentlyContinue'

# --- root resolution (env override -> git toplevel -> script-relative) ---
$Root = $env:FORGE_DOCTOR_ROOT
if (-not $Root) { $Root = (git rev-parse --show-toplevel 2>$null) }
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
if (-not (Test-Path $Root)) {
    Write-Host 'forge doctor: cannot resolve project root — nothing to diagnose (advisory, exit 0)'
    exit 0
}
Set-Location $Root

$Taxonomy = if ($env:FORGE_DOCTOR_TAXONOMY) { $env:FORGE_DOCTOR_TAXONOMY } else { Join-Path $Root '.forge/distribution-taxonomy.yaml' }
$StateDir = if ($env:FORGE_DOCTOR_STATE_DIR) { $env:FORGE_DOCTOR_STATE_DIR } else { Join-Path $Root '.forge/state' }
$SyncScript = Join-Path $Root 'scripts/sync-to-public.sh'
$Py = (Get-Command python3 -ErrorAction SilentlyContinue) ?? (Get-Command python -ErrorAction SilentlyContinue)

function Find-Bash {
    # Prefer Git Bash over any WSL launcher (SIG-460-A: System32\bash.exe cannot reliably
    # run Git-Bash-style scripts against Windows paths). Fall back to whatever bash exists.
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $gitRoot = Split-Path (Split-Path $git.Source -Parent) -Parent
        foreach ($cand in @((Join-Path $gitRoot 'bin\bash.exe'), 'C:\Program Files\Git\bin\bash.exe', 'C:\Program Files (x86)\Git\bin\bash.exe')) {
            if (Test-Path $cand) { return $cand }
        }
    }
    $c = Get-Command bash -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}
$Bash = Find-Bash

$script:HighCount = 0
$script:BehindCount = 0
$script:AheadCount = 0
$script:MediumCount = 0
$script:CoveragePct = ''
$script:CoverageDelta = ''
$script:ProvStatus = ''

$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("forge-doctor-" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null

# Shared taxonomy classifier — byte-identical logic to the forge-doctor.sh embedded
# helper. Parses ONLY the taxonomy map (never the publish manifest DSL; the publish
# set arrives via the shared sync-to-public.sh flag).
$ClassifierSource = @'
import re, sys

tax_path, paths_file = sys.argv[1], sys.argv[2]
rules = []          # [(compiled_regex, confidentiality)]
default_conf = "private"   # fail-closed even if the default block is malformed
in_rules = False
cur_glob = None

def glob_to_re(g):
    r = re.escape(g)
    r = r.replace(r"\*\*", "*").replace(r"\*", "*")   # collapse escaped stars
    r = r.replace("*", ".*")
    return re.compile("^" + r + "$")

for raw in open(tax_path, encoding="utf-8"):
    line = raw.rstrip("\n")
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    if s == "rules:":
        in_rules = True
        continue
    m = re.match(r'^\s*-\s*path:\s*"?([^"]+?)"?\s*$', line)
    if in_rules and m:
        cur_glob = m.group(1)
        continue
    m = re.match(r"^\s*confidentiality:\s*(\S+)", line)
    if m:
        if in_rules and cur_glob is not None:
            rules.append((glob_to_re(cur_glob), m.group(1)))
            cur_glob = None
        elif not in_rules:
            default_conf = m.group(1)

with open(paths_file, encoding="utf-8") as fh:
    for raw in fh:
        p = raw.strip().replace("\\", "/")
        if not p:
            continue
        for rx, conf in rules:
            if rx.match(p):
                print("rule\t%s\t%s" % (conf, p))
                break
        else:
            print("default\t%s\t%s" % (default_conf, p))
'@
$ClassifierPath = Join-Path $TmpDir 'classify.py'
Set-Content -Path $ClassifierPath -Value $ClassifierSource -Encoding utf8NoBOM

function Invoke-Classifier {
    param([string]$TaxPath, [string]$PathsFile)
    & $Py.Source $ClassifierPath $TaxPath $PathsFile 2>$null
}

# --- currency computation (shared by -Summary and the full D-CURRENCY section) ---
function Get-Currency {
    param([bool]$DoFetch)
    $r = [ordered]@{ Branch = ''; Upstream = ''; Ahead = $null; Behind = $null; Note = '' }
    $r.Branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    if (-not $r.Branch) { $r.Branch = '(unknown)' }
    $r.Upstream = (git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null)
    if (-not $r.Upstream) {
        $r.Note = "no upstream configured for '$($r.Branch)' — currency unknown"
        return $r
    }
    if ($DoFetch -and $env:FORGE_DOCTOR_NO_FETCH -ne '1') {
        $remote = ($r.Upstream -split '/')[0]
        git fetch --quiet $remote 2>$null
        if ($LASTEXITCODE -ne 0) { $r.Note = 'fetch failed — comparing against last-known remote refs' }
    }
    $counts = (git rev-list --left-right --count "$($r.Upstream)...HEAD" 2>$null)
    if (-not $counts) {
        $r.Note = "cannot compare against $($r.Upstream) — currency unknown"
        return $r
    }
    $parts = -split $counts
    $r.Behind = [int]$parts[0]
    $r.Ahead = [int]$parts[1]
    return $r
}

# --- Spec 530: durable JSONL history + cached last-full state (bash twin parity) ---
# mode values: full | summary | summary-verbose. provenance: pinned | unpinned | "".
# Overridable for hermetic tests (Spec 535).
$HistoryFile = if ($env:FORGE_DOCTOR_HISTORY_FILE) { $env:FORGE_DOCTOR_HISTORY_FILE } else { Join-Path $Root 'docs/sessions/doctor-history.jsonl' }
$LastFullFile = Join-Path $StateDir 'doctor-last-full.state'

function Read-CachedFull {
    $c = @{ pct=''; delta=''; high=''; medium=''; provenance='' }
    if (Test-Path -LiteralPath $LastFullFile) {
        foreach ($line in (Get-Content -LiteralPath $LastFullFile)) {
            if ($line -match '^(pct|delta|high|medium|provenance)=(.*)$') { $c[$Matches[1]] = $Matches[2] }
        }
    }
    return $c
}

function Add-HistoryRecord {
    param([string]$Mode, [string]$Ahead, [string]$Behind, [string]$Pct, [string]$Delta,
          [string]$High, [string]$Medium, [string]$Prov, [string]$Notes)
    try {
        $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $dir = Split-Path -Parent $HistoryFile
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $rec = ('{{"ts":"{0}","mode":"{1}","ahead":"{2}","behind":"{3}","coverage_pct":"{4}","coverage_delta":"{5}","high":"{6}","medium":"{7}","provenance":"{8}","notes":"{9}"}}' -f `
            $ts, $Mode, $Ahead, $Behind, $Pct, $Delta, $High, $Medium, $Prov, $Notes)
        Add-Content -LiteralPath $HistoryFile -Value $rec -ErrorAction SilentlyContinue
    } catch { }
}

try {
    if ($Summary) {
        # One-line SessionStart surface (Spec 520 R5/AC6). No fetch — fast + offline-safe.
        # Spec 530: silent unless ACTIONABLE (behind>0, cached HIGH>0, cached delta<0);
        # ahead-only stays silent; -Verbose530 preserves the always-print line.
        $c = Get-Currency -DoFetch:$false
        $cache = Read-CachedFull
        $actionable = @()
        if ($null -ne $c.Behind -and [int]$c.Behind -gt 0) {
            $actionable += "behind upstream by $($c.Behind) commit(s) — fetch/pull before starting work"
        }
        if ($cache.high -match '^[0-9]+$' -and [int]$cache.high -gt 0) {
            $actionable += "$($cache.high) HIGH consistency finding(s) at last full run"
        }
        if ($cache.delta -match '^-' -and $cache.delta -ne '-0.0') {
            $actionable += "coverage delta $($cache.delta) at last full run"
        }
        $mode = if ($Verbose530) { 'summary-verbose' } else { 'summary' }
        Add-HistoryRecord -Mode $mode -Ahead "$($c.Ahead)" -Behind "$($c.Behind)" -Pct $cache.pct `
            -Delta $cache.delta -High $cache.high -Medium $cache.medium -Prov $cache.provenance -Notes "$($c.Note)"
        if ($Verbose530) {
            if ($null -ne $c.Ahead) {
                $line = "doctor currency: ahead $($c.Ahead) / behind $($c.Behind) (vs $($c.Upstream))"
                if ($c.Behind -gt 0) { $line += ' — WARN: behind upstream, fetch/pull before starting work' }
                Write-Host $line
            } else {
                Write-Host "doctor currency: $($c.Note)"
            }
        } elseif ($actionable.Count -gt 0) {
            Write-Host ("doctor: " + ($actionable -join '; ') + " (run .forge/bin/forge-doctor.ps1 for detail)")
        }
        exit 0
    }

    Write-Host 'forge doctor — read-only distribution diagnostic (Spec 520, ADR-502 Phase 1)'
    Write-Host "root: $Root"
    Write-Host ''

    # =============================== D-PROVENANCE ===================================
    Write-Host '== D-PROVENANCE =='
    $CopierAnswers = Join-Path $Root '.copier-answers.yml'
    if (Test-Path $CopierAnswers) {
        $script:ProvStatus = 'pinned'
        $PinCommit = (Select-String -Path $CopierAnswers -Pattern '^_commit:\s*(.+)$' | Select-Object -First 1).Matches.Groups[1].Value
        $PinSrc = (Select-String -Path $CopierAnswers -Pattern '^_src_path:\s*(.+)$' | Select-Object -First 1).Matches.Groups[1].Value
        Write-Host "  pinned _commit: $(if ($PinCommit) { $PinCommit } else { '(missing)' })"
        Write-Host "  template source: $(if ($PinSrc) { $PinSrc } else { '(missing)' })"
        if (-not $PinCommit) {
            $script:ProvStatus = 'unpinned'
            Write-Host '  WARN  .copier-answers.yml carries no _commit pin — provenance unverifiable'
        } elseif ($PinSrc -and (Test-Path $PinSrc)) {
            git -C $PinSrc cat-file -e "$PinCommit^{commit}" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host '  OK    pinned _commit is reachable in the local template source'
            } else {
                Write-Host "  WARN  pinned _commit $PinCommit NOT reachable in $PinSrc — the pin names a ref the source does not have"
            }
        } else {
            Write-Host '  note  template source is remote or unavailable — reachability not verified (best-effort check)'
        }
    } else {
        Write-Host '  not a copier consumer (no .copier-answers.yml) — provenance check not applicable'
    }
    Write-Host ''

    # ================================ D-CURRENCY ====================================
    Write-Host '== D-CURRENCY =='
    $c = Get-Currency -DoFetch:$true
    Write-Host "  branch: $($c.Branch)"
    if ($null -ne $c.Ahead) {
        Write-Host "  upstream: $($c.Upstream)"
        if ($c.Note) { Write-Host "  note  $($c.Note)" }
        Write-Host "  ahead: $($c.Ahead) / behind: $($c.Behind)"
        if ($c.Behind -gt 0) {
            Write-Host "  WARN  behind upstream by $($c.Behind) commit(s) — start from a current base (fetch/pull before work)"
            $script:BehindCount = $c.Behind
            $script:AheadCount = $c.Ahead
        } else {
            Write-Host '  OK    checkout is current with its upstream'
        }
    } else {
        Write-Host "  note  $($c.Note)"
    }
    Write-Host ''

    # ============================ D-TAXONOMY-COVERAGE ===============================
    Write-Host '== D-TAXONOMY-COVERAGE =='
    $TrackedFile = Join-Path $TmpDir 'tracked.txt'
    git ls-files 2>$null | Set-Content -Path $TrackedFile -Encoding utf8NoBOM
    if (-not (Test-Path $Taxonomy)) {
        Write-Host '  note  taxonomy map not present — coverage skipped (expected on consumer checkouts; the map is a private dev-repo artifact)'
    } elseif (-not $Py) {
        Write-Host '  note  python3 not available — coverage skipped (advisory)'
    } elseif (-not (Test-Path $TrackedFile) -or (Get-Item $TrackedFile).Length -eq 0) {
        Write-Host '  note  not a git repository — coverage skipped (advisory)'
    } else {
        $RuleCount = (Select-String -Path $Taxonomy -Pattern '^\s*- path:').Count
        Write-Host "  taxonomy: $Taxonomy ($RuleCount rules)"
        $Classified = Invoke-Classifier -TaxPath $Taxonomy -PathsFile $TrackedFile
        if ($Classified) {
            $Total = @(Get-Content $TrackedFile | Where-Object { $_ -ne '' }).Count
            $Matched = @($Classified | Where-Object { $_ -like 'rule*' }).Count
            $Unclassified = $Total - $Matched
            $Pct = if ($Total -eq 0) { '0.0' } else { '{0:F1}' -f (($Matched * 100.0) / $Total) }
            $script:CoveragePct = $Pct
            Write-Host "  tracked paths: $Total; rule-classified: $Matched ($Pct%)"
            if ($Unclassified -gt 0) {
                Write-Host "  unclassified (fail-closed default: private): $Unclassified — sample:"
                $Classified | Where-Object { $_ -like 'default*' } | Select-Object -First 10 | ForEach-Object {
                    Write-Host "    - $(($_ -split "`t")[2])"
                }
            } else {
                Write-Host '  unclassified: 0 — every tracked path has an explicit rule'
            }
            $StateFile = Join-Path $StateDir 'doctor-coverage.prev'
            if (Test-Path $StateFile) {
                $PrevPct = (Get-Content $StateFile -TotalCount 1).Trim()
                $Delta = '{0:+0.0;-0.0;+0.0}' -f ([double]$Pct - [double]$PrevPct)
                $script:CoverageDelta = $Delta
                Write-Host "  coverage delta vs previous run: $Delta (prev $PrevPct%) — negative deltas are reviewed at /evolve cadence (SIG candidate)"
            } else {
                Write-Host '  coverage delta vs previous run: n/a (no previous run recorded — baseline written)'
            }
            try {
                New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
                Set-Content -Path $StateFile -Value $Pct -Encoding utf8NoBOM
            } catch {
                Write-Host "  note  could not persist coverage state under $StateDir (advisory — delta unavailable next run)"
            }
        } else {
            Write-Host '  note  taxonomy classification failed — coverage skipped (advisory)'
        }
    }
    Write-Host ''

    # ======================= D-CONFIDENTIALITY-CONSISTENCY ==========================
    Write-Host '== D-CONFIDENTIALITY-CONSISTENCY =='
    if (-not (Test-Path $SyncScript)) {
        Write-Host '  note  scripts/sync-to-public.sh not present — consistency skipped (expected on consumer checkouts; publishing happens only in the dev repo)'
    } elseif (-not (Test-Path $Taxonomy)) {
        Write-Host '  note  taxonomy map not present — consistency skipped (advisory)'
    } elseif (-not $Py) {
        Write-Host '  note  python3 not available — consistency skipped (advisory)'
    } elseif (-not $Bash) {
        Write-Host '  note  bash not available — cannot invoke sync-to-public.sh --print-public-set; consistency skipped (advisory)'
    } else {
        $PubsetFile = Join-Path $TmpDir 'pubset.txt'
        # Relative script path on purpose: the resolved bash may be WSL bash, which cannot
        # open absolute Windows paths (cwd is already $Root). Success is judged by output —
        # a failing flag emits nothing on stdout (fail-closed aborts go to stderr).
        & $Bash 'scripts/sync-to-public.sh' --print-public-set 2>$null | Set-Content -Path $PubsetFile -Encoding utf8NoBOM
        $PubsetOk = (Test-Path $PubsetFile) -and ((Get-Item $PubsetFile).Length -gt 0)
        if (-not $PubsetOk) {
            Write-Host '  note  sync-to-public.sh --print-public-set failed — consistency skipped (advisory)'
        } else {
            $PubTotal = @(Get-Content $PubsetFile | Where-Object { $_ -ne '' }).Count
            Write-Host "  publish-reachable set: $PubTotal path(s) (single source: sync-to-public.sh --print-public-set)"
            $PubClass = Invoke-Classifier -TaxPath $Taxonomy -PathsFile $PubsetFile
            if ($PubClass) {
                foreach ($line in $PubClass) {
                    $parts = $line -split "`t"
                    if ($parts[0] -eq 'rule' -and ($parts[1] -eq 'private' -or $parts[1] -eq 'customer')) {
                        Write-Host "  HIGH  $($parts[2]) — classified $($parts[1]) but publish-reachable"
                        $script:HighCount++
                    }
                }
                $DefLines = @($PubClass | Where-Object { $_ -like 'default*' })
                if ($DefLines.Count -gt 0) {
                    $script:MediumCount += $DefLines.Count
                    Write-Host "  MEDIUM  $($DefLines.Count) publish-reachable path(s) have no explicit taxonomy rule (fail-closed default: private) — sample:"
                    $DefLines | Select-Object -First 5 | ForEach-Object { Write-Host "    - $(($_ -split "`t")[2])" }
                }
                if ($script:HighCount -eq 0) {
                    Write-Host '  OK    no private/customer-classified path is publish-reachable (HIGH findings: 0)'
                } else {
                    Write-Host "  HIGH findings: $($script:HighCount) — a private/customer path would ship; fix the manifest disposition or the classification"
                }
            } else {
                Write-Host '  note  taxonomy classification failed — consistency skipped (advisory)'
            }
        }
    }
    Write-Host ''

    # ============================== D-PUBLIC-CHECKOUT ===============================
    Write-Host '== D-PUBLIC-CHECKOUT =='
    $PubDir = Join-Path $Root '../forge-public'
    $PubIsRepo = $false
    if (Test-Path $PubDir) {
        git -C $PubDir rev-parse --git-dir 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $PubIsRepo = $true }
    }
    if ($PubIsRepo) {
        $PubBranch = (git -C $PubDir rev-parse --abbrev-ref HEAD 2>$null)
        Write-Host "  sibling checkout: $PubDir"
        Write-Host "  branch: $PubBranch"
        if ($PubBranch -ne 'main') {
            Write-Host '  WARN  public checkout is not on main (detached or feature branch) — sync targets main'
        }
        $PubCounts = (git -C $PubDir rev-list --left-right --count '@{upstream}...HEAD' 2>$null)
        if ($PubCounts) {
            $pp = -split $PubCounts
            Write-Host "  ahead: $($pp[1]) / behind: $($pp[0]) (vs its upstream, last-known refs)"
        } else {
            Write-Host '  note  no upstream comparison available (best-effort check)'
        }
    } else {
        Write-Host '  note  no sibling forge-public checkout — skipped (optional, best-effort check)'
    }
    Write-Host ''

    # =============================== fixed footer ===================================
    Write-Host 'advisory detector — enforcement is public-manifest.yaml + validate-public-docs.sh/check-outgoing-identity.sh gates'

    # --- Spec 530: persist last-full state (read by -Summary) + history record ------
    try {
        if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
        @(
            "pct=$($script:CoveragePct)"
            "delta=$($script:CoverageDelta)"
            "high=$($script:HighCount)"
            "medium=$($script:MediumCount)"
            "provenance=$($script:ProvStatus)"
        ) | Set-Content -LiteralPath $LastFullFile -ErrorAction SilentlyContinue
    } catch { }
    Add-HistoryRecord -Mode 'full' -Ahead "$($script:AheadCount)" -Behind "$($script:BehindCount)" `
        -Pct "$($script:CoveragePct)" -Delta "$($script:CoverageDelta)" -High "$($script:HighCount)" `
        -Medium "$($script:MediumCount)" -Prov "$($script:ProvStatus)" -Notes ''

    if ($Strict -and ($script:HighCount -gt 0 -or $script:BehindCount -gt 0)) {
        exit 1
    }
    exit 0
} finally {
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}

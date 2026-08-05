# FORGE /parallel worktree anti-forking audit (Spec 622) — PowerShell parity for
# parallel-worktree-audit.sh. Advisory, never blocking; ALWAYS exits 0.
# Classification semantics must stay identical to the .sh (attribution-not-exclusion;
# persistent unexplained-preexisting advisory; aggregate line ONLY for preexisting
# out-of-namespace paths; a current-run foreign worktree is reported individually in
# ANY namespace; main identified by path comparison, never porcelain ordering).
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$BatchId,
  [Parameter(Position = 1)]
  [string]$RepoRoot = ""
)

$ErrorActionPreference = 'SilentlyContinue'

if ($RepoRoot -eq "") {
  $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..' '..')).Path
}

function Get-Norm([string]$p) {
  try { return [System.IO.Path]::GetFullPath($p).TrimEnd('\','/').ToLowerInvariant() } catch { return $p.ToLowerInvariant() }
}

$porcelain = git -C $RepoRoot worktree list --porcelain 2>$null
$mainPath = git -C $RepoRoot rev-parse --show-toplevel 2>$null

$current = @()
foreach ($line in ($porcelain -split "`n")) {
  $t = $line.Trim()
  if ($t.StartsWith("worktree ")) { $current += $t.Substring(9) }
}

$mainN = if ($mainPath) { Get-Norm $mainPath } else { "" }
$namespace = if ($mainPath) { Get-Norm (Join-Path $mainPath ".worktrees") } else { "" }

$stateDir = Join-Path $RepoRoot ".forge/state"
$own = $null
$ownPaths = @{}
$siblings = @()  # objects: BatchId, Preserved, Paths(hashtable)
foreach ($f in (Get-ChildItem -LiteralPath $stateDir -Filter "parallel-created-worktrees-*.json" -File -ErrorAction SilentlyContinue)) {
  try { $data = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json }
  catch { Write-Output "warning: unreadable allowlist file $($f.Name) — ignored"; continue }
  $paths = @{}
  foreach ($p in @($data.worktrees)) { if ($p) { $paths[(Get-Norm $p)] = $true } }
  if ("$($data.batch_id)" -eq $BatchId) { $own = $data; $ownPaths = $paths }
  else { $siblings += [pscustomobject]@{ BatchId = "$($data.batch_id)"; Preserved = [bool]$data.preserved; Paths = $paths } }
}

if ($null -eq $own) {
  Write-Output "warning: no allowlist file for batch $BatchId — audit skipped (file missing or already cleaned)"
  exit 0
}

$preexisting = @{}
foreach ($p in @($own.preexisting)) { if ($p) { $preexisting[(Get-Norm $p)] = $true } }
$unionDeclared = @{}
foreach ($k in $ownPaths.Keys) { $unionDeclared[$k] = $true }
foreach ($s in $siblings) { foreach ($k in $s.Paths.Keys) { $unionDeclared[$k] = $true } }

$aggregate = @()
foreach ($p in $current) {
  $pn = Get-Norm $p
  if ($pn -eq $mainN) { continue }
  if ($ownPaths.ContainsKey($pn)) { continue }
  if ($preexisting.ContainsKey($pn)) {
    if ($unionDeclared.ContainsKey($pn)) { continue }
    if ($namespace -ne "" -and $pn.StartsWith($namespace + [System.IO.Path]::DirectorySeparatorChar)) {
      Write-Output "unexplained pre-existing worktree: $p — not created by any recorded /parallel batch; inspect or remove"
    }
    else { $aggregate += $p }
    continue
  }
  $attributed = $false
  foreach ($s in $siblings) {
    if ($s.Paths.ContainsKey($pn)) {
      $state = if ($s.Preserved) { "preserved" } else { "in-progress" }
      Write-Output "attributed: $p — declared by batch $($s.BatchId) ($state)"
      $attributed = $true
      break
    }
  }
  if (-not $attributed) {
    Write-Output "ADVISORY: foreign worktree $p was not created by this /parallel run — inspect for out-of-scope changes, then remove with 'git worktree remove $p'"
  }
}

if ($aggregate.Count -gt 0) {
  Write-Output ("note: {0} worktree(s) outside /parallel jurisdiction (harness/other): {1}" -f $aggregate.Count, ($aggregate -join ", "))
}

foreach ($s in $siblings) {
  $state = if ($s.Preserved) { "preserved worktrees remain" } else { "possibly stale from a dead or in-progress run" }
  Write-Output "warning: allowlist from batch $($s.BatchId) still present ($state) — its declared paths are attributed above, never silently excluded"
}

exit 0

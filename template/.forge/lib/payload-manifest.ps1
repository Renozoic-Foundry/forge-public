# FORGE plugin payload manifest builder — PowerShell parity (Spec 488, R12).
#
# Produces output BYTE-IDENTICAL to .forge/lib/payload-manifest.sh for the same payload:
#   one "<sha256>  <relpath>" line per payload file (two spaces), ordinal-sorted by relpath,
#   LF line endings, trailing LF. CR bytes are stripped before hashing (R3 CRLF canonicalization),
#   so bash and PowerShell — and LF vs CRLF checkouts — all yield the same manifest.
#
# MIGRATION (Spec 508): Get-ForgeManifest now applies the PAYLOAD_EXCLUDE set at the
# algorithm level, changing the signed-manifest contract — a payload manifest signed BEFORE
# Spec 508 will FAIL verification against this builder (the file set differs) and must be
# RE-SIGNED. That failure is by design, not corruption. See docs/process-kit/sync-runbook.md
# § Signed-manifest migration (Spec 508).
# forge:path-literal-ok (comment)
#
# Usage:
#   . ./payload-manifest.ps1 ; Get-ForgeManifest -Root <dir>   # returns the manifest string
#   pwsh payload-manifest.ps1 <root>                            # prints the manifest
Set-StrictMode -Version Latest

$script:ForgePayloadDirs = @(
  '.claude/commands','.claude/agents','.claude/skills','.claude-plugin',
  '.forge/bin','.forge/lib','.forge/templates','.forge/modules','.forge/adapters'
)
# Lockstep mirror of PAYLOAD_EXCLUDE in payload-manifest.sh (VALUE owned by Spec 506;
# applied inside the builder by Spec 508). Bare entries match a whole path segment;
# "*.ext" entries match the basename only.
$script:ForgePayloadExclude = @('tests','autonomy-test','__pycache__','*.pyc')
$script:ForgeManifestRel    = '.claude-plugin/payload-manifest.txt'
$script:ForgeManifestSigRel = '.claude-plugin/payload-manifest.txt.minisig'

# PINNED exclusion predicate (Spec 508) — the ONE PowerShell definition, matching the bash
# forge_manifest_excluded byte-for-byte in behavior: segment-anchored bare names
# ("tests" excludes "a/tests/f" but NOT "contests/f" or "mytests.sh"), case-sensitive
# ordinal matching (bash `case` is case-sensitive), basename-only "*.ext" globs.
function Test-ForgeManifestExcluded {
  param([string]$Rel)
  foreach ($pat in $script:ForgePayloadExclude) {
    if ($pat.StartsWith('*.')) {
      $base = $Rel.Substring($Rel.LastIndexOf('/') + 1)
      if ($base.EndsWith($pat.Substring(1), [System.StringComparison]::Ordinal)) { return $true }
    } elseif (("/$Rel/").Contains("/$pat/")) {
      return $true
    }
  }
  return $false
}

function Get-ForgeFileHash {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  # Strip CR (0x0D) so CRLF and LF checkouts hash identically (matches `tr -d '\r'`).
  if ($bytes -contains 13) { $bytes = [byte[]]@($bytes | Where-Object { $_ -ne 13 }) }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
  -join ($hash | ForEach-Object { $_.ToString('x2') })
}

function Get-ForgeManifest {
  param([string]$Root = $(if ($env:FORGE_ASSET_ROOT) { $env:FORGE_ASSET_ROOT } else { (Get-Location).Path }))
  $Root = ($Root -replace '\\','/').TrimEnd('/')
  if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "payload-manifest: root not found: $Root" }

  $lines = New-Object System.Collections.Generic.List[string]
  $seen = 0
  foreach ($d in $script:ForgePayloadDirs) {
    $dir = "$Root/$d"
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Recurse -File) {
      $seen++
      $rel = ($f.FullName -replace '\\','/')
      $rel = $rel.Substring($Root.Length).TrimStart('/')
      if ($rel -eq $script:ForgeManifestRel -or $rel -eq $script:ForgeManifestSigRel) { continue }
      # Apply the exclusion set at the algorithm level (Spec 508) BEFORE hashing, so
      # excluded paths never enter the signed manifest.
      if (Test-ForgeManifestExcluded $rel) { continue }
      $lines.Add(('{0}  {1}' -f (Get-ForgeFileHash $f.FullName), $rel))
    }
  }
  if ($seen -eq 0)        { throw "payload-manifest: no payload files under $Root" }
  # Runtime count invariant (Spec 508, CISO hardening): fail closed rather than emit an
  # empty manifest after exclusion filtering (mirrors the bash builder).
  if ($lines.Count -eq 0) { throw "payload-manifest: no payload files under $Root after exclusions (fail-closed)" }
  # Ordinal (byte-order) sort by relpath to match `LC_ALL=C sort -k2`. Each line is
  # "<64hex>  <relpath>"; the relpath starts after the first double-space.
  $arr = $lines.ToArray()
  [System.Array]::Sort($arr, [System.Comparison[string]]{
    param($a, $b)
    [string]::CompareOrdinal($a.Substring($a.IndexOf('  ') + 2), $b.Substring($b.IndexOf('  ') + 2))
  })
  # Build with explicit LF + trailing LF (no BOM, no CRLF) so it matches the bash output byte-for-byte.
  ($arr -join "`n") + "`n"
}

if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.\s') {
  $r = if ($args.Count -ge 1) { $args[0] } else { '' }
  if ($r) { [Console]::Out.Write((Get-ForgeManifest -Root $r)) }
  else    { [Console]::Out.Write((Get-ForgeManifest)) }
}

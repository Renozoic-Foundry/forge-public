# FORGE plugin payload manifest builder — PowerShell parity (Spec 488, R12).
#
# Produces output BYTE-IDENTICAL to .forge/lib/payload-manifest.sh for the same payload:
#   one "<sha256>  <relpath>" line per payload file (two spaces), ordinal-sorted by relpath,
#   LF line endings, trailing LF. CR bytes are stripped before hashing (R3 CRLF canonicalization),
#   so bash and PowerShell — and LF vs CRLF checkouts — all yield the same manifest.
#
# Usage:
#   . ./payload-manifest.ps1 ; Get-ForgeManifest -Root <dir>   # returns the manifest string
#   pwsh payload-manifest.ps1 <root>                            # prints the manifest
Set-StrictMode -Version Latest

$script:ForgePayloadDirs = @(
  '.claude/commands','.claude/agents','.claude/skills','.claude-plugin',
  '.forge/bin','.forge/lib','.forge/templates','.forge/modules','.forge/adapters'
)
$script:ForgeManifestRel    = '.claude-plugin/payload-manifest.txt'
$script:ForgeManifestSigRel = '.claude-plugin/payload-manifest.txt.minisig'

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
  foreach ($d in $script:ForgePayloadDirs) {
    $dir = "$Root/$d"
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Recurse -File) {
      $rel = ($f.FullName -replace '\\','/')
      $rel = $rel.Substring($Root.Length).TrimStart('/')
      if ($rel -eq $script:ForgeManifestRel -or $rel -eq $script:ForgeManifestSigRel) { continue }
      $lines.Add(('{0}  {1}' -f (Get-ForgeFileHash $f.FullName), $rel))
    }
  }
  if ($lines.Count -eq 0) { throw "payload-manifest: no payload files under $Root" }
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

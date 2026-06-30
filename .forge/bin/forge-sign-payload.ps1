# FORGE plugin payload signing — PowerShell parity (Spec 488, R12).
# Mirrors forge-sign-payload.sh: builds the canonical manifest, writes it into the payload
# (LF, no BOM — byte-identical to the bash builder), and produces a minisign detached
# signature with a signed `tier=/version=` trusted comment. FAIL-CLOSED (R8): on any failure
# the partial manifest/sig are removed and the script exits non-zero.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Tier,
  [Parameter(Mandatory)][string]$Version,
  [Parameter(Mandatory)][string]$Key,
  [string]$Root,
  [string]$PasswordFile
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '../lib/payload-manifest.ps1')

if (-not (Get-Command minisign -ErrorAction SilentlyContinue)) {
  Write-Error 'forge-sign-payload: minisign not found — cannot sign (fail-closed)'; exit 3
}
if (-not $Root) { $Root = if ($env:FORGE_ASSET_ROOT) { $env:FORGE_ASSET_ROOT } else { (Get-Location).Path } }
$Root = ($Root -replace '\\','/').TrimEnd('/')
if (-not (Test-Path -LiteralPath $Key -PathType Leaf)) { Write-Error "forge-sign-payload: secret key not found: $Key"; exit 3 }

$manifest = "$Root/.claude-plugin/payload-manifest.txt"
$sig      = "$Root/.claude-plugin/payload-manifest.txt.minisig"

function Remove-Partial { foreach ($p in @($manifest,$sig)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } } }

try {
  $content = Get-ForgeManifest -Root $Root
  if ([string]::IsNullOrEmpty($content)) { throw 'empty manifest' }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifest) | Out-Null
  [System.IO.File]::WriteAllText($manifest, $content, (New-Object System.Text.UTF8Encoding($false)))
} catch {
  Remove-Partial; Write-Error "forge-sign-payload: manifest build failed (fail-closed): $_"; exit 4
}

$trusted = "tier=$Tier version=$Version"
try {
  if ($PasswordFile) {
    Get-Content -Raw -LiteralPath $PasswordFile | & minisign -S -s $Key -m $manifest -t $trusted -x $sig
  } else {
    '' | & minisign -S -s $Key -m $manifest -t $trusted -x $sig
  }
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sig)) { throw "minisign exit $LASTEXITCODE" }
} catch {
  Remove-Partial; Write-Error "forge-sign-payload: signing FAILED — removed partial manifest/sig (fail-closed): $_"; exit 5
}

$n = (Get-Content -LiteralPath $manifest).Count
Write-Output "forge-sign-payload: signed $n payload files (tier=$Tier version=$Version)"
Write-Output "  manifest:  $manifest"
Write-Output "  signature: $sig"

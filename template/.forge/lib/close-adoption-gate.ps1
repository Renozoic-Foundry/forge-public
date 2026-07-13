# FORGE close adoption-gate helpers — Spec 402 library (PowerShell parity).
# Sourceable: pure functions, no main execution.
#
# Closes the build-without-adopt failure mode (see close-adoption-gate.sh header).
#
# Public functions:
#   Get-AdoptionFrontmatterFields -SpecFile <path>   -> string[]
#   Get-AdoptionArtifactPaths     -SpecFile <path>   -> string[]
#   Get-AdoptionConfigBlocks      -SpecFile <path>   -> string[]
#   Test-AdoptionFollowup         -SpecFile <path> -RepoRoot <path> -> bool
#   Get-AdoptionConsumerCount     -Declaration <s> -RepoRoot <path> -SpecFile <path> -> int
#   Invoke-AdoptionGateCheck      -SpecFile <path> -RepoRoot <path> -> bool (writes GATE line)

$script:AdoptionKnownFields = @(
  'Status','Change-Lane','Priority-Score','Approved-SHA','Trigger','Dependencies',
  'Consensus-Review','Consensus-Close-SHA','Consensus-Exempt','Consensus-Status',
  'Provisional-Until','Owner','Author','Reviewer','Approver','Implementation owner',
  'Last updated','valid-until','Supersedes','Lane-B-Sealed','DA-Reviewed','DA-Decision',
  'DA-Encoded-Via','DA-Verification','Safety-Override','Spec-vs-HEAD-Exempt',
  'Enforcement-Layers','Gate-Mediation-Exempt','Follow-up adoption spec',
  'Consensus-Exempt-Reason'
)

function Test-AdoptionKnownField {
  param([string]$Candidate)
  return ($script:AdoptionKnownFields -contains $Candidate)
}

# Return $true if the spec is the adoption-gate's own defining spec (Spec 402),
# which names tokens definitionally (in its ACs as examples), not as shipped
# machinery — self-excluded, mirroring the lib/tests/guide exclusion.
function Test-AdoptionDefiningSpec {
  param([string]$SpecFile)
  return ((Split-Path -Leaf $SpecFile) -like '402-*.md')
}

# Extract the body section between `## <heading>` and the next `## `.
function Get-AdoptionSection {
  param([string]$SpecFile, [string]$Heading)
  if (-not (Test-Path -LiteralPath $SpecFile -PathType Leaf)) { return @() }
  $h = "## $Heading"
  $p = $false
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($line in (Get-Content -LiteralPath $SpecFile)) {
    if ($line -eq $h) { $p = $true; continue }
    if ($line -match '^## ') { $p = $false }
    if ($p) { $out.Add($line) | Out-Null }
  }
  return ,$out.ToArray()
}

function Get-AdoptionDeclBody {
  param([string]$SpecFile)
  $b = @()
  $b += Get-AdoptionSection -SpecFile $SpecFile -Heading 'Scope'
  $b += Get-AdoptionSection -SpecFile $SpecFile -Heading 'Requirements'
  $b += Get-AdoptionSection -SpecFile $SpecFile -Heading 'Acceptance Criteria'
  return ,$b
}

function Get-AdoptionFrontmatterFields {
  param([string]$SpecFile)
  if (-not (Test-Path -LiteralPath $SpecFile -PathType Leaf)) { return @() }
  if (Test-AdoptionDefiningSpec $SpecFile) { return @() }
  $found = New-Object System.Collections.Generic.HashSet[string]
  foreach ($line in (Get-AdoptionDeclBody -SpecFile $SpecFile)) {
    # Precision rule (Spec 536 — SIG-509-TRUST-01): backticked OR line-anchored only;
    # bare mid-prose Word-Word: phrases are prose, not declarations.
    foreach ($m in [regex]::Matches($line, '`([A-Z][A-Za-z]+(-[A-Za-z]+)+):')) {
      $field = $m.Groups[1].Value
      if (Test-AdoptionKnownField $field) { continue }
      [void]$found.Add($field)
    }
    if ($line -match '^\s*-?\s*([A-Z][A-Za-z]+(-[A-Za-z]+)+):') {
      $field = $Matches[1]
      if (-not (Test-AdoptionKnownField $field)) { [void]$found.Add($field) }
    }
  }
  return ,(@($found) | Sort-Object)
}

function Get-AdoptionArtifactPaths {
  param([string]$SpecFile)
  if (-not (Test-Path -LiteralPath $SpecFile -PathType Leaf)) { return @() }
  if (Test-AdoptionDefiningSpec $SpecFile) { return @() }
  $found = New-Object System.Collections.Generic.HashSet[string]
  foreach ($line in (Get-AdoptionDeclBody -SpecFile $SpecFile)) {
    foreach ($m in [regex]::Matches($line, '`[A-Za-z0-9_./-]+\*[A-Za-z0-9_./*-]*\.(md|json|jsonl|yaml|yml|txt|csv)`')) {
      $p = $m.Value.Trim('`')
      # Double-glob `**` patterns are pattern-class descriptions, not outputs.
      if ($p -like '*`**`*' -or $p.Contains('**')) { continue }
      [void]$found.Add($p)
    }
  }
  return ,(@($found) | Sort-Object)
}

function Get-AdoptionConfigBlocks {
  param([string]$SpecFile)
  if (-not (Test-Path -LiteralPath $SpecFile -PathType Leaf)) { return @() }
  if (Test-AdoptionDefiningSpec $SpecFile) { return @() }
  $found = New-Object System.Collections.Generic.HashSet[string]
  foreach ($line in (Get-AdoptionDeclBody -SpecFile $SpecFile)) {
    foreach ($m in [regex]::Matches($line, '\b(forge|multi_agent)\.[a-z_]+(\.[a-z_]+)*')) {
      [void]$found.Add($m.Value)
    }
  }
  return ,(@($found) | Sort-Object)
}

function Test-AdoptionFollowup {
  param([string]$SpecFile, [string]$RepoRoot = '.')
  if (-not (Test-Path -LiteralPath $SpecFile -PathType Leaf)) { return $false }
  $line = (Get-Content -LiteralPath $SpecFile | Where-Object { $_ -imatch '^- ?Follow-up adoption spec:' } | Select-Object -First 1)
  if (-not $line) { return $false }
  $m = [regex]::Match($line, '[0-9]{3}')
  if (-not $m.Success) {
    [Console]::Error.WriteLine('Follow-up adoption spec field present but no NNN reference parsed.')
    return $false
  }
  $ref = $m.Value
  $hit = Get-ChildItem -Path (Join-Path $RepoRoot 'docs/specs') -Filter "$ref-*.md" -ErrorAction SilentlyContinue
  if (-not $hit) {
    [Console]::Error.WriteLine("Follow-up adoption spec $ref referenced but no such spec exists.")
    return $false
  }
  return $true
}

function Get-AdoptionConsumerCount {
  param([string]$Declaration, [string]$RepoRoot = '.', [string]$SpecFile)
  $count = 0
  $exts = @('*.md','*.json','*.jsonl','*.yaml','*.yml','*.jinja','*.sh','*.ps1','*.py')
  $specFull = (Resolve-Path -LiteralPath $SpecFile -ErrorAction SilentlyContinue).Path
  $files = Get-ChildItem -Path $RepoRoot -Recurse -File -Include $exts -ErrorAction SilentlyContinue
  foreach ($file in $files) {
    if ($file.Name -like 'close-adoption-gate.*') { continue }
    if ($file.Name -like 'test-spec-402-*') { continue }
    if ($file.Name -eq 'close-adoption-gate-guide.md') { continue }
    if ($specFull -and $file.FullName -eq $specFull) { continue }
    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -and $content.Contains($Declaration)) { $count++ }
  }
  # Originating-spec-as-consumer: field populated in its own frontmatter.
  if (Test-Path -LiteralPath $SpecFile -PathType Leaf) {
    $fm = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-Content -LiteralPath $SpecFile)) {
      if ($line -match '^## ') { break }
      $fm.Add($line) | Out-Null
    }
    if (($fm -join "`n") -match ("(?m)^- ?" + [regex]::Escape($Declaration) + ":")) { $count++ }
  }
  return $count
}

function Invoke-AdoptionGateCheck {
  param([string]$SpecFile, [string]$RepoRoot = '.')
  if (-not (Test-Path -LiteralPath $SpecFile -PathType Leaf)) {
    Write-Output "GATE [close-adoption]: FAIL — spec file not found: $SpecFile"
    return $false
  }
  if (Test-AdoptionFollowup -SpecFile $SpecFile -RepoRoot $RepoRoot) {
    Write-Output 'GATE [close-adoption]: PASS — adoption deferred via Follow-up adoption spec.'
    return $true
  }
  $declarations = @()
  $declarations += Get-AdoptionFrontmatterFields -SpecFile $SpecFile
  $declarations += Get-AdoptionArtifactPaths -SpecFile $SpecFile
  $declarations += Get-AdoptionConfigBlocks -SpecFile $SpecFile
  $declarations = @($declarations | Where-Object { $_ })

  if ($declarations.Count -eq 0) {
    Write-Output 'GATE [close-adoption]: PASS — no new artifact/field/config declarations detected.'
    return $true
  }

  $unadopted = @()
  foreach ($d in $declarations) {
    $n = Get-AdoptionConsumerCount -Declaration $d -RepoRoot $RepoRoot -SpecFile $SpecFile
    if ($n -lt 1) { $unadopted += $d }
  }

  if ($unadopted.Count -eq 0) {
    Write-Output "GATE [close-adoption]: PASS — all $($declarations.Count) declaration(s) have >=1 consumer."
    return $true
  }

  Write-Output ("GATE [close-adoption]: FAIL — $($unadopted.Count) declaration(s) shipped without a consumer: " + ($unadopted -join ', '))
  [Console]::Error.WriteLine('Remediation: (a) exercise the declaration (the originating spec body counts — populate the field/path/config in this spec or a consuming file), or (b) add `Follow-up adoption spec: NNN` to the spec frontmatter naming the successor that owns adoption.')
  return $false
}

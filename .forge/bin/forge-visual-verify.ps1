# FORGE render-time visual-verification fixture (Spec 545) — PowerShell equivalent
#
# Given an HTML/visual artifact path, walks the operator through a render-time
# visual check (open the artifact in the render target, confirm layout/content/
# theme, record the outcome) and writes a manifest entry in the SAME evidence
# convention as Spec 093/540 browser evidence:
#   tmp/evidence/SPEC-NNN-browser-YYYYMMDD/manifest.json
# There is exactly one manifest family — this fixture does not invent a second
# convention. See docs/process-kit/human-validation-runbook.md section H.
#
# Usage:
#   forge-visual-verify.ps1 <spec-number> <artifact-path> [options]
#
# Options:
#   -Result pass|fail       Record outcome without prompting (non-interactive / CI use)
#   -Notes "<text>"         Notes to attach to the recorded step (default: none)
#   -EvidenceDir <path>     Override evidence output directory

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$SpecNum,

    [Parameter(Position=1, Mandatory=$true)]
    [string]$ArtifactPath,

    [string]$Result = "",
    [string]$Notes = "",
    [string]$EvidenceDir = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ArtifactPath -PathType Leaf)) {
    Write-Error "Artifact not found: $ArtifactPath"
    exit 1
}

$SpecDisplay = $SpecNum.PadLeft(3, '0')

if (-not $EvidenceDir) {
    $DateStamp = Get-Date -Format "yyyyMMdd"
    $EvidenceDir = Join-Path "tmp" "evidence" "SPEC-${SpecDisplay}-browser-${DateStamp}"
}
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null

Write-Host "FORGE render-time visual verification — Spec $SpecDisplay"
Write-Host "Artifact: $ArtifactPath"
Write-Host "Evidence dir: $EvidenceDir"

if (-not $Result) {
    Write-Host ""
    Write-Host "Open the artifact in the render target (browser) and confirm:"
    Write-Host "  1. Layout renders as expected (no broken CSS/overflow)"
    Write-Host "  2. Content matches the spec's expected copy/data"
    Write-Host "  3. Theme (light/dark) renders correctly if applicable"
    $ans = Read-Host "Did the artifact pass the visual check? (y/n)"
    if ($ans -match '^[Yy]') {
        $Result = "pass"
    } else {
        $Result = "fail"
    }
    $Notes = Read-Host "Notes (optional)"
}

if ($Result -ne "pass" -and $Result -ne "fail") {
    Write-Error "-Result must be 'pass' or 'fail', got: $Result"
    exit 1
}

$PassedBool = ($Result -eq "pass")
$Now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$Total = 1
$Passed = if ($PassedBool) { 1 } else { 0 }
$Failed = if ($PassedBool) { 0 } else { 1 }

$manifestObj = [ordered]@{
    spec      = $SpecDisplay
    startTime = $Now
    endTime   = $Now
    steps     = @(
        [ordered]@{
            index      = 0
            action     = "render-time visual verification"
            artifact   = $ArtifactPath
            assessment = [ordered]@{
                passed = $PassedBool
                notes  = $Notes
            }
        }
    )
    summary   = [ordered]@{
        total    = $Total
        passed   = $Passed
        failed   = $Failed
        warnings = 0
    }
    videoPath = $null
}

$ManifestPath = Join-Path $EvidenceDir "manifest.json"
$manifestObj | ConvertTo-Json -Depth 6 | Set-Content -Path $ManifestPath -Encoding utf8

$SummaryPath = Join-Path $EvidenceDir "summary.md"
$summaryLines = @(
    "# Visual Evidence Summary — Spec $SpecDisplay",
    "",
    "- Artifact: $ArtifactPath",
    "- Results: $Passed/$Total passed"
)
if ($Failed -gt 0) {
    $summaryLines += "  ($Failed failed)"
}
$summaryLines += "- Notes: $(if ($Notes) { $Notes } else { 'none' })"
$summaryLines -join "`n" | Set-Content -Path $SummaryPath -Encoding utf8

Write-Host ""
Write-Host "Manifest: $ManifestPath"
Write-Host "Summary: $SummaryPath"

if ($Result -eq "fail") {
    exit 1
}
exit 0

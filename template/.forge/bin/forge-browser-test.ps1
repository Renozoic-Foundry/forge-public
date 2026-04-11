# FORGE Browser Test Runner — PowerShell equivalent
# Usage: forge-browser-test.ps1 <spec-number> [options]
#
# Options:
#   -Url <base-url>        Application URL (default: http://localhost:3000)
#   -Headed                Run browser in headed mode
#   -NoVideo               Disable video recording
#   -Runner <name>         Force "puppeteer" or "playwright"
#   -Browser <type>        Browser: chromium, firefox, webkit (Playwright only)
#   -TestFile <path>       Path to test script
#   -EvidenceDir <path>    Override evidence output directory

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$SpecNum,

    [string]$Url = "http://localhost:3000",
    [switch]$Headed,
    [switch]$NoVideo,
    [string]$Runner = "",
    [string]$Browser = "chromium",
    [string]$TestFile = "",
    [string]$EvidenceDir = ""
)

$ErrorActionPreference = "Stop"

$ForgeDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ProjectDir = Split-Path -Parent $ForgeDir

# Normalize spec number
$SpecDisplay = $SpecNum.PadLeft(3, '0')

# Set evidence directory
if (-not $EvidenceDir) {
    $DateStamp = Get-Date -Format "yyyyMMdd"
    $EvidenceDir = Join-Path $ProjectDir "tmp" "evidence" "SPEC-${SpecDisplay}-browser-${DateStamp}"
}

New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null

Write-Host "FORGE Browser Test - Spec $SpecDisplay" -ForegroundColor Cyan
Write-Host "Evidence dir: $EvidenceDir"

# Check Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Node.js is required. Install from https://nodejs.org/" -ForegroundColor Red
    exit 1
}

# Auto-detect runner
if (-not $Runner) {
    if (Test-Path (Join-Path $ProjectDir "node_modules" "playwright")) {
        $Runner = "playwright"
    } elseif (Test-Path (Join-Path $ProjectDir "node_modules" "puppeteer")) {
        $Runner = "puppeteer"
    } else {
        Write-Host "No browser test framework found." -ForegroundColor Yellow
        Write-Host "  Install: npm install --save-dev playwright"
        Write-Host "  Install: npm install --save-dev puppeteer"
        exit 1
    }
}

$Headless = if ($Headed) { "false" } else { "true" }
$Video = if ($NoVideo) { "false" } else { "true" }

Write-Host "Runner: $Runner"
Write-Host "Base URL: $Url"
Write-Host "Headless: $Headless"
Write-Host "Video: $Video"

# Locate test file
if (-not $TestFile) {
    $SearchPattern = "browser-test-${SpecDisplay}.*"
    $Found = Get-ChildItem -Path $ProjectDir -Recurse -Depth 3 -Filter $SearchPattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Found) {
        $TestFile = $Found.FullName
    } else {
        $TestFile = Join-Path $EvidenceDir "browser-test.js"
        if (-not (Test-Path $TestFile)) {
            Write-Host "No browser test script found for Spec $SpecDisplay." -ForegroundColor Yellow
            Write-Host "Generate one by running /implement with UI acceptance criteria."
            Write-Host "Template: $(Join-Path $ForgeDir '.forge' 'templates' 'browser-test-template.js')"
            exit 0
        }
    }
}

Write-Host "Test file: $TestFile"

# Set environment and run
$env:FORGE_SPEC = $SpecDisplay
$env:FORGE_EVIDENCE_DIR = $EvidenceDir
$env:FORGE_BASE_URL = $Url
$env:FORGE_HEADLESS = $Headless
$env:FORGE_VIDEO = $Video
$env:FORGE_RUNNER = $Runner
$env:FORGE_BROWSER = $Browser

Write-Host "Running browser test..." -ForegroundColor Cyan

Push-Location $ProjectDir
try {
    node $TestFile
    $ExitCode = $LASTEXITCODE
    if ($null -eq $ExitCode) { $ExitCode = 0 }
} catch {
    $ExitCode = 1
    Write-Host "Error: $_" -ForegroundColor Red
} finally {
    Pop-Location
}

# Report evidence
$ManifestPath = Join-Path $EvidenceDir "manifest.json"
if (Test-Path $ManifestPath) {
    Write-Host "Evidence manifest: $ManifestPath" -ForegroundColor Green
    $Screenshots = (Get-ChildItem -Path $EvidenceDir -Filter "*.png" -ErrorAction SilentlyContinue).Count
    Write-Host "Screenshots captured: $Screenshots"

    $SummaryPath = Join-Path $EvidenceDir "summary.md"
    if (Test-Path $SummaryPath) {
        Write-Host "Summary report: $SummaryPath"
    }

    $Videos = (Get-ChildItem -Path $EvidenceDir -Include "*.mp4","*.webm" -Recurse -ErrorAction SilentlyContinue).Count
    if ($Videos -gt 0) {
        Write-Host "Video recordings: $Videos"
    }
} else {
    Write-Host "No evidence manifest generated. Check test output." -ForegroundColor Yellow
}

Write-Host "FORGE Browser Test - complete" -ForegroundColor Cyan

# Clean up env
Remove-Item env:FORGE_SPEC -ErrorAction SilentlyContinue
Remove-Item env:FORGE_EVIDENCE_DIR -ErrorAction SilentlyContinue
Remove-Item env:FORGE_BASE_URL -ErrorAction SilentlyContinue
Remove-Item env:FORGE_HEADLESS -ErrorAction SilentlyContinue
Remove-Item env:FORGE_VIDEO -ErrorAction SilentlyContinue
Remove-Item env:FORGE_RUNNER -ErrorAction SilentlyContinue
Remove-Item env:FORGE_BROWSER -ErrorAction SilentlyContinue

exit $ExitCode

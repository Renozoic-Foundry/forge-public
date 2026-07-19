# FORGE forge-sync-cross-level (PowerShell sibling) — Spec 270
# forge:path-literal-ok (file: framework-structure — framework-repo mirror sync tooling; Spec 575)
# Propagates canonical repo-root sources to template/ mirrors.
#
# forge:path-literal-ok (framework-structure) — this script syncs FORGE's own docs/
# tree into template/ mirrors; the docs/process-kit references below are not a
# generic consumer project's process-state location.
# Sync pairs:
#   .forge/commands/*.md        -> template/.forge/commands/*
#   .claude/agents/*.md         -> template/.claude/agents/*
#   docs/process-kit/*.md       -> template/docs/process-kit/*
#
# Usage: pwsh .forge/bin/forge-sync-cross-level.ps1 [-Check] [-DryRun] [-VerboseOutput]

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$DryRun,
    [switch]$VerboseOutput,
    [switch]$Help
)

if ($Help) {
    Write-Output @"
Usage: pwsh .forge/bin/forge-sync-cross-level.ps1 [-Check] [-DryRun] [-VerboseOutput]

Propagate repo-root canonical sources to template/ mirrors.

Options:
  -Check            Non-zero exit on unexpected drift (pre-commit safe)
  -DryRun           Report what would change without writing files
  -VerboseOutput    Show all file comparisons, not just drifted ones

Sync pairs:
  .forge/commands/*.md       -> template/.forge/commands/*
  .claude/agents/*.md        -> template/.claude/agents/*
  docs/process-kit/*.md      -> template/docs/process-kit/*

Escape hatch: .forge/state/expected-cross-level-drift.txt
Composition:  .forge/update-manifest.yaml (project, removed sections)
"@
    exit 0
}

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ForgeDir = Resolve-Path (Join-Path $ScriptDir '..')
$ProjectDir = Resolve-Path (Join-Path $ForgeDir '..')
$TemplateDir = Join-Path $ProjectDir 'template'
$ManifestFile = Join-Path $ForgeDir 'update-manifest.yaml'
$EscapeHatch = Join-Path $ForgeDir 'state/expected-cross-level-drift.txt'

function Write-VLog {
    param([string]$Message)
    if ($VerboseOutput) { Write-Output $Message }
}

# Load escape hatch
$ExpectedDrift = @{}
if (Test-Path $EscapeHatch) {
    Get-Content $EscapeHatch | ForEach-Object {
        $line = $_
        if ($line -match '^\s*#') { return }
        if ($line.Trim() -eq '') { return }
        $path = ($line -split '\|', 2)[0].Trim()
        if ($path) { $ExpectedDrift[$path] = $true }
    }
}

# Parse manifest — extract project and removed path lists
$ProjectPaths = @()
$RemovedPaths = @()
if (Test-Path $ManifestFile) {
    $currentSection = ''
    $inPaths = $false
    Get-Content $ManifestFile | ForEach-Object {
        $line = $_
        if ($line -match '^(framework|project|merge|obsolete|removed):') {
            $currentSection = $Matches[1]
            $inPaths = $false
            return
        }
        if ($currentSection -and $line -match '^\s+paths:') {
            $inPaths = $true
            return
        }
        if ($currentSection -and $line -match '^\s+mappings:') {
            $inPaths = $false
            return
        }
        if ($inPaths -and $line -match '^\s+-\s+(.+)$') {
            $entry = $Matches[1]
            # Strip inline comment
            $entry = ($entry -split '#', 2)[0].Trim()
            # Strip surrounding quotes
            $entry = $entry.Trim('"')
            if ($currentSection -eq 'project') { $ProjectPaths += $entry }
            elseif ($currentSection -eq 'removed') { $RemovedPaths += $entry }
        }
    }
}

function Test-ProjectOwned {
    param([string]$RelPath)
    foreach ($pattern in $ProjectPaths) {
        if ($RelPath -like $pattern) { return $true }
        # Directory prefix match
        if ($pattern.EndsWith('/') -and $RelPath.StartsWith($pattern)) { return $true }
    }
    return $false
}

function Test-ExpectedDrift {
    param([string]$RelPath)
    return $ExpectedDrift.ContainsKey($RelPath)
}

function Find-MirrorTarget {
    param([string]$CanonicalRel)
    $mirrorBase = Join-Path $TemplateDir $CanonicalRel
    if (Test-Path "$mirrorBase.jinja") { return "$mirrorBase.jinja" }
    return $mirrorBase
}

$script:Synced = 0
$script:Created = 0
$script:Deleted = 0
$script:Skipped = 0
$script:DriftCount = 0

function Invoke-ProcessFile {
    param(
        [string]$CanonicalFile,
        [string]$CanonicalRel,
        [string]$MirrorTarget
    )
    $mirrorRel = $MirrorTarget.Substring($ProjectDir.ToString().Length + 1) -replace '\\', '/'

    if ($Check) {
        if (-not (Test-Path $MirrorTarget)) {
            if ((Test-ExpectedDrift $mirrorRel) -or (Test-ExpectedDrift $CanonicalRel)) {
                Write-VLog "  OK (expected missing): $CanonicalRel"
                $script:Skipped++
            } else {
                Write-Output "DRIFT [missing]: $CanonicalRel -- new canonical file not mirrored at $mirrorRel"
                $script:DriftCount++
            }
            return
        }
        $expected = [System.IO.File]::ReadAllText($CanonicalFile)
        $actual = [System.IO.File]::ReadAllText($MirrorTarget)
        if ($expected -ne $actual) {
            if ((Test-ExpectedDrift $mirrorRel) -or (Test-ExpectedDrift $CanonicalRel)) {
                Write-VLog "  OK (expected drift): $CanonicalRel"
                $script:Skipped++
            } else {
                Write-Output "DRIFT [content]: $CanonicalRel -> $mirrorRel"
                $script:DriftCount++
            }
        } else {
            Write-VLog "  OK: $CanonicalRel"
        }
        return
    }

    # Dry-run or sync
    if ((Test-ExpectedDrift $mirrorRel) -or (Test-ExpectedDrift $CanonicalRel)) {
        Write-VLog "  Skip (expected drift): $CanonicalRel"
        $script:Skipped++
        return
    }

    if ($DryRun) {
        if (-not (Test-Path $MirrorTarget)) {
            Write-Output "  Would create: $mirrorRel"
            $script:Created++
        } else {
            $expected = [System.IO.File]::ReadAllText($CanonicalFile)
            $actual = [System.IO.File]::ReadAllText($MirrorTarget)
            if ($expected -ne $actual) {
                Write-Output "  Would update: $mirrorRel"
                $script:Synced++
            } else {
                Write-VLog "  No change: $mirrorRel"
            }
        }
        return
    }

    # Sync
    if (-not (Test-Path $MirrorTarget)) {
        $dir = Split-Path -Parent $MirrorTarget
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Copy-Item -Path $CanonicalFile -Destination $MirrorTarget -Force
        $script:Created++
        Write-VLog "  Created: $mirrorRel"
        return
    }
    $expected = [System.IO.File]::ReadAllText($CanonicalFile)
    $actual = [System.IO.File]::ReadAllText($MirrorTarget)
    if ($expected -ne $actual) {
        Copy-Item -Path $CanonicalFile -Destination $MirrorTarget -Force
        $script:Synced++
        Write-VLog "  Synced: $mirrorRel"
    } else {
        Write-VLog "  No change: $mirrorRel"
    }
}

function Invoke-ProcessDir {
    param(
        [string]$CanonicalDir,
        [string]$CanonicalPrefix
    )
    if (-not (Test-Path $CanonicalDir)) { return }
    Get-ChildItem -Path $CanonicalDir -File | Where-Object {
        $_.Name -like '*.md' -or $_.Name -like '*.md.jinja'
    } | ForEach-Object {
        $canonicalRel = "$CanonicalPrefix/$($_.Name)"
        if (Test-ProjectOwned $canonicalRel) {
            Write-VLog "  Skip (project-owned): $canonicalRel"
            $script:Skipped++
            return
        }
        $mirrorTarget = Find-MirrorTarget $canonicalRel
        Invoke-ProcessFile $_.FullName $canonicalRel $mirrorTarget
    }
}

function Invoke-ProcessRemoved {
    foreach ($removedPath in $RemovedPaths) {
        $mirrorTarget = Join-Path $TemplateDir $removedPath
        $mirrorRel = "template/$removedPath"
        if (-not (Test-Path $mirrorTarget)) { continue }
        if ($Check) {
            Write-Output "DRIFT [removed]: $removedPath -- should be deleted from $mirrorRel (manifest: removed)"
            $script:DriftCount++
        } elseif ($DryRun) {
            Write-Output "  Would delete (removed in manifest): $mirrorRel"
            $script:Deleted++
        } else {
            Remove-Item -Force $mirrorTarget
            $script:Deleted++
            Write-VLog "  Deleted (removed in manifest): $mirrorRel"
        }
    }
}

Write-Output '## forge-sync-cross-level'
Write-Output ''

if (Test-Path (Join-Path $ProjectDir '.forge/commands')) {
    Write-Output '=== .forge/commands -> template/.forge/commands ==='
    Invoke-ProcessDir (Join-Path $ProjectDir '.forge/commands') '.forge/commands'
    Write-Output ''
}

if (Test-Path (Join-Path $ProjectDir '.claude/agents')) {
    Write-Output '=== .claude/agents -> template/.claude/agents ==='
    Invoke-ProcessDir (Join-Path $ProjectDir '.claude/agents') '.claude/agents'
    Write-Output ''
}

if (Test-Path (Join-Path $ProjectDir 'docs/process-kit')) {
    Write-Output '=== docs/process-kit -> template/docs/process-kit ==='
    Invoke-ProcessDir (Join-Path $ProjectDir 'docs/process-kit') 'docs/process-kit'
    Write-Output ''
}

if ($RemovedPaths.Count -gt 0) {
    Write-Output '=== Processing manifest removals ==='
    Invoke-ProcessRemoved
    Write-Output ''
}

Write-Output '## Summary'
if ($Check) {
    Write-Output "Expected drift (skipped): $script:Skipped"
    Write-Output "Unexpected drift: $script:DriftCount"
    Write-Output ''
    if ($script:DriftCount -gt 0) {
        Write-Output "FAILED: $script:DriftCount file(s) out of sync."
        Write-Output 'Run .forge/bin/forge-sync-cross-level.ps1 to fix, then re-commit.'
        exit 1
    } else {
        Write-Output 'PASS: All cross-level mirrors are in sync.'
        exit 0
    }
} elseif ($DryRun) {
    Write-Output 'Mode: dry-run (no files written)'
    Write-Output "Would create: $script:Created"
    Write-Output "Would update: $script:Synced"
    Write-Output "Would delete (manifest removed): $script:Deleted"
    Write-Output "Skipped (expected drift/project-owned): $script:Skipped"
} else {
    Write-Output "Created: $script:Created"
    Write-Output "Synced: $script:Synced"
    Write-Output "Deleted (manifest removed): $script:Deleted"
    Write-Output "Skipped (expected drift/project-owned): $script:Skipped"
}

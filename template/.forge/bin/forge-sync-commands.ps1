#Requires -Version 5.1
<#
.SYNOPSIS
    Generate agent-specific command wrappers from canonical FORGE commands.
.DESCRIPTION
    Reads command files from .forge/commands/ (canonical source) and generates
    agent-specific wrappers in each agent's native command directory.
    Strips YAML frontmatter when copying — agent directories get clean files.
.PARAMETER Agents
    Comma-separated list of agents. Default: read from onboarding.yaml or claude-code.
.PARAMETER Scope
    Installation scope: project (default), user, or both.
    project: sync to project agent directories (existing behavior).
    user: install Codex skills to ~/.codex/skills/ and commands to ~/.claude/commands/.
    both: do both project and user installation.
.PARAMETER DryRun
    Report what would be generated without writing files.
.EXAMPLE
    .\forge-sync-commands.ps1
    .\forge-sync-commands.ps1 -Agents claude-code,cursor
    .\forge-sync-commands.ps1 -Scope user
    .\forge-sync-commands.ps1 -Scope both -DryRun
    .\forge-sync-commands.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string]$Agents = "",
    [ValidateSet("project", "user", "both")]
    [string]$Scope = "project",
    [switch]$DryRun,
    [switch]$Force,  # Spec 329: overwrite mirror files even when body diverges from canonical
    [switch]$TemplateSide  # Spec 281: process template/.forge/commands -> template/.claude/commands (4th-edge sync)
)

$ErrorActionPreference = "Stop"

$ForgeDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
# Adjust: this script lives in .forge/bin/, so FORGE_DIR is .forge/
$ForgeDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ".."
$ForgeDir = (Resolve-Path $ForgeDir).Path
$ProjectDir = (Resolve-Path (Join-Path $ForgeDir "..")).Path
$CanonicalDir = Join-Path $ForgeDir "commands"
$BaseDir = $ProjectDir  # Spec 281: base for agent target directories (overridden by -TemplateSide)
$TriggerMap = Join-Path $ForgeDir "templates\codex-trigger-map.yaml"

# --- Spec 281: -TemplateSide switches both canonical source and target base ---
if ($TemplateSide) {
    $CanonicalDir = Join-Path $ProjectDir "template\.forge\commands"
    $BaseDir = Join-Path $ProjectDir "template"
    if ($Scope -eq "user" -or $Scope -eq "both") {
        Write-Error "-TemplateSide is incompatible with -Scope user|both (template processing is project-side only)"
        exit 1
    }
}

# --- Resolve agents ---
function Resolve-Agents {
    if ($Agents -ne "") {
        return $Agents -split ","
    }

    $onboardingFile = Join-Path $ForgeDir "onboarding.yaml"
    if (Test-Path $onboardingFile) {
        $content = Get-Content $onboardingFile -Raw
        $agentList = @()
        $inAgents = $false
        foreach ($line in ($content -split "`n")) {
            if ($line -match "^agents:") {
                $inAgents = $true
                continue
            }
            if ($inAgents) {
                if ($line -match "^[a-z_]" -and $line -notmatch "^\s") {
                    break
                }
                if ($line -match "^\s+(\w+):\s*(true|false)") {
                    if ($Matches[2] -eq "true") {
                        $agentList += $Matches[1] -replace "_", "-"
                    }
                }
            }
        }
        if ($agentList.Count -gt 0) {
            return $agentList
        }
    }

    return @("claude-code")
}

# --- Get agent command directory ---
# Spec 281: $BaseDir resolves to $ProjectDir by default, or $ProjectDir/template when -TemplateSide is set
function Get-AgentCommandDir {
    param([string]$Agent)
    switch ($Agent) {
        "claude-code" { return Join-Path $BaseDir ".claude\commands" }
        "cursor"      { return Join-Path $BaseDir ".cursor\commands" }
        "copilot"     { return Join-Path $BaseDir ".github\prompts" }
        "cline"       { return Join-Path $BaseDir ".cline\commands" }
        default       { Write-Warning "Unknown agent: $Agent"; return "" }
    }
}

# --- Strip YAML frontmatter ---
# CRLF-tolerant: trims trailing \r before comparing.
function Remove-Frontmatter {
    param([string[]]$Lines)
    $inFrontmatter = $false
    $frontmatterDone = $false
    $output = @()
    $firstLine = $true
    foreach ($line in $Lines) {
        $stripped = $line -replace "`r$", ""
        if (-not $frontmatterDone) {
            if ($firstLine) {
                $firstLine = $false
                if ($stripped -eq "---") {
                    $inFrontmatter = $true
                    continue
                }
                # No leading frontmatter — fall through
                $frontmatterDone = $true
                $output += $line
                continue
            }
            elseif ($stripped -eq "---" -and $inFrontmatter) {
                $frontmatterDone = $true
                $inFrontmatter = $false
                continue
            }
            elseif ($inFrontmatter) {
                continue
            }
        }
        $output += $line
    }
    return $output
}

# --- Spec 329: Extract frontmatter block (returns lines including --- markers, or empty) ---
function Get-Frontmatter {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return @() }
    $lines = Get-Content $FilePath
    $output = @()
    $inFm = $false
    $first = $true
    foreach ($line in $lines) {
        $stripped = $line -replace "`r$", ""
        if ($first) {
            $first = $false
            if ($stripped -eq "---") {
                $inFm = $true
                $output += $line
                continue
            }
            return @()
        }
        if ($inFm) {
            $output += $line
            if ($stripped -eq "---") {
                return $output
            }
        }
    }
    return @()
}

# --- Spec 329: Check if file is FORGE-managed (frontmatter-aware) ---
# Strips leading YAML frontmatter (if any), then checks first 5 BODY lines for the
# FORGE header. Fixes the head-5 scan that misidentified mirrors-with-frontmatter.
function Test-ForgeCommand {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $false }
    $body = Remove-Frontmatter -Lines (Get-Content $FilePath)
    if ($body.Count -eq 0) { return $false }
    $first5Body = $body | Select-Object -First 5
    return (($first5Body -join "`n") -match "(# Framework: FORGE|## Subcommand:)")
}

# --- Spec 329: Compare two files body-to-body (frontmatter stripped from both) ---
function Test-BodiesEqual {
    param([string]$FileA, [string]$FileB)
    if (-not (Test-Path $FileA) -or -not (Test-Path $FileB)) { return $false }
    $bodyA = (Remove-Frontmatter -Lines (Get-Content $FileA)) -join "`n"
    $bodyB = (Remove-Frontmatter -Lines (Get-Content $FileB)) -join "`n"
    return $bodyA -eq $bodyB
}

# --- Read frontmatter field ---
function Read-FrontmatterField {
    param([string]$FilePath, [string]$Field)
    $inFm = $false
    foreach ($line in (Get-Content $FilePath)) {
        if ($line -eq "---" -and -not $inFm) { $inFm = $true; continue }
        elseif ($line -eq "---" -and $inFm) { break }
        elseif ($inFm -and $line -match "^${Field}:\s*`"?([^`"]*)`"?") {
            return $Matches[1]
        }
    }
    return ""
}

# --- Read a field from the trigger map for a given command ---
function Read-TriggerField {
    param([string]$CommandName, [string]$Field)
    if (-not (Test-Path $TriggerMap)) { return "" }
    $content = Get-Content $TriggerMap
    $inCommands = $false
    $inCommand = $false
    foreach ($line in $content) {
        if ($line -match "^commands:") {
            $inCommands = $true
            continue
        }
        if (-not $inCommands) { continue }
        # Match command key (2-space indent, not 4)
        if ($line -match "^  ([a-z_-]+):" -and $line -notmatch "^    ") {
            if ($Matches[1] -eq $CommandName) {
                $inCommand = $true
                continue
            } else {
                if ($inCommand) { break }
            }
        }
        if ($inCommand -and $line -match "^\s+${Field}:\s*`"?(.+?)`"?\s*$") {
            return $Matches[1]
        }
    }
    return ""
}

# --- Generate a single Codex skill ---
function New-CodexSkill {
    param([string]$SrcFile, [string]$CommandName, [string]$SkillDir)

    $action = Read-TriggerField -CommandName $CommandName -Field "action"
    $triggers = Read-TriggerField -CommandName $CommandName -Field "triggers"
    $description = Read-FrontmatterField -FilePath $SrcFile -Field "description"

    if ([string]::IsNullOrEmpty($action)) { $action = "run the FORGE /$CommandName command" }
    if ([string]::IsNullOrEmpty($triggers)) { $triggers = "'/$CommandName'" }

    $srcLines = Get-Content $SrcFile
    $body = (Remove-Frontmatter -Lines $srcLines) -join "`n"

    # Convert command name to display name
    $displayName = ($CommandName -replace "-", " ") -replace "\b(\w)", { $_.Groups[1].Value.ToUpper() }

    if ($DryRun) {
        Write-Host "  Would generate Codex skill: $SkillDir\SKILL.md"
        Write-Host "  Would generate Codex agent: $SkillDir\agents\openai.yaml"
        return
    }

    $agentsDir = Join-Path $SkillDir "agents"
    if (-not (Test-Path $SkillDir)) { New-Item -ItemType Directory -Path $SkillDir -Force | Out-Null }
    if (-not (Test-Path $agentsDir)) { New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null }

    $skillDesc = "${description}. Use when the user wants to ${action}. Triggers on: ${triggers}."

    $skillContent = @"
---
name: forge-${CommandName}
description: "${skillDesc}"
---

# FORGE: ${displayName}

${body}

## Project Context

When inside a FORGE-managed project (has AGENTS.md or .forge/ directory), this command reads project-level configuration:
- AGENTS.md for autonomy levels and enforcement rules
- docs/specs/ for spec files
- docs/sessions/ for session logs and signals
- docs/backlog.md for prioritized work

When NOT inside a FORGE project, this command will note that no project context is available and suggest running ``forge install`` followed by ``/forge init`` to set up a project.
"@

    $skillContent | Set-Content -Path (Join-Path $SkillDir "SKILL.md") -Encoding UTF8

    $agentContent = @"
# Codex agent configuration for forge-${CommandName}
model: o4-mini
instructions_file: ../SKILL.md
"@

    $agentContent | Set-Content -Path (Join-Path $agentsDir "openai.yaml") -Encoding UTF8
}

# --- Generate all Codex skills ---
function Install-CodexSkills {
    $codexSkillsDir = Join-Path $HOME ".codex\skills"
    Write-Host "`nGenerating Codex skills in $codexSkillsDir"

    if (-not (Test-Path $TriggerMap)) {
        Write-Warning "Trigger map not found: $TriggerMap - skipping Codex skill generation"
        return
    }

    $codexCount = 0
    foreach ($srcFile in (Get-ChildItem -Path $CanonicalDir -Filter "*.md*")) {
        $cmdName = $srcFile.BaseName
        # Strip .md from .md.jinja files (BaseName would be "test.md")
        if ($cmdName -match "\.md$") { $cmdName = $cmdName -replace "\.md$", "" }
        $skillDir = Join-Path $codexSkillsDir "forge-$cmdName"

        New-CodexSkill -SrcFile $srcFile.FullName -CommandName $cmdName -SkillDir $skillDir
        $codexCount++
    }

    Write-Host "  Generated: $codexCount Codex skills in $codexSkillsDir"
}

# --- Install commands to user-level Claude Code directory ---
function Install-ClaudeCodeUser {
    $userCmdDir = Join-Path $HOME ".claude\commands"
    Write-Host "`nInstalling FORGE commands to $userCmdDir"

    if (-not $DryRun -and -not (Test-Path $userCmdDir)) {
        New-Item -ItemType Directory -Path $userCmdDir -Force | Out-Null
    }

    $userCount = 0
    foreach ($srcFile in (Get-ChildItem -Path $CanonicalDir -Filter "*.md*")) {
        $dstFile = Join-Path $userCmdDir $srcFile.Name

        if ((Test-Path $dstFile) -and -not (Test-ForgeCommand $dstFile)) {
            Write-Warning "CONFLICT: $dstFile exists and is not a FORGE command - skipping"
            continue
        }

        if ($DryRun) {
            Write-Host "  Would install: $dstFile"
            $userCount++
            continue
        }

        $srcLines = Get-Content $srcFile.FullName
        $body = Remove-Frontmatter -Lines $srcLines
        $body | Set-Content -Path $dstFile -Encoding UTF8
        $userCount++
    }

    Write-Host "  Installed: $userCount commands to $userCmdDir"
}

# --- Main ---
$agentList = Resolve-Agents
if ($agentList.Count -eq 0) { $agentList = @("claude-code") }

Write-Host "Target agents: $($agentList -join ', ')"
Write-Host "Scope: $Scope"

if (-not (Test-Path $CanonicalDir)) {
    Write-Error "Canonical command directory not found: $CanonicalDir"
    exit 1
}

$generated = 0
$conflicts = 0

# --- User-level installation ---
if ($Scope -eq "user" -or $Scope -eq "both") {
    Install-CodexSkills
    Install-ClaudeCodeUser
}

# --- Project-level installation ---
if ($Scope -ne "user") {
foreach ($agent in $agentList) {
    $targetDir = Get-AgentCommandDir -Agent $agent
    if ($targetDir -eq "") { continue }

    Write-Host "`nGenerating commands for: $agent"

    if (-not $DryRun -and -not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    foreach ($srcFile in (Get-ChildItem -Path $CanonicalDir -Filter "*.md*")) {
        $dstFile = Join-Path $targetDir $srcFile.Name

        # Check for conflicts
        if ((Test-Path $dstFile) -and -not (Test-ForgeCommand $dstFile)) {
            Write-Warning "CONFLICT: $dstFile exists and is not a FORGE command - skipping"
            $conflicts++
            continue
        }

        $desc = Read-FrontmatterField -FilePath $srcFile.FullName -Field "description"
        $srcLines = Get-Content $srcFile.FullName

        if ($DryRun) {
            Write-Host "  Would generate: $dstFile"
            $generated++
            continue
        }

        $body = Remove-Frontmatter -Lines $srcLines

        switch ($agent) {
            "claude-code" {
                # Spec 329: refuse-overwrite-without-force when body diverges
                if ((Test-Path $dstFile) -and -not $Force) {
                    if (-not (Test-BodiesEqual -FileA $srcFile.FullName -FileB $dstFile)) {
                        Write-Error "REFUSED OVERWRITE: $dstFile body diverges from canonical $($srcFile.FullName). Re-run with -Force to overwrite."
                        exit 2
                    }
                }
                # Frontmatter-preserving regen for claude-code:
                # If mirror exists with frontmatter, preserve it; replace body only.
                # If mirror has no frontmatter, fall back to canonical's frontmatter.
                # If mirror does not exist, copy canonical's frontmatter + body.
                if (Test-Path $dstFile) {
                    $mirrorFm = Get-Frontmatter -FilePath $dstFile
                    if ($mirrorFm.Count -eq 0) {
                        $mirrorFm = Get-Frontmatter -FilePath $srcFile.FullName
                    }
                    if ($Force -and -not (Test-BodiesEqual -FileA $srcFile.FullName -FileB $dstFile)) {
                        Write-Warning "FORCE OVERWRITE: $dstFile body replaced from canonical"
                    }
                } else {
                    $mirrorFm = Get-Frontmatter -FilePath $srcFile.FullName
                }
                if ($mirrorFm.Count -gt 0) {
                    ($mirrorFm + $body) | Set-Content -Path $dstFile -Encoding UTF8
                } else {
                    $body | Set-Content -Path $dstFile -Encoding UTF8
                }
            }
            { $_ -in @("cursor", "cline") } {
                $body | Set-Content -Path $dstFile -Encoding UTF8
            }
            "copilot" {
                $header = @("---", "mode: agent", "description: `"$desc`"", "---")
                ($header + $body) | Set-Content -Path $dstFile -Encoding UTF8
            }
        }

        $generated++
    }

    Write-Host "  Generated: $generated files in $targetDir"
}
}  # end project-level installation

Write-Host ""
Write-Host "## forge-sync-commands - Complete"
Write-Host "Agents: $($agentList -join ', ')"
Write-Host "Commands generated: $generated"
Write-Host "Conflicts (skipped): $conflicts"
if ($DryRun) {
    Write-Host "Mode: dry-run (no files written)"
}

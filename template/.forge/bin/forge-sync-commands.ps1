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
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$ForgeDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
# Adjust: this script lives in .forge/bin/, so FORGE_DIR is .forge/
$ForgeDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ".."
$ForgeDir = (Resolve-Path $ForgeDir).Path
$ProjectDir = (Resolve-Path (Join-Path $ForgeDir "..")).Path
$CanonicalDir = Join-Path $ForgeDir "commands"
$TriggerMap = Join-Path $ForgeDir "templates\codex-trigger-map.yaml"

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
function Get-AgentCommandDir {
    param([string]$Agent)
    switch ($Agent) {
        "claude-code" { return Join-Path $ProjectDir ".claude\commands" }
        "cursor"      { return Join-Path $ProjectDir ".cursor\commands" }
        "copilot"     { return Join-Path $ProjectDir ".github\prompts" }
        "cline"       { return Join-Path $ProjectDir ".cline\commands" }
        default       { Write-Warning "Unknown agent: $Agent"; return "" }
    }
}

# --- Strip YAML frontmatter ---
function Remove-Frontmatter {
    param([string[]]$Lines)
    $inFrontmatter = $false
    $frontmatterDone = $false
    $output = @()
    foreach ($line in $Lines) {
        if (-not $frontmatterDone) {
            if ($line -eq "---" -and -not $inFrontmatter) {
                $inFrontmatter = $true
                continue
            }
            elseif ($line -eq "---" -and $inFrontmatter) {
                $frontmatterDone = $true
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

# --- Check if file is FORGE-managed ---
function Test-ForgeCommand {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $false }
    $first5 = Get-Content $FilePath -TotalCount 5 -ErrorAction SilentlyContinue
    return ($first5 -join "`n") -match "# Framework: FORGE"
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
            { $_ -in @("claude-code", "cursor", "cline") } {
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

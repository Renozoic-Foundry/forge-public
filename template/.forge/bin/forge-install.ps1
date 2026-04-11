#Requires -Version 5.1
<#
.SYNOPSIS
    User-level FORGE installation and management.
.DESCRIPTION
    Installs FORGE libraries, commands, and agent integrations to ~/.forge/.
    Supports installation, update, and uninstall of user-level FORGE files
    and per-agent configuration (Codex, Claude Code, Cursor, Copilot, Cline, Windsurf).
.PARAMETER Agents
    Comma-separated agent list: codex,claude-code,cursor,copilot,cline,windsurf.
    Default: auto-detect installed agents.
.PARAMETER Scope
    Where to install: user, project, or both. Default: user.
.PARAMETER Source
    Path to FORGE template repo. Default: auto-detect from script location.
.PARAMETER Update
    Update existing installation (reports "updated" instead of "installed").
.PARAMETER Uninstall
    Remove all user-level FORGE files.
.PARAMETER DryRun
    Show what would be done without doing it.
.EXAMPLE
    .\forge-install.ps1
    .\forge-install.ps1 -Agents codex,claude-code
    .\forge-install.ps1 -Update
    .\forge-install.ps1 -Uninstall
    .\forge-install.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string]$Agents = "",
    [ValidateSet("user", "project", "both")]
    [string]$Scope = "user",
    [string]$Source = "",
    [switch]$Update,
    [switch]$Uninstall,
    [switch]$CheckPrereqs,
    [switch]$SkipPrereqs,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# --- Constants ---
$ForgeManagedHeader = "# Managed by FORGE"
$ForgeCommandHeader = "# Framework: FORGE"
$ScriptVersion = "0.1.0"

# --- Logging ---
function Write-LogInfo  { param([string]$Msg) Write-Host "[+] $Msg" -ForegroundColor Green }
function Write-LogWarn  { param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-LogError { param([string]$Msg) Write-Host "[x] $Msg" -ForegroundColor Red }
function Write-LogStep  { param([string]$Msg) Write-Host "`n=== $Msg ===" -ForegroundColor Cyan }
function Write-LogDebug { param([string]$Msg) if ($env:FORGE_LOG_LEVEL -eq "DEBUG") { Write-Host "[.] $Msg" -ForegroundColor DarkGray } }

# --- Prerequisite checks (Spec 143) ---
function Test-Prereqs {
    Write-LogStep "Prerequisite Check"
    $missing = 0

    # Detect package manager
    $pkgMgr = "none"
    if (Get-Command scoop -ErrorAction SilentlyContinue) { $pkgMgr = "scoop" }
    elseif (Get-Command winget -ErrorAction SilentlyContinue) { $pkgMgr = "winget" }
    Write-LogInfo "Platform package manager: $pkgMgr"

    # Python
    $pycmd = $null
    if (Get-Command python3 -ErrorAction SilentlyContinue) { $pycmd = "python3" }
    elseif (Get-Command python -ErrorAction SilentlyContinue) { $pycmd = "python" }
    if ($pycmd) {
        $pyVer = & $pycmd --version 2>&1 | Select-String -Pattern '\d+\.\d+' | ForEach-Object { $_.Matches[0].Value }
        $parts = $pyVer -split '\.'
        if ([int]$parts[0] -ge 3 -and [int]$parts[1] -ge 9) {
            Write-LogInfo "Python: $pycmd $pyVer"
        } else {
            Write-LogWarn "Python: $pycmd $pyVer (need 3.9+)"
            $missing++
        }
    } else {
        Write-LogError "Python: not found (need 3.9+)"
        if ($pkgMgr -eq "scoop") { Write-Host "  Install: scoop install python" }
        elseif ($pkgMgr -eq "winget") { Write-Host "  Install: winget install Python.Python.3.12" }
        $missing++
    }

    # Git
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVer = git --version 2>&1 | Select-String -Pattern '\d+\.\d+' | ForEach-Object { $_.Matches[0].Value }
        Write-LogInfo "Git: $gitVer"
    } else {
        Write-LogError "Git: not found"
        if ($pkgMgr -eq "scoop") { Write-Host "  Install: scoop install git" }
        elseif ($pkgMgr -eq "winget") { Write-Host "  Install: winget install Git.Git" }
        $missing++
    }

    # Git Bash
    $gitBashPath = "C:\Program Files\Git\bin\bash.exe"
    if (Test-Path $gitBashPath) {
        Write-LogInfo "Git Bash: available"
    } else {
        Write-LogWarn "Git Bash: not found (required for .forge/ scripts)"
        $missing++
    }

    # Copier
    try {
        $copierVer = & python -m copier --version 2>&1 | Select-String -Pattern '\d+\.\d+' | ForEach-Object { $_.Matches[0].Value }
        $major = [int]($copierVer -split '\.')[0]
        if ($major -ge 9) {
            Write-LogInfo "Copier: $copierVer"
        } else {
            Write-LogWarn "Copier: $copierVer (need 9.0+)"
            Write-Host "  Install: pip install copier"
            $missing++
        }
    } catch {
        Write-LogError "Copier: not found (need 9.0+)"
        Write-Host "  Install: pip install copier"
        $missing++
    }

    # Shellcheck (advisory)
    if (Get-Command shellcheck -ErrorAction SilentlyContinue) {
        Write-LogInfo "shellcheck: available (optional)"
    } else {
        Write-LogInfo "shellcheck: not found (optional - install: pip install shellcheck-py)"
    }

    Write-Host ""
    if ($missing -eq 0) {
        Write-LogInfo "All prerequisites met."
        return $true
    } else {
        Write-LogError "$missing required prerequisite(s) missing."
        return $false
    }
}

if ($CheckPrereqs) {
    $result = Test-Prereqs
    if ($result) { exit 0 } else { exit 1 }
}

# --- Resolve paths ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UserHome = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath("UserProfile") }
$ForgeUserDir = Join-Path $UserHome ".forge"

# --- Resolve FORGE template source ---
function Resolve-ForgeSource {
    if ($Source -ne "") {
        if (-not (Test-Path $Source -PathType Container)) {
            Write-LogError "Source path does not exist: $Source"
            exit 1
        }
        return (Resolve-Path $Source).Path
    }

    # Script lives at <repo>/.forge/bin/ — parent of bin/ is .forge/
    $candidate = (Resolve-Path (Join-Path $ScriptDir "..")).Path
    if ((Test-Path (Join-Path $candidate "lib")) -and (Test-Path (Join-Path $candidate "commands"))) {
        return $candidate
    }

    # Walk up looking for copier.yml
    $dir = $ScriptDir
    while ($dir -and $dir -ne [System.IO.Path]::GetPathRoot($dir)) {
        if ((Test-Path (Join-Path $dir "copier.yml")) -or (Test-Path (Join-Path $dir "copier.yaml"))) {
            $forgeDir = Join-Path $dir ".forge"
            if (Test-Path $forgeDir -PathType Container) {
                return (Resolve-Path $forgeDir).Path
            }
        }
        $dir = Split-Path -Parent $dir
    }

    Write-LogError "Cannot find FORGE template source. Use -Source to specify the path."
    exit 1
}

$TemplateSource = Resolve-ForgeSource
Write-LogInfo "FORGE template source: $TemplateSource"

# --- Resolve FORGE version ---
function Resolve-ForgeVersion {
    param([string]$SourceDir)

    $manifest = Join-Path $SourceDir "update-manifest.yaml"
    if (Test-Path $manifest) {
        $content = Get-Content $manifest -Raw
        if ($content -match "(?m)^version:\s*[`"']?([^`"'\r\n]+)") {
            return $Matches[1].Trim()
        }
    }

    # Try git describe
    $repoRoot = Split-Path -Parent $SourceDir
    try {
        $gitVersion = & git -C $repoRoot describe --tags --always 2>$null
        if ($gitVersion) { return $gitVersion.Trim() }
    } catch {}

    return "0.0.0-unknown"
}

# --- Auto-detect installed agents ---
function Detect-Agents {
    $detected = @()

    # codex
    if ((Get-Command codex -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $UserHome ".codex"))) {
        $detected += "codex"
    }

    # claude-code
    if ((Get-Command claude -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $UserHome ".claude"))) {
        $detected += "claude-code"
    }

    # cursor
    $cursorPaths = @(
        (Join-Path $UserHome ".cursor"),
        (Join-Path $env:APPDATA "Cursor" -ErrorAction SilentlyContinue)
    ) | Where-Object { $_ -and (Test-Path $_) }
    if ($cursorPaths.Count -gt 0) { $detected += "cursor" }

    # copilot
    if ((Test-Path (Join-Path $UserHome ".github")) -or (Get-Command gh -ErrorAction SilentlyContinue)) {
        $detected += "copilot"
    }

    # cline
    if (Test-Path (Join-Path $UserHome ".cline")) { $detected += "cline" }

    # windsurf
    $windsurfPaths = @(
        (Join-Path $UserHome ".windsurf"),
        (Join-Path $env:APPDATA "Windsurf" -ErrorAction SilentlyContinue)
    ) | Where-Object { $_ -and (Test-Path $_) }
    if ($windsurfPaths.Count -gt 0) { $detected += "windsurf" }

    if ($detected.Count -eq 0) { $detected += "claude-code" }
    return $detected
}

# --- Resolve agent list ---
function Resolve-AgentList {
    if ($Agents -ne "") {
        return $Agents -split ","
    }
    return Detect-Agents
}

# --- Validate agent names ---
function Test-AgentNames {
    param([string[]]$AgentList)
    $valid = @("codex", "claude-code", "cursor", "copilot", "cline", "windsurf")
    foreach ($agent in $AgentList) {
        if ($agent -notin $valid) {
            Write-LogError "Unknown agent: $agent"
            Write-LogError "Valid agents: $($valid -join ', ')"
            exit 2
        }
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

# --- Copy directory contents ---
function Copy-ForgeDir {
    param([string]$Src, [string]$Dst, [string]$Label)

    if (-not (Test-Path $Src -PathType Container)) {
        Write-LogDebug "Source directory does not exist, skipping: $Src"
        return
    }

    if ($DryRun) {
        Write-LogInfo "Would copy ${Label}: $Src -> $Dst"
        return
    }

    if (-not (Test-Path $Dst)) {
        New-Item -ItemType Directory -Path $Dst -Force | Out-Null
    }
    Copy-Item -Path (Join-Path $Src "*") -Destination $Dst -Recurse -Force
    $fileCount = (Get-ChildItem $Dst -File -Recurse -ErrorAction SilentlyContinue).Count
    Write-LogInfo "Copied ${Label}: $fileCount files"
}

# --- Write version.yaml ---
function Write-VersionFile {
    param([string]$TargetDir)

    $version = Resolve-ForgeVersion -SourceDir $TemplateSource
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $agentsYaml = ($script:AgentList | ForEach-Object { "  - $_" }) -join "`n"

    if ($DryRun) {
        Write-LogInfo "Would write $(Join-Path $TargetDir 'version.yaml')"
        return
    }

    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    $content = @"
installed: $timestamp
source: $TemplateSource
version: $version
installer: $ScriptVersion
agents:
$agentsYaml
"@
    Set-Content -Path (Join-Path $TargetDir "version.yaml") -Value $content -Encoding UTF8
    Write-LogInfo "Wrote version.yaml (version: $version)"
}

# --- Test if file is FORGE-managed ---
function Test-ForgeManaged {
    param([string]$FilePath, [string]$Marker = "Managed by FORGE")
    if (-not (Test-Path $FilePath)) { return $false }
    $first = Get-Content $FilePath -TotalCount 1 -ErrorAction SilentlyContinue
    return ($first -match [regex]::Escape($Marker))
}

function Test-ForgeCommand {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $false }
    $first5 = Get-Content $FilePath -TotalCount 5 -ErrorAction SilentlyContinue
    return ($first5 -join "`n") -match "# Framework: FORGE"
}

# --- Agent installer: Claude Code ---
function Install-ClaudeCode {
    $targetDir = Join-Path $UserHome ".claude\commands"
    $sourceDir = Join-Path $TemplateSource "commands"

    Write-LogStep "Installing Claude Code commands"

    if (-not (Test-Path $sourceDir -PathType Container)) {
        Write-LogWarn "No commands directory found in source - skipping Claude Code"
        return
    }

    if ($DryRun) {
        Write-LogInfo "Would create: $targetDir"
        $count = (Get-ChildItem $sourceDir -Filter "*.md*" -File).Count
        Write-LogInfo "Would install $count commands to $targetDir"
        return
    }

    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $installed = 0
    foreach ($srcFile in (Get-ChildItem $sourceDir -Filter "*.md*" -File)) {
        $dstFile = Join-Path $targetDir $srcFile.Name

        # Skip existing non-FORGE files
        if ((Test-Path $dstFile) -and -not (Test-ForgeCommand $dstFile)) {
            Write-LogWarn "Skipping $($srcFile.Name): existing non-FORGE file"
            continue
        }

        $srcLines = Get-Content $srcFile.FullName
        $body = Remove-Frontmatter -Lines $srcLines
        $body | Set-Content -Path $dstFile -Encoding UTF8
        $installed++
    }

    Write-LogInfo "Installed $installed Claude Code commands to $targetDir"
}

# --- Agent installer: Codex ---
function Install-Codex {
    $sourceDir = Join-Path $TemplateSource "commands"
    $codexSkillsDir = Join-Path $UserHome ".codex\skills"

    Write-LogStep "Installing Codex skills"

    if (-not (Test-Path $sourceDir -PathType Container)) {
        Write-LogWarn "No commands directory found in source - skipping Codex"
        return
    }

    if ($DryRun) {
        $count = (Get-ChildItem $sourceDir -Filter "*.md*" -File).Count
        Write-LogInfo "Would install $count Codex skills to $codexSkillsDir\forge-*\"
        return
    }

    $installed = 0
    foreach ($srcFile in (Get-ChildItem $sourceDir -Filter "*.md*" -File)) {
        $baseName = $srcFile.BaseName -replace '\.jinja$', '' -replace '\.md$', ''
        if ($srcFile.Extension -eq ".jinja") {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
        }

        $cmdName = Read-FrontmatterField -FilePath $srcFile.FullName -Field "name"
        if (-not $cmdName) { $cmdName = $baseName }

        $cmdDesc = Read-FrontmatterField -FilePath $srcFile.FullName -Field "description"
        if (-not $cmdDesc) { $cmdDesc = "FORGE command: $cmdName" }

        $skillDir = Join-Path $codexSkillsDir "forge-$cmdName"
        $agentsDir = Join-Path $skillDir "agents"

        New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null

        # Generate SKILL.md
        $srcLines = Get-Content $srcFile.FullName
        $body = Remove-Frontmatter -Lines $srcLines

        $skillContent = @(
            "---"
            "name: forge-$cmdName"
            "description: `"$cmdDesc. Use when the user invokes /forge $cmdName or asks about $cmdName.`""
            "---"
        ) + $body

        $skillContent | Set-Content -Path (Join-Path $skillDir "SKILL.md") -Encoding UTF8

        # Title-case the command name
        $titleName = ($cmdName -split "-" | ForEach-Object {
            if ($_.Length -gt 0) { $_.Substring(0,1).ToUpper() + $_.Substring(1) } else { $_ }
        }) -join " "

        # Generate agents/openai.yaml
        $openaiContent = @"
interface:
  display_name: "FORGE: $titleName"
  short_description: "$cmdDesc"
"@
        Set-Content -Path (Join-Path $agentsDir "openai.yaml") -Value $openaiContent -Encoding UTF8

        $installed++
    }

    Write-LogInfo "Installed $installed Codex skills to $codexSkillsDir"
}

# --- Agent installer: Cursor ---
function Install-Cursor {
    $targetFile = Join-Path $UserHome ".cursorrules"

    Write-LogStep "Installing Cursor rules"

    if ((Test-Path $targetFile) -and -not (Test-ForgeManaged $targetFile)) {
        Write-LogWarn "Skipping Cursor: $targetFile exists with non-FORGE content"
        return
    }

    if ($DryRun) {
        Write-LogInfo "Would write: $targetFile"
        return
    }

    $content = @"
# Managed by FORGE - do not edit manually
# This file was generated by forge-install.ps1
# Re-run forge-install.ps1 -Update to refresh

# FORGE Framework Rules
You are working in a project that uses the FORGE (Framework for Organized Reliable Gated Engineering) methodology.

## Core principles
1. Every change has a matching spec. No implementation without one.
2. Every session ends with a session log. No exceptions.

## Workflow
- Check docs/backlog.md for prioritized work items
- Find specs in docs/specs/README.md
- Follow the spec lifecycle: draft -> in-progress -> implemented -> closed
- Use FORGE slash commands for structured workflows (/now, /spec, /implement, /close, /session)

## FORGE commands available
Run these as slash commands or ask about them:
/now - Review current project state
/spec - Create or update a spec
/implement - Implement a spec
/close - Close and validate a spec
/session - Log a session
/matrix - View prioritization matrix
/trace - Trace requirements to implementation
"@
    Set-Content -Path $targetFile -Value $content -Encoding UTF8
    Write-LogInfo "Wrote Cursor rules to $targetFile"
}

# --- Agent installer: Copilot ---
function Install-Copilot {
    $targetDir = Join-Path $UserHome ".github"
    $targetFile = Join-Path $targetDir "copilot-instructions.md"

    Write-LogStep "Installing Copilot instructions"

    if ((Test-Path $targetFile) -and -not (Test-ForgeManaged $targetFile)) {
        Write-LogWarn "Skipping Copilot: $targetFile exists with non-FORGE content"
        return
    }

    if ($DryRun) {
        Write-LogInfo "Would write: $targetFile"
        return
    }

    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $content = @"
<!-- Managed by FORGE - do not edit manually -->
<!-- Generated by forge-install.ps1. Re-run forge-install.ps1 -Update to refresh -->

# FORGE Framework Instructions

You are working in a project that uses the FORGE (Framework for Organized Reliable Gated Engineering) methodology.

## Core principles
1. Every change has a matching spec. No implementation without one.
2. Every session ends with a session log. No exceptions.

## Workflow
- Check docs/backlog.md for prioritized work items
- Find specs in docs/specs/README.md
- Follow the spec lifecycle: draft -> in-progress -> implemented -> closed

## When implementing changes
1. Always reference the relevant spec number
2. Follow the acceptance criteria defined in the spec
3. Run tests and validation before marking complete
4. Update the spec status when implementation is done
"@
    Set-Content -Path $targetFile -Value $content -Encoding UTF8
    Write-LogInfo "Wrote Copilot instructions to $targetFile"
}

# --- Agent installer: Cline ---
function Install-Cline {
    $targetFile = Join-Path $UserHome ".clinerules"

    Write-LogStep "Installing Cline rules"

    if ((Test-Path $targetFile) -and -not (Test-ForgeManaged $targetFile)) {
        Write-LogWarn "Skipping Cline: $targetFile exists with non-FORGE content"
        return
    }

    if ($DryRun) {
        Write-LogInfo "Would write: $targetFile"
        return
    }

    $content = @"
# Managed by FORGE - do not edit manually
# Generated by forge-install.ps1. Re-run forge-install.ps1 -Update to refresh

# FORGE Framework Rules
You are working in a project that uses the FORGE methodology.

## Core principles
1. Every change has a matching spec. No implementation without one.
2. Every session ends with a session log.

## Workflow
- Check docs/backlog.md for prioritized work
- Follow spec lifecycle: draft -> in-progress -> implemented -> closed
- Use FORGE commands for structured workflows
"@
    Set-Content -Path $targetFile -Value $content -Encoding UTF8
    Write-LogInfo "Wrote Cline rules to $targetFile"
}

# --- Agent installer: Windsurf ---
function Install-Windsurf {
    $targetFile = Join-Path $UserHome ".windsurfrules"

    Write-LogStep "Installing Windsurf rules"

    if ((Test-Path $targetFile) -and -not (Test-ForgeManaged $targetFile)) {
        Write-LogWarn "Skipping Windsurf: $targetFile exists with non-FORGE content"
        return
    }

    if ($DryRun) {
        Write-LogInfo "Would write: $targetFile"
        return
    }

    $content = @"
# Managed by FORGE - do not edit manually
# Generated by forge-install.ps1. Re-run forge-install.ps1 -Update to refresh

# FORGE Framework Rules
You are working in a project that uses the FORGE methodology.

## Core principles
1. Every change has a matching spec. No implementation without one.
2. Every session ends with a session log.

## Workflow
- Check docs/backlog.md for prioritized work
- Follow spec lifecycle: draft -> in-progress -> implemented -> closed
- Use FORGE commands for structured workflows
"@
    Set-Content -Path $targetFile -Value $content -Encoding UTF8
    Write-LogInfo "Wrote Windsurf rules to $targetFile"
}

# --- Uninstall flow ---
function Invoke-Uninstall {
    Write-LogStep "Uninstalling FORGE (user-level)"

    $removed = 0

    # 1. Remove ~/.forge/ entirely
    if (Test-Path $ForgeUserDir -PathType Container) {
        if ($DryRun) {
            Write-LogInfo "Would remove: $ForgeUserDir"
        } else {
            Remove-Item -Path $ForgeUserDir -Recurse -Force
            Write-LogInfo "Removed: $ForgeUserDir"
        }
        $removed++
    }

    # 2. Remove Codex skills (forge-* only)
    $codexSkillsDir = Join-Path $UserHome ".codex\skills"
    if (Test-Path $codexSkillsDir -PathType Container) {
        foreach ($skillDir in (Get-ChildItem $codexSkillsDir -Directory -Filter "forge-*")) {
            if ($DryRun) {
                Write-LogInfo "Would remove: $($skillDir.FullName)"
            } else {
                Remove-Item -Path $skillDir.FullName -Recurse -Force
                Write-LogInfo "Removed: $($skillDir.FullName)"
            }
            $removed++
        }
    }

    # 3. Remove FORGE commands from ~/.claude/commands/
    $claudeCmdDir = Join-Path $UserHome ".claude\commands"
    if (Test-Path $claudeCmdDir -PathType Container) {
        foreach ($cmdFile in (Get-ChildItem $claudeCmdDir -File -Filter "*.md*")) {
            if (Test-ForgeCommand $cmdFile.FullName) {
                if ($DryRun) {
                    Write-LogInfo "Would remove: $($cmdFile.FullName)"
                } else {
                    Remove-Item -Path $cmdFile.FullName -Force
                    Write-LogInfo "Removed: $($cmdFile.FullName)"
                }
                $removed++
            }
        }
    }

    # 4. Remove pointer files (only if FORGE-managed)
    $pointerFiles = @(
        (Join-Path $UserHome ".cursorrules"),
        (Join-Path $UserHome ".clinerules"),
        (Join-Path $UserHome ".windsurfrules"),
        (Join-Path $UserHome ".github\copilot-instructions.md")
    )
    foreach ($pf in $pointerFiles) {
        if (Test-Path $pf) {
            if (Test-ForgeManaged $pf) {
                if ($DryRun) {
                    Write-LogInfo "Would remove: $pf"
                } else {
                    Remove-Item -Path $pf -Force
                    Write-LogInfo "Removed: $pf"
                }
                $removed++
            } else {
                Write-LogWarn "Skipping: $pf (not FORGE-managed)"
            }
        }
    }

    Write-Host ""
    Write-Host "## forge-install -Uninstall - Complete"
    Write-Host "Items removed: $removed"
    if ($DryRun) {
        Write-Host "Mode: dry-run (no files removed)"
    }
}

# --- Install flow (user scope) ---
function Invoke-InstallUser {
    $modeLabel = if ($Update) { "Updating" } else { "Installing" }

    Write-LogStep "$modeLabel FORGE (user-level)"

    # Create directory structure
    $subDirs = @("lib", "adapters", "templates", "commands", "process-kit")
    if ($DryRun) {
        Write-LogInfo "Would create: $ForgeUserDir\{$($subDirs -join ',')}"
    } else {
        foreach ($sub in $subDirs) {
            $path = Join-Path $ForgeUserDir $sub
            if (-not (Test-Path $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }
    }

    # Copy template source directories
    Copy-ForgeDir -Src (Join-Path $TemplateSource "lib")       -Dst (Join-Path $ForgeUserDir "lib")       -Label "lib"
    Copy-ForgeDir -Src (Join-Path $TemplateSource "adapters")  -Dst (Join-Path $ForgeUserDir "adapters")  -Label "adapters"
    Copy-ForgeDir -Src (Join-Path $TemplateSource "templates") -Dst (Join-Path $ForgeUserDir "templates") -Label "templates"
    Copy-ForgeDir -Src (Join-Path $TemplateSource "commands")  -Dst (Join-Path $ForgeUserDir "commands")  -Label "commands"

    # process-kit
    $processKitSrc = Join-Path (Split-Path -Parent $TemplateSource) "docs\process-kit"
    if (Test-Path $processKitSrc -PathType Container) {
        Copy-ForgeDir -Src $processKitSrc -Dst (Join-Path $ForgeUserDir "process-kit") -Label "process-kit"
    } else {
        Write-LogWarn "process-kit source not found - skipping"
    }

    # Write version.yaml
    Write-VersionFile -TargetDir $ForgeUserDir

    # Install agent integrations
    foreach ($agent in $script:AgentList) {
        switch ($agent) {
            "claude-code" { Install-ClaudeCode }
            "codex"       { Install-Codex }
            "cursor"      { Install-Cursor }
            "copilot"     { Install-Copilot }
            "cline"       { Install-Cline }
            "windsurf"    { Install-Windsurf }
        }
    }
}

# --- Install flow (project scope) ---
function Invoke-InstallProject {
    Write-LogStep "Installing FORGE (project-level)"

    $syncScript = Join-Path $ScriptDir "forge-sync-commands.ps1"
    if (Test-Path $syncScript) {
        $syncArgs = @{}
        if ($Agents -ne "") { $syncArgs["Agents"] = $Agents }
        if ($DryRun) { $syncArgs["DryRun"] = $true }
        & $syncScript @syncArgs
    } else {
        Write-LogWarn "forge-sync-commands.ps1 not found - skipping project-level install"
    }
}

# --- Main ---
Write-Host ""
Write-Host "=== FORGE Installer v$ScriptVersion ==="
Write-Host ""

# Handle uninstall
if ($Uninstall) {
    Invoke-Uninstall
    exit 0
}

# Resolve and validate agents
$script:AgentList = @(Resolve-AgentList)
if ($script:AgentList.Count -eq 0) { $script:AgentList = @("claude-code") }
Test-AgentNames -AgentList $script:AgentList

Write-LogInfo "Detected agents: $($script:AgentList -join ', ')"
Write-LogInfo "Scope: $Scope"
Write-LogInfo "Source: $TemplateSource"
if ($DryRun) { Write-LogInfo "Mode: dry-run" }
if ($Update) { Write-LogInfo "Mode: update" }

# Execute install
switch ($Scope) {
    "user"    { Invoke-InstallUser }
    "project" { Invoke-InstallProject }
    "both"    { Invoke-InstallUser; Invoke-InstallProject }
}

# Summary
$action = if ($Update) { "Updated" } else { "Installed" }

Write-Host ""
Write-Host "## forge-install - Complete"
Write-Host "Action: $action"
Write-Host "Scope: $Scope"
Write-Host "Agents: $($script:AgentList -join ', ')"
if ($Scope -eq "user" -or $Scope -eq "both") {
    Write-Host "FORGE home: $ForgeUserDir"
}
if ($DryRun) {
    Write-Host "Mode: dry-run (no files written)"
}

#Requires -Version 5.1
<#
.SYNOPSIS
    FORGE CLI — thin entry point for spec-driven workflows.

.DESCRIPTION
    Maps `forge <command> [args]` to .forge/commands/<command>.md prompts
    and dispatches to the active AI agent runtime.

    Exit codes:
      0 — success
      1 — command not found
      2 — missing required arguments
      3 — agent dispatch failure

.EXAMPLE
    .\forge.ps1 list
    .\forge.ps1 help implement
    .\forge.ps1 implement 42 --plain
    .\forge.ps1 --version
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Arguments
)

$ErrorActionPreference = 'Stop'

# --- Path resolution ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$ForgeCommandsDir = Join-Path $ProjectDir '.forge' 'commands'
$ClaudeCommandsDir = Join-Path $ProjectDir '.claude' 'commands'

# Resolve commands directory
if (Test-Path $ForgeCommandsDir) {
    $CommandsDir = $ForgeCommandsDir
}
elseif (Test-Path $ClaudeCommandsDir) {
    $CommandsDir = $ClaudeCommandsDir
}
else {
    Write-Error "No commands directory found. Expected: .forge/commands/ or .claude/commands/"
    exit 3
}

# --- Version ---
$ForgeVersion = '1.0.0'
$CopierAnswers = Join-Path $ProjectDir '.copier-answers.yml'
if (Test-Path $CopierAnswers) {
    $content = Get-Content $CopierAnswers -Raw
    if ($content -match '^\s*_commit:\s*(.+)$') {
        $ForgeVersion = $Matches[1].Trim()
    }
}

# --- Helpers ---

function Find-CommandFile {
    param([string]$CmdName)
    $mdFile = Join-Path $CommandsDir "$CmdName.md"
    $jinjaFile = Join-Path $CommandsDir "$CmdName.md.jinja"
    if (Test-Path $mdFile) { return $mdFile }
    if (Test-Path $jinjaFile) { return $jinjaFile }
    return $null
}

function Get-CommandDescription {
    param([string]$FilePath)
    $content = Get-Content $FilePath -Raw
    if ($content -match '(?m)^description:\s*"?([^"\r\n]+)"?') {
        return $Matches[1]
    }
    return '(no description)'
}

function Get-CommandName {
    param([string]$FilePath)
    $content = Get-Content $FilePath -Raw
    if ($content -match '(?m)^name:\s*"?([^"\r\n]+)"?') {
        return $Matches[1]
    }
    return [System.IO.Path]::GetFileNameWithoutExtension($FilePath) -replace '\.md$', ''
}

function Test-RequiresSpecNumber {
    param([string]$CmdName)
    return $CmdName -in @('implement', 'close', 'trace', 'revise', 'handoff', 'tab')
}

function Show-CommandList {
    Write-Host 'FORGE CLI — Available Commands'
    Write-Host '=============================='
    Write-Host ''

    $files = Get-ChildItem -Path $CommandsDir -Filter '*.md*' |
        Where-Object { $_.Extension -match '^\.(md|jinja)$' -or $_.Name -match '\.md\.jinja$' } |
        Sort-Object Name

    $entries = @()
    $maxLen = 0
    foreach ($file in $files) {
        $name = Get-CommandName $file.FullName
        $desc = Get-CommandDescription $file.FullName
        $entries += @{ Name = $name; Desc = $desc }
        if ($name.Length -gt $maxLen) { $maxLen = $name.Length }
    }

    foreach ($entry in $entries) {
        $padded = $entry.Name.PadRight($maxLen)
        Write-Host "  $padded  $($entry.Desc)"
    }

    Write-Host ''
    Write-Host 'Usage: forge <command> [spec-number] [--plain|--json]'
    Write-Host '       forge help <command>     — show full command prompt'
    Write-Host '       forge --version          — show version'
}

function Show-CommandHelp {
    param([string]$CmdName)
    $file = Find-CommandFile $CmdName
    if (-not $file) {
        Write-Error "Unknown command '$CmdName'. Run 'forge list' to see available commands."
        exit 1
    }
    Get-Content $file -Raw | Write-Host
}

function Get-AgentRuntime {
    if (Get-Command 'claude' -ErrorAction SilentlyContinue) { return 'claude-code' }
    if (Get-Command 'aider' -ErrorAction SilentlyContinue) { return 'aider' }
    if (Get-Command 'cursor' -ErrorAction SilentlyContinue) { return 'cursor' }
    if (Get-Command 'codex' -ErrorAction SilentlyContinue) { return 'codex' }
    return 'generic'
}

function New-Prompt {
    param(
        [string]$CmdFile,
        [string]$SpecNumber
    )
    $promptContent = Get-Content $CmdFile -Raw

    if ($SpecNumber) {
        $specFiles = Get-ChildItem -Path (Join-Path $ProjectDir 'docs' 'specs') -Filter "$SpecNumber-*.md" -ErrorAction SilentlyContinue
        $specContext = ''
        if ($specFiles -and $specFiles.Count -gt 0) {
            $specFile = $specFiles[0].FullName
            $specContext = @"

---
## Spec Context (auto-loaded by forge CLI)
Spec file: $specFile
Spec number: $SpecNumber
---
"@
        }
        return "$promptContent$specContext`n`n`$ARGUMENTS: $SpecNumber"
    }
    return $promptContent
}

function Invoke-AgentDispatch {
    param(
        [string]$Agent,
        [string]$Prompt
    )
    switch ($Agent) {
        'claude-code' {
            try {
                $Prompt | claude -p -
            }
            catch {
                Write-Error 'Claude Code dispatch failed.'
                exit 3
            }
        }
        'aider' {
            try {
                $Prompt | aider --message-file -
            }
            catch {
                Write-Error 'Aider dispatch failed.'
                exit 3
            }
        }
        default {
            Write-Host $Prompt
        }
    }
}

# --- Parse arguments ---
$SpecNumber = ''
$OutputFormat = ''
$RemainingArgs = @()

if ($Arguments) {
    foreach ($arg in $Arguments) {
        switch -Regex ($arg) {
            '^--plain$' { $OutputFormat = 'plain' }
            '^--json$' { $OutputFormat = 'json' }
            '^--version$' {
                Write-Host "FORGE CLI v$ForgeVersion"
                exit 0
            }
            '^\d+$' {
                if (-not $SpecNumber) { $SpecNumber = $arg }
                else { $RemainingArgs += $arg }
            }
            default { $RemainingArgs += $arg }
        }
    }
}

# --- Main ---

# No command — show usage
if (-not $Command) {
    Write-Host "FORGE CLI v$ForgeVersion"
    Write-Host ''
    Write-Host 'Usage: forge <command> [spec-number] [flags]'
    Write-Host ''
    Write-Host "Run 'forge list' for available commands."
    Write-Host "Run 'forge help <command>' for command details."
    exit 0
}

# Handle --version as the command
if ($Command -eq '--version' -or $Command -eq '-v') {
    Write-Host "FORGE CLI v$ForgeVersion"
    exit 0
}

# Handle built-in commands
switch ($Command) {
    'list' {
        Show-CommandList
        exit 0
    }
    'help' {
        if ($RemainingArgs.Count -gt 0) {
            Show-CommandHelp $RemainingArgs[0]
        }
        elseif ($SpecNumber) {
            Write-Error "'forge help' expects a command name, not a number. Usage: forge help <command>"
            exit 2
        }
        else {
            Write-Error "'forge help' requires a command name. Usage: forge help <command>"
            exit 2
        }
        exit 0
    }
}

# Resolve command file
$CmdFile = Find-CommandFile $Command
if (-not $CmdFile) {
    Write-Error "Unknown command '$Command'. Run 'forge list' to see available commands."
    exit 1
}

# Check required spec number
if ((Test-RequiresSpecNumber $Command) -and -not $SpecNumber) {
    Write-Error "Command '$Command' requires a spec number. Usage: forge $Command <spec-number>"
    exit 2
}

# Assemble prompt
$Prompt = New-Prompt -CmdFile $CmdFile -SpecNumber $SpecNumber

# Handle output formats
switch ($OutputFormat) {
    'plain' {
        Write-Host $Prompt
        exit 0
    }
    'json' {
        $agent = Get-AgentRuntime
        $jsonObj = @{
            command     = $Command
            spec_number = $SpecNumber
            agent       = $agent
            prompt      = $Prompt
        }
        $jsonObj | ConvertTo-Json -Depth 3
        exit 0
    }
}

# Detect agent and dispatch
$agent = Get-AgentRuntime
Invoke-AgentDispatch -Agent $agent -Prompt $Prompt

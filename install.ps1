# FORGE Installer — Universal entry point (PowerShell)
# Usage: irm https://raw.githubusercontent.com/Renozoic-Foundry/forge-public/main/install.ps1 | iex
#        .\install.ps1 [-Repo <url>] [-Init <path>] [-Update] [-Yes]
#
# Detects environment (Claude Code or generic) and adapts behavior.
# See: https://github.com/Renozoic-Foundry/forge-public

[CmdletBinding()]
param(
    [string]$Repo = "",
    [string]$Init = "",
    [switch]$Update,
    [switch]$Yes,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# TLS 1.2 — required for PowerShell 5.1 (GitHub rejects TLS 1.0/1.1)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Constants ---
$DEFAULT_REPO = "https://github.com/Renozoic-Foundry/forge-public.git"
$RAW_BASE = "https://raw.githubusercontent.com/Renozoic-Foundry/forge-public/main"
$FORGE_CONFIG_DIR = Join-Path $HOME ".forge"
$FORGE_CONFIG_FILE = Join-Path $FORGE_CONFIG_DIR "config"
$CLAUDE_CMD_DIR = Join-Path (Join-Path $HOME ".claude") "commands"
$BOOTSTRAP_FILE = "forge-bootstrap.md"
$DOCS_URL = "https://github.com/Renozoic-Foundry/forge-public#readme"

# --- Output helpers ---
function Write-Info  { param([string]$Msg) Write-Host "  $([char]0x2713) $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "  ! $Msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$Msg) Write-Host "  X $Msg" -ForegroundColor Red }
function Write-Step  { param([string]$Msg) Write-Host "`n  $Msg" -ForegroundColor White -NoNewline; Write-Host "" }

function Confirm-Action {
    param([string]$Prompt)
    if ($Yes) { return $true }
    $response = Read-Host "$Prompt [Y/n]"
    return ($response -eq "" -or $response -match "^[yY]")
}

# --- Help ---
if ($Help) {
    @"
FORGE Installer - Universal entry point (PowerShell)

Usage:
  .\install.ps1 [OPTIONS]
  irm <url>/install.ps1 | iex

Options:
  -Repo <url>    Use a custom template repository (private fork)
  -Init <path>   Also bootstrap a project at <path> via Copier
  -Update        Refresh forge-bootstrap.md to latest version (Claude Code only)
  -Yes           Non-interactive mode (skip confirmation prompts)
  -Help          Show this help

Examples:
  .\install.ps1                                       # Install prereqs + detect Claude Code
  .\install.ps1 -Init my-project                      # Install + bootstrap a project
  .\install.ps1 -Repo https://github.com/myorg/forge-private.git
  .\install.ps1 -Repo https://github.com/myorg/forge.git -Init .
"@ | Write-Host
    exit 0
}

# --- Repo URL resolution ---
function Resolve-RepoUrl {
    if ($script:Repo) { return $script:Repo }
    if (Test-Path $FORGE_CONFIG_FILE) {
        $saved = Get-Content $FORGE_CONFIG_FILE -ErrorAction SilentlyContinue |
            Where-Object { $_ -match "^repo_url=" } |
            ForEach-Object { $_ -replace "^repo_url=", "" } |
            Select-Object -First 1
        if ($saved) {
            Write-Info "Using saved repo URL from ~/.forge/config: $saved"
            return $saved
        }
    }
    return $DEFAULT_REPO
}

# --- Tool checks ---
function Test-Python {
    foreach ($cmd in @("python3", "python")) {
        try {
            $out = & $cmd --version 2>&1
            if ($out -match "(\d+)\.(\d+)") {
                $major = [int]$Matches[1]
                $minor = [int]$Matches[2]
                if ($major -ge 3 -and $minor -ge 9) {
                    $script:PythonCmd = $cmd
                    $script:PythonVersion = "$major.$minor"
                    return $true
                }
            }
        } catch { }
    }
    $script:PythonCmd = ""
    $script:PythonVersion = ""
    return $false
}

function Test-Git {
    try {
        $out = & git --version 2>&1
        if ($out -match "(\d+\.\d+)") {
            $script:GitVersion = $Matches[1]
            return $true
        }
    } catch { }
    $script:GitVersion = ""
    return $false
}

function Test-Copier {
    foreach ($cmd in @($script:PythonCmd, "python3", "python")) {
        if (-not $cmd) { continue }
        try {
            $out = & $cmd -m copier --version 2>&1
            if ($out -match "(\d+)\.(\d+)") {
                $major = [int]$Matches[1]
                if ($major -ge 9) {
                    $script:CopierVersion = "$($Matches[1]).$($Matches[2])"
                    return $true
                }
            }
        } catch { }
    }
    $script:CopierVersion = ""
    return $false
}

function Test-Claude {
    try {
        $out = & claude --version 2>&1
        if ($out -match "(\d+\.\d+\.\d+)") {
            $script:ClaudeVersion = $Matches[1]
        } else {
            $script:ClaudeVersion = "detected"
        }
        return $true
    } catch { }
    $script:ClaudeVersion = ""
    return $false
}

# --- Install missing tools ---
function Install-Git {
    Write-Step "Installing Git..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        & winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        & choco install git -y
    } else {
        Write-Err "Install Git manually: https://git-scm.com/download/win"
        throw "Git installation failed"
    }
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Install-Python {
    Write-Step "Installing Python..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        & winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        & choco install python312 -y
    } else {
        Write-Err "Install Python manually: https://python.org/downloads/"
        throw "Python installation failed"
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Install-Copier {
    Write-Step "Installing Copier..."
    $pipCmd = if ($script:PythonCmd) { $script:PythonCmd } else { "python" }
    & $pipCmd -m pip install "copier>=9.0"
}

# --- Git auth preflight ---
function Test-GitAuth {
    param([string]$RepoUrl)
    Write-Step "Checking repository access..."

    try {
        $null = & git ls-remote $RepoUrl HEAD 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Repository accessible: $RepoUrl"
            return $true
        }
    } catch { }

    Write-Err "Cannot access repository: $RepoUrl"
    Write-Host ""

    switch -Regex ($RepoUrl) {
        "github\.com" {
            Write-Warn "GitHub authentication guidance:"
            Write-Host "    1. SSH: ssh-keygen -t ed25519 && ssh-add ~/.ssh/id_ed25519"
            Write-Host "       Then add the public key at https://github.com/settings/keys"
            Write-Host "    2. HTTPS: gh auth login (GitHub CLI) or configure a Personal Access Token"
        }
        "(dev\.azure\.com|visualstudio\.com)" {
            Write-Warn "Azure DevOps authentication guidance:"
            Write-Host "    1. Generate a PAT in Azure DevOps > User Settings > Personal Access Tokens"
            Write-Host "    2. Git Credential Manager: git config --global credential.helper manager"
        }
        "gitlab" {
            Write-Warn "GitLab authentication guidance:"
            Write-Host "    1. SSH key: https://docs.gitlab.com/ee/user/ssh.html"
            Write-Host "    2. Personal Access Token: Settings > Access Tokens"
        }
        "bitbucket\.org" {
            Write-Warn "Bitbucket authentication guidance:"
            Write-Host "    1. App password: https://bitbucket.org/account/settings/app-passwords/"
            Write-Host "    2. SSH key: https://support.atlassian.com/bitbucket-cloud/docs/set-up-an-ssh-key/"
        }
        default {
            Write-Warn "Authentication guidance:"
            Write-Host "    1. SSH: ensure your SSH key is added to the remote server"
            Write-Host "    2. HTTPS: git config --global credential.helper manager"
        }
    }

    Write-Host ""
    if ($Yes) {
        Write-Err "Non-interactive mode: cannot retry auth. Configure credentials and re-run."
        return $false
    }

    Read-Host "Press Enter to retry after configuring credentials, or Ctrl+C to exit"

    try {
        $null = & git ls-remote $RepoUrl HEAD 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Repository accessible after retry: $RepoUrl"
            return $true
        }
    } catch { }

    Write-Err "Still cannot access repository. Configure credentials and re-run."
    return $false
}

# --- Save config ---
function Save-Config {
    param([string]$Url)
    if (-not (Test-Path $FORGE_CONFIG_DIR)) {
        New-Item -ItemType Directory -Path $FORGE_CONFIG_DIR -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($FORGE_CONFIG_FILE, "repo_url=$Url`n", [System.Text.Encoding]::UTF8)
    Write-Info "Saved repo URL to ~/.forge/config"
}

# --- Plant forge-bootstrap.md ---
function Install-Bootstrap {
    param([string]$RepoUrl)
    Write-Step "Setting up Claude Code integration..."

    if (-not (Test-Path $CLAUDE_CMD_DIR)) {
        New-Item -ItemType Directory -Path $CLAUDE_CMD_DIR -Force | Out-Null
    }

    $target = Join-Path $CLAUDE_CMD_DIR $BOOTSTRAP_FILE
    $content = ""

    if ($RepoUrl -eq $DEFAULT_REPO) {
        $rawUrl = "$RAW_BASE/$BOOTSTRAP_FILE"
        try {
            $content = (Invoke-WebRequest -Uri $rawUrl -UseBasicParsing).Content
        } catch {
            Write-Err "Failed to download $BOOTSTRAP_FILE from $rawUrl"
            throw
        }
    } else {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "forge-install-$(Get-Random)"
        try {
            & git clone --depth 1 $RepoUrl $tmpDir 2>&1 | Out-Null
            $bootstrapPath = Join-Path $tmpDir $BOOTSTRAP_FILE
            if (-not (Test-Path $bootstrapPath)) {
                $bootstrapPath = Join-Path (Join-Path (Join-Path $tmpDir ".claude") "commands") $BOOTSTRAP_FILE
            }
            if (Test-Path $bootstrapPath) {
                $content = Get-Content $bootstrapPath -Raw
            } else {
                Write-Err "$BOOTSTRAP_FILE not found in repository"
                throw "$BOOTSTRAP_FILE not found"
            }
        } finally {
            if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    # Bake repo URL if non-default
    if ($RepoUrl -ne $DEFAULT_REPO) {
        $content += "`n<!-- FORGE Install Config -->`n<!-- repo: $RepoUrl -->"
    }

    # Check if update needed
    if (Test-Path $target) {
        $existing = Get-Content $target -Raw -ErrorAction SilentlyContinue
        if ($existing -eq $content) {
            Write-Info "$BOOTSTRAP_FILE already current"
            return
        }
        [System.IO.File]::WriteAllText($target, $content, [System.Text.Encoding]::UTF8)
        Write-Info "$BOOTSTRAP_FILE updated"
    } else {
        [System.IO.File]::WriteAllText($target, $content, [System.Text.Encoding]::UTF8)
        Write-Info "$BOOTSTRAP_FILE installed to $CLAUDE_CMD_DIR"
    }
}

# --- Bootstrap project ---
function Initialize-Project {
    param([string]$Path, [string]$RepoUrl)
    Write-Step "Bootstrapping project at $Path..."

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    $pipCmd = if ($script:PythonCmd) { $script:PythonCmd } else { "python" }

    # --trust allows Copier to run template tasks/hooks. Warn the user.
    Write-Warn "Copier will run with --trust, which allows the template to execute tasks."
    Write-Host "        Source: $RepoUrl"
    if (Confirm-Action "Proceed with --trust?") {
        & $pipCmd -m copier copy $RepoUrl $Path --defaults --trust
    } else {
        Write-Warn "Running without --trust (template tasks will be skipped)."
        & $pipCmd -m copier copy $RepoUrl $Path --defaults
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Copier failed to bootstrap project at $Path"
        throw "Copier copy failed"
    }

    $answersFile = Join-Path $Path ".copier-answers.yml"
    if (Test-Path $answersFile) {
        Write-Info ".copier-answers.yml created"
    } else {
        Write-Warn ".copier-answers.yml not found - Copier may have encountered an issue"
    }

    # Initialize git if not already a repo
    $gitDir = Join-Path $Path ".git"
    if (-not (Test-Path $gitDir)) {
        & git init $Path 2>&1 | Out-Null
        Write-Info "Initialized git repository at $Path"
    }
}

# =========================================================================
# Main
# =========================================================================

Write-Host ""
Write-Host "  FORGE Installer" -ForegroundColor White
Write-Host "  Framework for Organized Reliable Gated Engineering"
Write-Host ""

# Platform detection (5.1-compatible)
$IsWindowsPlatform = $true
if ($PSVersionTable.PSEdition -eq "Core") {
    $IsWindowsPlatform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )
}
$platform = if ($IsWindowsPlatform) { "Windows" } else { "Cross-platform PowerShell" }
Write-Info "Platform: $platform (PowerShell $($PSVersionTable.PSVersion))"

# Resolve repo URL
$RepoUrl = Resolve-RepoUrl

# Prerequisite check
Write-Step "Checking prerequisites..."

$missing = @()

if (Test-Python) {
    Write-Info "Python $script:PythonVersion"
} else {
    Write-Warn "Python 3.9+ not found"
    $missing += "python"
}

if (Test-Git) {
    Write-Info "Git $script:GitVersion"
} else {
    Write-Warn "Git not found"
    $missing += "git"
}

if (Test-Copier) {
    Write-Info "Copier $script:CopierVersion"
} else {
    Write-Warn "Copier 9.0+ not found"
    $missing += "copier"
}

if (Test-Claude) {
    Write-Info "Claude Code $script:ClaudeVersion"
    $Mode = "claude-code"
} else {
    Write-Warn "Claude Code not detected - using generic install path"
    $Mode = "generic"
}

# Install missing prerequisites
if ($missing.Count -gt 0) {
    Write-Step "Installing missing prerequisites: $($missing -join ', ')"

    foreach ($tool in $missing) {
        switch ($tool) {
            "python" {
                if (Confirm-Action "Install Python 3.12?") {
                    Install-Python
                    if (-not (Test-Python)) {
                        Write-Err "Python installation failed. Install manually and re-run."
                        exit 1
                    }
                    Write-Info "Python $script:PythonVersion installed"
                } else {
                    Write-Err "Python 3.9+ is required. Install manually and re-run."
                    exit 1
                }
            }
            "git" {
                if (Confirm-Action "Install Git?") {
                    Install-Git
                    if (-not (Test-Git)) {
                        Write-Err "Git installation failed. Install manually and re-run."
                        exit 1
                    }
                    Write-Info "Git $script:GitVersion installed"
                } else {
                    Write-Err "Git is required. Install manually and re-run."
                    exit 1
                }
            }
            "copier" {
                if (Confirm-Action "Install Copier (via pip)?") {
                    Install-Copier
                    if (-not (Test-Copier)) {
                        Write-Err "Copier installation failed. Run: pip install 'copier>=9.0'"
                        exit 1
                    }
                    Write-Info "Copier $script:CopierVersion installed"
                } else {
                    Write-Err "Copier 9.0+ is required. Install manually: pip install 'copier>=9.0'"
                    exit 1
                }
            }
        }
    }
} else {
    Write-Info "All prerequisites satisfied"
}

# Git auth preflight
if ($RepoUrl -ne $DEFAULT_REPO -or $Init) {
    if (-not (Test-GitAuth -RepoUrl $RepoUrl)) {
        exit 1
    }
}

# Save config for custom repos
if ($RepoUrl -ne $DEFAULT_REPO) {
    Save-Config -Url $RepoUrl
}

# Claude Code integration
if ($Mode -eq "claude-code") {
    Install-Bootstrap -RepoUrl $RepoUrl
}

# Update mode (early exit)
if ($Update) {
    if ($Mode -eq "claude-code") {
        Write-Info "Update complete."
    } else {
        Write-Warn "--Update only applies to Claude Code (forge-bootstrap.md). Nothing to update."
    }
    exit 0
}

# Bootstrap project if --Init
if ($Init) {
    Initialize-Project -Path $Init -RepoUrl $RepoUrl
}

# Completion summary
Write-Host ""
Write-Step "Done!"
Write-Host ""

$CopierUrl = $RepoUrl -replace "\.git$", ""

if ($Mode -eq "claude-code" -and $Init) {
    Write-Host "  FORGE project bootstrapped at $Init." -ForegroundColor Green
    Write-Host "  Next: Open $Init in Claude Code and run /onboarding"
    Write-Host ""
    Write-Host "  Note: " -ForegroundColor Yellow -NoNewline
    Write-Host "If your IDE is already open, reload the window first"
    Write-Host "        (VS Code: Ctrl+Shift+P > `"Developer: Reload Window`")"
} elseif ($Mode -eq "claude-code") {
    Write-Host "  FORGE installed successfully." -ForegroundColor Green
    Write-Host "  Next: Open any project directory in Claude Code and run /forge-bootstrap"
    Write-Host ""
    Write-Host "  Note: " -ForegroundColor Yellow -NoNewline
    Write-Host "If your IDE is already open, reload the window so it picks"
    Write-Host "        up the new command (VS Code: Ctrl+Shift+P > `"Developer: Reload Window`")"
} elseif ($Mode -eq "generic" -and $Init) {
    Write-Host "  FORGE project bootstrapped at $Init." -ForegroundColor Green
    Write-Host "  Next: Open $Init in your AI-assisted IDE."
    Write-Host "        Your assistant will read AGENTS.md and guide you through setup."
} else {
    Write-Host "  FORGE prerequisites installed." -ForegroundColor Green
    Write-Host "  Next steps:"
    Write-Host "    1. Create a project:  copier copy $CopierUrl my-project"
    Write-Host "    2. Open my-project/ in your AI-assisted IDE (Cursor, Windsurf, Copilot, etc.)"
    Write-Host "    3. Your assistant will read AGENTS.md and guide you through setup"
    Write-Host ""
    Write-Host "  Tip: If you install Claude Code later, re-run this script to add the"
    Write-Host "       /forge-bootstrap command for the fastest experience."
}

Write-Host ""
Write-Host "  Docs: $DOCS_URL"
Write-Host ""

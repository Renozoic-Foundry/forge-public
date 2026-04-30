#!/usr/bin/env bash
# FORGE Installer — Universal entry point
# Usage: curl -fsSL https://raw.githubusercontent.com/Renozoic-Foundry/forge-public/main/install.sh | bash
#        bash install.sh [--repo <url>] [--init <path>] [--update] [--yes]
#
# Detects environment (Claude Code or generic) and adapts behavior.
# See: https://github.com/Renozoic-Foundry/forge-public

set -euo pipefail

# --- Constants ---
DEFAULT_REPO="https://github.com/Renozoic-Foundry/forge-public.git"
RAW_BASE="https://raw.githubusercontent.com/Renozoic-Foundry/forge-public/main"
FORGE_CONFIG_DIR="$HOME/.forge"
FORGE_CONFIG_FILE="$FORGE_CONFIG_DIR/config"
CLAUDE_CMD_DIR="$HOME/.claude/commands"
BOOTSTRAP_FILE="forge-bootstrap.md"
DOCS_URL="https://github.com/Renozoic-Foundry/forge-public#readme"

# --- Color output (disabled if not a terminal) ---
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN='' YELLOW='' RED='' BLUE='' BOLD='' NC=''
fi

# --- Utility functions ---
info()  { printf "${GREEN}✓${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}!${NC} %s\n" "$1"; }
error() { printf "${RED}✗${NC} %s\n" "$1" >&2; }
step()  { printf "\n${BOLD}%s${NC}\n" "$1"; }

confirm() {
    if [ "$YES" = "true" ]; then
        return 0
    fi
    local prompt="$1"
    printf "%s [Y/n] " "$prompt"
    read -r response </dev/tty || response="y"
    case "$response" in
        [nN]*) return 1 ;;
        *) return 0 ;;
    esac
}

# --- Parse arguments ---
REPO_URL=""
INIT_PATH=""
UPDATE=false
YES=false

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)
            shift
            REPO_URL="${1:-}"
            if [ -z "$REPO_URL" ]; then
                error "--repo requires a URL argument"
                exit 1
            fi
            ;;
        --init)
            shift
            INIT_PATH="${1:-}"
            if [ -z "$INIT_PATH" ]; then
                error "--init requires a path argument"
                exit 1
            fi
            ;;
        --update) UPDATE=true ;;
        --yes|-y) YES=true ;;
        --help|-h)
            cat <<'USAGE'
FORGE Installer — Universal entry point

Usage:
  bash install.sh [OPTIONS]
  curl -fsSL <url>/install.sh | bash
  curl -fsSL <url>/install.sh | bash -s -- [OPTIONS]

Options:
  --repo <url>    Use a custom template repository (private fork)
  --init <path>   Also bootstrap a project at <path> via Copier
  --update        Refresh forge-bootstrap.md to latest version (Claude Code only)
  --yes, -y       Non-interactive mode (skip confirmation prompts)
  --help, -h      Show this help

Examples:
  bash install.sh                                    # Install prereqs + detect Claude Code
  bash install.sh --init my-project                  # Install + bootstrap a project
  bash install.sh --repo https://github.com/myorg/forge-private.git
  bash install.sh --repo git@github.com:myorg/forge.git --init .
USAGE
            exit 0
            ;;
        *)
            error "Unknown option: $1 (try --help)"
            exit 1
            ;;
    esac
    shift
done

# --- Repo URL resolution (--repo > config file > default) ---
resolve_repo_url() {
    if [ -n "$REPO_URL" ]; then
        return
    fi
    if [ -f "$FORGE_CONFIG_FILE" ]; then
        local saved
        saved=$(grep -m1 '^repo_url=' "$FORGE_CONFIG_FILE" 2>/dev/null | cut -d= -f2-)
        if [ -n "$saved" ]; then
            REPO_URL="$saved"
            info "Using saved repo URL from ~/.forge/config: $REPO_URL"
            return
        fi
    fi
    REPO_URL="$DEFAULT_REPO"
}

# --- Raw URL builder (for downloading files from the repo) ---
raw_url_for() {
    local file="$1"
    if [ "$REPO_URL" = "$DEFAULT_REPO" ]; then
        printf "%s/%s" "$RAW_BASE" "$file"
    else
        # For non-default repos, we'll clone to a temp dir instead
        printf ""
    fi
}

# --- Detect platform ---
detect_platform() {
    local uname_s
    uname_s=$(uname -s 2>/dev/null || echo "Unknown")
    case "$uname_s" in
        Darwin)  PLATFORM="macos" ;;
        Linux)   PLATFORM="linux" ;;
        MINGW*|MSYS*|CYGWIN*)  PLATFORM="windows-bash" ;;
        *)       PLATFORM="unknown" ;;
    esac
}

# --- Detect Linux distro ---
detect_distro() {
    if [ "$PLATFORM" != "linux" ]; then
        DISTRO="none"
        return
    fi
    if command -v apt-get >/dev/null 2>&1; then
        DISTRO="debian"
    elif command -v dnf >/dev/null 2>&1; then
        DISTRO="fedora"
    elif command -v pacman >/dev/null 2>&1; then
        DISTRO="arch"
    elif command -v apk >/dev/null 2>&1; then
        DISTRO="alpine"
    else
        DISTRO="unknown"
    fi
}

# --- Check a tool and its version ---
check_python() {
    local cmd version major minor
    for cmd in python3 python; do
        if command -v "$cmd" >/dev/null 2>&1; then
            version=$("$cmd" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
            major=$(echo "$version" | cut -d. -f1)
            minor=$(echo "$version" | cut -d. -f2)
            if [ "$major" -ge 3 ] && [ "$minor" -ge 9 ] 2>/dev/null; then
                PYTHON_CMD="$cmd"
                PYTHON_VERSION="$version"
                return 0
            fi
        fi
    done
    PYTHON_CMD=""
    PYTHON_VERSION=""
    return 1
}

check_git() {
    if command -v git >/dev/null 2>&1; then
        GIT_VERSION=$(git --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        return 0
    fi
    GIT_VERSION=""
    return 1
}

check_copier() {
    local version major
    COPIER_VERSION=""
    COPIER_SOURCE=""

    # Prefer standalone `copier` binary on PATH (Homebrew, pipx, winget — isolated env, more reliable)
    if command -v copier >/dev/null 2>&1; then
        version=$(copier --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1) || version=""
        if [ -n "$version" ]; then
            major=$(echo "$version" | cut -d. -f1)
            if [ "$major" -ge 9 ] 2>/dev/null; then
                COPIER_VERSION="$version"
                COPIER_SOURCE="binary"
                return 0
            fi
        fi
    fi

    # Fallback: `python -m copier` (pip --user, venv, system install)
    for cmd in "${PYTHON_CMD:-}" python3 python; do
        if [ -n "$cmd" ] && command -v "$cmd" >/dev/null 2>&1; then
            version=$("$cmd" -m copier --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1) || continue
            if [ -n "$version" ]; then
                major=$(echo "$version" | cut -d. -f1)
                if [ "$major" -ge 9 ] 2>/dev/null; then
                    COPIER_VERSION="$version"
                    COPIER_SOURCE="python-module ($cmd)"
                    return 0
                fi
            fi
        fi
    done
    return 1
}

check_claude() {
    if command -v claude >/dev/null 2>&1; then
        CLAUDE_VERSION=$(claude --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || CLAUDE_VERSION="detected"
        return 0
    fi
    CLAUDE_VERSION=""
    return 1
}

# --- Install missing tools ---
install_git() {
    step "Installing Git..."
    case "$PLATFORM" in
        macos)
            if command -v brew >/dev/null 2>&1; then
                brew install git
            else
                warn "Homebrew not found. Install Git manually: https://git-scm.com/download/mac"
                warn "Or install Homebrew first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                return 1
            fi
            ;;
        linux)
            case "$DISTRO" in
                debian)  sudo apt-get update && sudo apt-get install -y git ;;
                fedora)  sudo dnf install -y git ;;
                arch)    sudo pacman -S --noconfirm git ;;
                alpine)  sudo apk add git ;;
                *)       error "Cannot auto-install git on this Linux distribution. Install manually: https://git-scm.com/download/linux"; return 1 ;;
            esac
            ;;
        windows-bash)
            if command -v winget >/dev/null 2>&1; then
                winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
            else
                warn "Install Git for Windows: https://git-scm.com/download/win"
                return 1
            fi
            ;;
        *)
            error "Cannot auto-install git on this platform. Install manually: https://git-scm.com/"
            return 1
            ;;
    esac
}

install_python() {
    step "Installing Python..."
    case "$PLATFORM" in
        macos)
            if command -v brew >/dev/null 2>&1; then
                brew install python@3.12
            else
                warn "Homebrew not found. Install Python manually: https://python.org/downloads/"
                warn "Or install Homebrew first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                return 1
            fi
            ;;
        linux)
            case "$DISTRO" in
                debian)  sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-venv ;;
                fedora)  sudo dnf install -y python3 python3-pip ;;
                arch)    sudo pacman -S --noconfirm python python-pip ;;
                alpine)  sudo apk add python3 py3-pip ;;
                *)       error "Cannot auto-install Python on this Linux distribution. Install manually: https://python.org/downloads/"; return 1 ;;
            esac
            ;;
        windows-bash)
            if command -v winget >/dev/null 2>&1; then
                winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements
            else
                warn "Install Python: https://python.org/downloads/"
                return 1
            fi
            ;;
        *)
            error "Cannot auto-install Python on this platform. Install manually: https://python.org/downloads/"
            return 1
            ;;
    esac
}

# Detect PEP 668 "externally-managed-environment" on the active Python interpreter.
# Returns 0 (true) if pip would refuse bare `pip install` without --user/venv.
# Spec 306 — never use --break-system-packages.
is_pep668_managed() {
    local py="${1:-}"
    [ -z "$py" ] && return 1
    command -v "$py" >/dev/null 2>&1 || return 1
    # Probe with a harmless dry-run — pip emits "externally-managed-environment" on managed Pythons.
    # `pip install --dry-run` is available in pip 22.2+; fall back to checking for EXTERNALLY-MANAGED marker.
    local probe
    probe=$("$py" -m pip install --dry-run --quiet --no-input pip 2>&1) || true
    if printf "%s" "$probe" | grep -qi 'externally-managed-environment'; then
        return 0
    fi
    # Secondary check: stdlib sysconfig reports the marker file path; presence means PEP 668.
    if "$py" - <<'PYEOF' 2>/dev/null
import sys, os, sysconfig
stdlib = sysconfig.get_path("stdlib")
if stdlib and os.path.exists(os.path.join(os.path.dirname(stdlib), "EXTERNALLY-MANAGED")):
    sys.exit(0)
sys.exit(1)
PYEOF
    then
        return 0
    fi
    return 1
}

install_copier() {
    step "Installing Copier..."
    local attempted=()
    COPIER_INSTALL_PATH=""

    # Tier 1: Homebrew on macOS (standalone binary — cleanest, survives PEP 668).
    if [ "${PLATFORM:-}" = "macos" ] && command -v brew >/dev/null 2>&1; then
        info "Attempting: brew install copier"
        attempted+=("brew")
        if brew install copier; then
            COPIER_INSTALL_PATH="brew"
            return 0
        fi
        warn "brew install copier failed — trying pipx"
    fi

    # Tier 2: pipx (isolated environment, standalone binary on PATH, avoids PEP 668).
    if command -v pipx >/dev/null 2>&1; then
        info "Attempting: pipx install 'copier>=9.0'"
        attempted+=("pipx")
        if pipx install "copier>=9.0"; then
            COPIER_INSTALL_PATH="pipx"
            # pipx binaries land in ~/.local/bin — ensure PATH hint for this shell
            if [ -d "$HOME/.local/bin" ]; then
                case ":$PATH:" in
                    *":$HOME/.local/bin:"*) ;;
                    *) export PATH="$HOME/.local/bin:$PATH" ;;
                esac
            fi
            return 0
        fi
        warn "pipx install failed — trying pip --user"
    fi

    # Determine the Python we'll target for --user / venv fallbacks.
    local py="${PYTHON_CMD:-}"
    if [ -z "$py" ]; then
        if command -v python3 >/dev/null 2>&1; then py="python3"
        elif command -v python >/dev/null 2>&1; then py="python"
        fi
    fi

    # Tier 3: pip install --user (works on most PEP 668 systems; user scheme bypasses the marker).
    if [ -n "$py" ]; then
        info "Attempting: $py -m pip install --user 'copier>=9.0'"
        attempted+=("pip --user")
        if "$py" -m pip install --user "copier>=9.0"; then
            COPIER_INSTALL_PATH="pip --user"
            # Ensure user-site bin is on PATH for this shell
            local user_base
            user_base=$("$py" -m site --user-base 2>/dev/null || printf "")
            if [ -n "$user_base" ] && [ -d "$user_base/bin" ]; then
                case ":$PATH:" in
                    *":$user_base/bin:"*) ;;
                    *) export PATH="$user_base/bin:$PATH" ;;
                esac
            fi
            return 0
        fi
        warn "pip --user install failed — trying venv fallback"
    fi

    # Tier 4: dedicated venv at ~/.forge/venv (last resort; works even on PEP 668).
    if [ -n "$py" ]; then
        local venv_dir="$FORGE_CONFIG_DIR/venv"
        info "Attempting: venv fallback at $venv_dir"
        attempted+=("venv")
        mkdir -p "$FORGE_CONFIG_DIR"
        if "$py" -m venv "$venv_dir"; then
            local venv_py="$venv_dir/bin/python"
            [ -x "$venv_py" ] || venv_py="$venv_dir/Scripts/python.exe"
            if [ -x "$venv_py" ] && "$venv_py" -m pip install "copier>=9.0"; then
                COPIER_INSTALL_PATH="venv ($venv_dir)"
                local venv_bin="$venv_dir/bin"
                [ -d "$venv_bin" ] || venv_bin="$venv_dir/Scripts"
                if [ -d "$venv_bin" ]; then
                    case ":$PATH:" in
                        *":$venv_bin:"*) ;;
                        *) export PATH="$venv_bin:$PATH" ;;
                    esac
                fi
                return 0
            fi
        fi
    fi

    # All tiers failed — emit actionable guidance. Never suggest --break-system-packages.
    error "Failed to install Copier. Attempted: ${attempted[*]:-none}"
    if [ -n "$py" ] && is_pep668_managed "$py"; then
        warn "Detected PEP 668 externally-managed Python at '$py'."
        warn "Bare 'pip install' is disallowed by this Python; FORGE will NOT override with --break-system-packages."
    fi
    echo ""
    echo "  Try one of these manually:"
    if [ "${PLATFORM:-}" = "macos" ]; then
        echo "    1. brew install copier                         (recommended on macOS)"
    fi
    echo "    2. pipx install 'copier>=9.0'                  (recommended — isolated env)"
    echo "       (install pipx first: python3 -m pip install --user pipx && pipx ensurepath)"
    echo "    3. python3 -m pip install --user 'copier>=9.0' (user install)"
    echo "    4. python3 -m venv ~/.forge/venv && ~/.forge/venv/bin/pip install 'copier>=9.0'"
    return 1
}

# --- Git auth preflight ---
git_auth_preflight() {
    local repo="$1"
    step "Checking repository access..."

    if git ls-remote "$repo" HEAD >/dev/null 2>&1; then
        info "Repository accessible: $repo"
        return 0
    fi

    error "Cannot access repository: $repo"
    echo ""

    # Detect provider from URL and show targeted guidance
    case "$repo" in
        *github.com*)
            warn "GitHub authentication guidance:"
            echo "  1. SSH: ssh-keygen -t ed25519 && ssh-add ~/.ssh/id_ed25519"
            echo "     Then add the public key at https://github.com/settings/keys"
            echo "  2. HTTPS: gh auth login (GitHub CLI) or configure a Personal Access Token"
            echo "     https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token"
            ;;
        *dev.azure.com*|*visualstudio.com*)
            warn "Azure DevOps authentication guidance:"
            echo "  1. Generate a PAT: https://dev.azure.com/<org>/_usersSettings/tokens"
            echo "  2. SSH: https://learn.microsoft.com/en-us/azure/devops/repos/git/use-ssh-keys-to-authenticate"
            echo "  3. Credential manager: git config --global credential.helper manager"
            ;;
        *gitlab.com*|*gitlab.*)
            warn "GitLab authentication guidance:"
            echo "  1. SSH key: https://docs.gitlab.com/ee/user/ssh.html"
            echo "  2. Personal Access Token: https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html"
            echo "  3. Deploy token (read-only): Settings > Repository > Deploy tokens"
            ;;
        *bitbucket.org*)
            warn "Bitbucket authentication guidance:"
            echo "  1. App password: https://bitbucket.org/account/settings/app-passwords/"
            echo "  2. SSH key: https://support.atlassian.com/bitbucket-cloud/docs/set-up-an-ssh-key/"
            ;;
        *)
            warn "Authentication guidance (generic):"
            echo "  1. SSH: ensure your SSH key is added to the remote server"
            echo "  2. HTTPS: configure git credential helper: git config --global credential.helper store"
            ;;
    esac

    echo ""
    if [ "$YES" = "true" ]; then
        error "Non-interactive mode: cannot retry auth. Configure credentials and re-run."
        return 1
    fi

    printf "Press Enter to retry after configuring credentials, or Ctrl+C to exit..."
    read -r </dev/tty

    if git ls-remote "$repo" HEAD >/dev/null 2>&1; then
        info "Repository accessible after retry: $repo"
        return 0
    fi

    error "Still cannot access repository. Configure credentials and re-run."
    return 1
}

# --- Save persistent config ---
save_config() {
    local url="$1"
    mkdir -p "$FORGE_CONFIG_DIR"
    printf "repo_url=%s\n" "$url" > "$FORGE_CONFIG_FILE"
    info "Saved repo URL to ~/.forge/config"
}

# --- Plant forge-bootstrap.md (Claude Code mode) ---
plant_bootstrap() {
    local repo="$1"
    local target="$CLAUDE_CMD_DIR/$BOOTSTRAP_FILE"
    local content=""
    local raw_url

    mkdir -p "$CLAUDE_CMD_DIR"

    raw_url=$(raw_url_for "$BOOTSTRAP_FILE")

    if [ -n "$raw_url" ]; then
        # Public repo: download directly
        content=$(curl -fsSL "$raw_url") || {
            error "Failed to download $BOOTSTRAP_FILE from $raw_url"
            return 1
        }
    else
        # Private repo: clone to temp dir and extract
        local tmp_dir
        tmp_dir=$(mktemp -d)
        trap 'rm -rf "$tmp_dir"' RETURN
        if git clone --depth 1 "$repo" "$tmp_dir/forge-repo" >/dev/null 2>&1; then
            if [ -f "$tmp_dir/forge-repo/$BOOTSTRAP_FILE" ]; then
                content=$(cat "$tmp_dir/forge-repo/$BOOTSTRAP_FILE")
            elif [ -f "$tmp_dir/forge-repo/.claude/commands/$BOOTSTRAP_FILE" ]; then
                content=$(cat "$tmp_dir/forge-repo/.claude/commands/$BOOTSTRAP_FILE")
            else
                error "$BOOTSTRAP_FILE not found in repository"
                rm -rf "$tmp_dir"
                return 1
            fi
        else
            error "Failed to clone repository for bootstrap file"
            rm -rf "$tmp_dir"
            return 1
        fi
        rm -rf "$tmp_dir"
        trap - RETURN
    fi

    # Bake repo URL into the command file if non-default
    if [ "$repo" != "$DEFAULT_REPO" ]; then
        content="$content
<!-- FORGE Install Config -->
<!-- repo: $repo -->"
    fi

    # Check if update needed
    if [ -f "$target" ]; then
        local existing
        existing=$(cat "$target")
        if [ "$existing" = "$content" ]; then
            info "$BOOTSTRAP_FILE already current"
            return 0
        fi
        printf "%s" "$content" > "$target"
        info "$BOOTSTRAP_FILE updated"
    else
        printf "%s" "$content" > "$target"
        info "$BOOTSTRAP_FILE installed to $CLAUDE_CMD_DIR/"
    fi
}

# --- Bootstrap a project with --init ---
init_project() {
    local path="$1"
    local repo="$2"

    step "Bootstrapping project at $path..."

    if [ ! -d "$path" ]; then
        mkdir -p "$path"
    fi

    # Spec 306 — prefer standalone `copier` binary when available (handles brew/pipx/winget installs).
    # Fall back to `python -m copier` for --user / venv installs.
    local copier_invoker=()
    if command -v copier >/dev/null 2>&1; then
        copier_invoker=(copier)
    elif [ -n "${PYTHON_CMD:-}" ]; then
        copier_invoker=("$PYTHON_CMD" -m copier)
    elif command -v python3 >/dev/null 2>&1; then
        copier_invoker=(python3 -m copier)
    else
        copier_invoker=(python -m copier)
    fi

    # --trust allows Copier to run template tasks/hooks. Warn the user.
    warn "Copier will run with --trust, which allows the template to execute tasks."
    printf "        Source: %s\n" "$repo"
    if ! confirm "Proceed with --trust?"; then
        warn "Running without --trust (template tasks will be skipped)."
        "${copier_invoker[@]}" copy "$repo" "$path" --defaults || {
            error "Copier failed to bootstrap project at $path"
            return 1
        }
        return 0
    fi

    "${copier_invoker[@]}" copy "$repo" "$path" --defaults --trust || {
        error "Copier failed to bootstrap project at $path"
        return 1
    }

    if [ -f "$path/.copier-answers.yml" ]; then
        info ".copier-answers.yml created"
    else
        warn ".copier-answers.yml not found — Copier may have encountered an issue"
    fi

    # Initialize git if not already a repo
    if [ ! -d "$path/.git" ]; then
        git init "$path" >/dev/null 2>&1
        info "Initialized git repository at $path"
    fi
}

# =========================================================================
# Main
# =========================================================================

printf "\n${BOLD}FORGE Installer${NC}\n"
printf "Framework for Organized Reliable Gated Engineering\n\n"

# Step 1: Detect platform
detect_platform
detect_distro
info "Platform: $PLATFORM${DISTRO:+" ($DISTRO)"}"

# Step 2: Resolve repo URL
resolve_repo_url

# Step 3: Prerequisite check
step "Checking prerequisites..."

MISSING=()

if check_python; then
    info "Python $PYTHON_VERSION"
else
    warn "Python 3.9+ not found"
    MISSING+=("python")
fi

if check_git; then
    info "Git $GIT_VERSION"
else
    warn "Git not found"
    MISSING+=("git")
fi

if check_copier; then
    info "Copier $COPIER_VERSION"
else
    warn "Copier 9.0+ not found"
    MISSING+=("copier")
fi

if check_claude; then
    info "Claude Code $CLAUDE_VERSION"
    MODE="claude-code"
else
    warn "Claude Code not detected — using generic install path"
    MODE="generic"
fi

# Step 4: Install missing prerequisites
if [ ${#MISSING[@]} -gt 0 ]; then
    step "Installing missing prerequisites: ${MISSING[*]}"

    for tool in "${MISSING[@]}"; do
        case "$tool" in
            python)
                if confirm "Install Python 3.12?"; then
                    install_python
                    check_python || { error "Python installation failed. Install manually and re-run."; exit 1; }
                    info "Python $PYTHON_VERSION installed"
                else
                    error "Python 3.9+ is required. Install manually and re-run."
                    exit 1
                fi
                ;;
            git)
                if confirm "Install Git?"; then
                    install_git
                    check_git || { error "Git installation failed. Install manually and re-run."; exit 1; }
                    info "Git $GIT_VERSION installed"
                else
                    error "Git is required. Install manually and re-run."
                    exit 1
                fi
                ;;
            copier)
                if confirm "Install Copier (brew/pipx/pip --user — auto-selected)?"; then
                    install_copier || {
                        error "Copier installation failed across all tiers. See guidance above."
                        exit 1
                    }
                    check_copier || {
                        error "Copier installed but not detected on PATH. Restart your shell and re-run, or inspect: ${COPIER_INSTALL_PATH:-unknown path}"
                        exit 1
                    }
                    info "Copier $COPIER_VERSION installed via ${COPIER_INSTALL_PATH:-unknown} (detected as: ${COPIER_SOURCE:-unknown})"
                else
                    error "Copier 9.0+ is required. Install manually: brew install copier | pipx install 'copier>=9.0' | python3 -m pip install --user 'copier>=9.0'"
                    exit 1
                fi
                ;;
        esac
    done
else
    info "All prerequisites satisfied"
fi

# Step 5: Git auth preflight (when using non-default repo or --init)
if [ "$REPO_URL" != "$DEFAULT_REPO" ] || [ -n "$INIT_PATH" ]; then
    git_auth_preflight "$REPO_URL"
fi

# Step 6: Save config for custom repos
if [ "$REPO_URL" != "$DEFAULT_REPO" ]; then
    save_config "$REPO_URL"
fi

# Step 7: Environment-specific setup
if [ "$MODE" = "claude-code" ]; then
    step "Setting up Claude Code integration..."
    plant_bootstrap "$REPO_URL"
fi

# Step 8: Update mode (early exit)
if [ "$UPDATE" = "true" ]; then
    if [ "$MODE" = "claude-code" ]; then
        info "Update complete."
    else
        warn "--update only applies to Claude Code (forge-bootstrap.md). Nothing to update."
    fi
    exit 0
fi

# Step 9: Bootstrap project if --init
if [ -n "$INIT_PATH" ]; then
    init_project "$INIT_PATH" "$REPO_URL"
fi

# Step 10: Completion summary
step "Done!"
echo ""

COPIER_URL="${REPO_URL%.git}"
if echo "$COPIER_URL" | grep -q "github.com"; then
    COPIER_SHORT="${COPIER_URL//https:\/\/github.com\//}"
else
    COPIER_SHORT="$COPIER_URL"
fi

if [ "$MODE" = "claude-code" ] && [ -n "$INIT_PATH" ]; then
    printf "  ${GREEN}FORGE project bootstrapped at %s.${NC}\n" "$INIT_PATH"
    printf "  Next: Open %s in Claude Code and run ${BOLD}/onboarding${NC}\n" "$INIT_PATH"
    echo ""
    printf "  ${YELLOW}Note:${NC} If your IDE is already open, reload the window first\n"
    printf "        (VS Code: Ctrl+Shift+P → \"Developer: Reload Window\")\n"
elif [ "$MODE" = "claude-code" ]; then
    printf "  ${GREEN}FORGE installed successfully.${NC}\n"
    printf "  Next: Open any project directory in Claude Code and run ${BOLD}/forge-bootstrap${NC}\n"
    echo ""
    printf "  ${YELLOW}Note:${NC} If your IDE is already open, reload the window so it picks\n"
    printf "        up the new command (VS Code: Ctrl+Shift+P → \"Developer: Reload Window\")\n"
elif [ "$MODE" = "generic" ] && [ -n "$INIT_PATH" ]; then
    printf "  ${GREEN}FORGE project bootstrapped at %s.${NC}\n" "$INIT_PATH"
    printf "  Next: Open %s in your AI-assisted IDE.\n" "$INIT_PATH"
    printf "        Your assistant will read AGENTS.md and guide you through setup.\n"
else
    printf "  ${GREEN}FORGE prerequisites installed.${NC}\n"
    printf "  Next steps:\n"
    printf "    1. Create a project:  copier copy %s my-project\n" "$COPIER_URL"
    printf "    2. Open my-project/ in your AI-assisted IDE (Cursor, Windsurf, Copilot, etc.)\n"
    printf "    3. Your assistant will read AGENTS.md and guide you through setup\n"
    echo ""
    printf "  Tip: If you install Claude Code later, re-run this script to add the\n"
    printf "       /forge-bootstrap command for the fastest experience.\n"
fi

echo ""
printf "  Docs: %s\n" "$DOCS_URL"
echo ""

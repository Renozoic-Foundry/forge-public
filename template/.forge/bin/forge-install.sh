#!/usr/bin/env bash
# FORGE forge-install — user-level FORGE installation and management
# Installs FORGE libraries, commands, and agent integrations to ~/.forge/
# Usage: forge-install.sh [--agents LIST] [--scope user|project|both] [--update] [--uninstall] [--dry-run]
set -euo pipefail

# --- Constants ---
# shellcheck disable=SC2034
readonly FORGE_MANAGED_HEADER="# Managed by FORGE — do not edit manually"
readonly FORGE_COMMAND_HEADER="# Framework: FORGE"
readonly SCRIPT_VERSION="0.1.0"

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Inline minimal logging (standalone fallback) ---
_log_info()  { printf '[✓] %s\n' "$1" >&2; }
_log_warn()  { printf '[!] %s\n' "$1" >&2; }
_log_error() { printf '[✗] %s\n' "$1" >&2; }
_log_step()  { printf '\n=== %s ===\n' "$1" >&2; }
_log_debug() { if [[ "${FORGE_LOG_LEVEL:-}" == "DEBUG" ]]; then printf '[.] %s\n' "$1" >&2; fi; }

# Try to source the real logging library
_FORGE_LIB_DIR="${SCRIPT_DIR}/../lib"
if [[ -f "${_FORGE_LIB_DIR}/logging.sh" ]]; then
  FORGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
  PROJECT_DIR="$(cd "${FORGE_DIR}/.." && pwd)"  # used by logging.sh
  export PROJECT_DIR
  # shellcheck source=../lib/logging.sh
  source "${_FORGE_LIB_DIR}/logging.sh"
  forge_log_init "forge-install"
  _log_info()  { forge_log_info  "$1"; }
  _log_warn()  { forge_log_warn  "$1"; }
  _log_error() { forge_log_error "$1"; }
  _log_step()  { forge_log_step  "$1"; }
  _log_debug() { forge_log_debug "$1"; }
fi

# --- Defaults ---
AGENTS_ARG=""
UPDATE_MODE=false
UNINSTALL_MODE=false
SCOPE="user"
SOURCE_PATH=""
DRY_RUN=false
CHECK_PREREQS=false
SKIP_PREREQS=false

# --- Parse arguments ---
show_help() {
  cat <<'USAGE'
forge-install.sh — User-level FORGE installation

Usage:
  forge-install.sh [OPTIONS]

Options:
  --agents <list>       Comma-separated agent list:
                        codex,claude-code,cursor,copilot,cline,windsurf
                        Default: auto-detect installed agents
  --scope <scope>       Where to install: user, project, or both (default: user)
  --source <path>       Path to FORGE template repo (default: auto-detect)
  --update              Update existing installation
  --uninstall           Remove all user-level FORGE files
  --check-prereqs       Check prerequisites and offer to install missing ones
  --skip-prereqs        Skip prerequisite checks
  --dry-run             Show what would be done without doing it
  -h, --help            Show this help

Exit codes:
  0  Success
  1  Error
  2  Invalid arguments

Examples:
  forge-install.sh                              # Install with auto-detected agents
  forge-install.sh --agents codex,claude-code   # Install for specific agents
  forge-install.sh --update                     # Update existing installation
  forge-install.sh --uninstall                  # Remove user-level FORGE
  forge-install.sh --dry-run                    # Preview install actions
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agents)
      [[ $# -lt 2 ]] && { _log_error "--agents requires a value"; exit 2; }
      AGENTS_ARG="$2"
      shift 2
      ;;
    --update)
      UPDATE_MODE=true
      shift
      ;;
    --uninstall)
      UNINSTALL_MODE=true
      shift
      ;;
    --scope)
      [[ $# -lt 2 ]] && { _log_error "--scope requires a value"; exit 2; }
      SCOPE="$2"
      if [[ "$SCOPE" != "user" && "$SCOPE" != "project" && "$SCOPE" != "both" ]]; then
        _log_error "Invalid scope: $SCOPE (must be user, project, or both)"
        exit 2
      fi
      shift 2
      ;;
    --source)
      [[ $# -lt 2 ]] && { _log_error "--source requires a value"; exit 2; }
      SOURCE_PATH="$2"
      shift 2
      ;;
    --check-prereqs)
      CHECK_PREREQS=true
      shift
      ;;
    --skip-prereqs)
      SKIP_PREREQS=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      _log_error "Unknown argument: $1"
      show_help
      exit 2
      ;;
  esac
done

# --- Prerequisite checks (Spec 143) ---
detect_package_manager() {
  if command -v brew &>/dev/null; then echo "brew"
  elif command -v scoop &>/dev/null; then echo "scoop"
  elif command -v winget &>/dev/null; then echo "winget"
  elif command -v apt-get &>/dev/null; then echo "apt"
  elif command -v dnf &>/dev/null; then echo "dnf"
  elif command -v pacman &>/dev/null; then echo "pacman"
  else echo "none"
  fi
}

check_python() {
  local py_cmd=""
  if command -v python3 &>/dev/null; then py_cmd="python3"
  elif command -v python &>/dev/null; then py_cmd="python"
  fi
  if [[ -z "$py_cmd" ]]; then
    echo "missing"
    return
  fi
  local version
  version=$($py_cmd --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
  local major minor
  major=$(echo "$version" | cut -d. -f1)
  minor=$(echo "$version" | cut -d. -f2)
  if [[ "$major" -ge 3 && "$minor" -ge 9 ]]; then
    echo "ok:$py_cmd:$version"
  else
    echo "old:$py_cmd:$version"
  fi
}

check_git() {
  if command -v git &>/dev/null; then
    local version
    version=$(git --version | grep -oP '\d+\.\d+' | head -1)
    echo "ok:$version"
  else
    echo "missing"
  fi
}

check_git_bash() {
  # Windows only — check for Git Bash
  if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || -n "${WINDIR:-}" ]]; then
    if [[ -f "/c/Program Files/Git/bin/bash.exe" ]] || [[ -f "/usr/bin/bash" ]]; then
      echo "ok"
    else
      echo "missing"
    fi
  else
    echo "n/a"  # not Windows
  fi
}

check_copier() {
  local py_cmd="python3"
  command -v python3 &>/dev/null || py_cmd="python"
  if $py_cmd -m copier --version &>/dev/null 2>&1; then
    local version
    version=$($py_cmd -m copier --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
    local major
    major=$(echo "$version" | cut -d. -f1)
    if [[ "$major" -ge 9 ]]; then
      echo "ok:$version"
    else
      echo "old:$version"
    fi
  else
    echo "missing"
  fi
}

check_shellcheck() {
  if command -v shellcheck &>/dev/null; then
    echo "ok"
  else
    echo "missing"
  fi
}

offer_install() {
  local tool="$1"
  local pkg_mgr="$2"
  local install_cmd=""

  case "$tool" in
    python)
      case "$pkg_mgr" in
        brew)   install_cmd="brew install python" ;;
        scoop)  install_cmd="scoop install python" ;;
        winget) install_cmd="winget install Python.Python.3.12" ;;
        apt)    install_cmd="sudo apt-get install -y python3 python3-pip" ;;
        dnf)    install_cmd="sudo dnf install -y python3 python3-pip" ;;
        pacman) install_cmd="sudo pacman -S --noconfirm python python-pip" ;;
      esac
      ;;
    git)
      case "$pkg_mgr" in
        brew)   install_cmd="brew install git" ;;
        scoop)  install_cmd="scoop install git" ;;
        winget) install_cmd="winget install Git.Git" ;;
        apt)    install_cmd="sudo apt-get install -y git" ;;
        dnf)    install_cmd="sudo dnf install -y git" ;;
        pacman) install_cmd="sudo pacman -S --noconfirm git" ;;
      esac
      ;;
    copier)
      install_cmd="pip install copier"
      ;;
    shellcheck)
      install_cmd="pip install shellcheck-py"
      ;;
  esac

  if [[ -z "$install_cmd" ]]; then
    _log_warn "  No auto-install available for $tool on this platform. Install manually."
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    _log_info "  Would run: $install_cmd"
    return 0
  fi

  printf "  Install via: %s\n  Proceed? (yes/no/skip) " "$install_cmd"
  read -r answer
  case "$answer" in
    yes|y|Y)
      _log_info "  Installing $tool..."
      if eval "$install_cmd"; then
        _log_info "  $tool installed successfully."
        return 0
      else
        _log_error "  $tool installation failed. Install manually: $install_cmd"
        return 1
      fi
      ;;
    *)
      _log_warn "  Skipped $tool installation."
      return 1
      ;;
  esac
}

run_prereq_checks() {
  _log_step "Prerequisite Check"
  local pkg_mgr missing=0 advisory=0

  pkg_mgr=$(detect_package_manager)
  _log_info "Platform package manager: $pkg_mgr"

  # Python
  local py_status
  py_status=$(check_python)
  case "$py_status" in
    ok:*)
      _log_info "Python: ${py_status#ok:} ✓"
      ;;
    old:*)
      _log_warn "Python: ${py_status#old:} (need 3.9+)"
      offer_install python "$pkg_mgr" || missing=$((missing + 1))
      ;;
    missing)
      _log_error "Python: not found (need 3.9+)"
      offer_install python "$pkg_mgr" || missing=$((missing + 1))
      ;;
  esac

  # Git
  local git_status
  git_status=$(check_git)
  case "$git_status" in
    ok:*)
      _log_info "Git: ${git_status#ok:} ✓"
      ;;
    missing)
      _log_error "Git: not found"
      offer_install git "$pkg_mgr" || missing=$((missing + 1))
      ;;
  esac

  # Git Bash (Windows only)
  local gb_status
  gb_status=$(check_git_bash)
  case "$gb_status" in
    ok)    _log_info "Git Bash: available ✓" ;;
    missing) _log_warn "Git Bash: not found (required on Windows for .forge/ scripts)" ; missing=$((missing + 1)) ;;
    n/a)   ;;  # not Windows
  esac

  # Copier
  local copier_status
  copier_status=$(check_copier)
  case "$copier_status" in
    ok:*)
      _log_info "Copier: ${copier_status#ok:} ✓"
      ;;
    old:*)
      _log_warn "Copier: ${copier_status#old:} (need 9.0+)"
      offer_install copier "$pkg_mgr" || missing=$((missing + 1))
      ;;
    missing)
      _log_error "Copier: not found (need 9.0+)"
      offer_install copier "$pkg_mgr" || missing=$((missing + 1))
      ;;
  esac

  # Shellcheck (advisory)
  local sc_status
  sc_status=$(check_shellcheck)
  case "$sc_status" in
    ok) _log_info "shellcheck: available ✓ (optional)" ;;
    missing)
      _log_info "shellcheck: not found (optional — install with: pip install shellcheck-py)"
      advisory=$((advisory + 1))
      ;;
  esac

  # Summary
  echo ""
  if [[ "$missing" -eq 0 ]]; then
    _log_info "All prerequisites met."
    [[ "$advisory" -gt 0 ]] && _log_info "$advisory advisory item(s) noted above."
    return 0
  else
    _log_error "$missing required prerequisite(s) missing. Install them before continuing."
    return 1
  fi
}

# Run prereq check if requested
if [[ "$CHECK_PREREQS" == "true" ]]; then
  run_prereq_checks
  exit $?
fi

# --- Determine user home directory (cross-platform) ---
resolve_home() {
  # Git Bash on Windows sets HOME but USERPROFILE is the canonical Windows home
  if [[ -n "${HOME:-}" ]]; then
    echo "$HOME"
  elif [[ -n "${USERPROFILE:-}" ]]; then
    echo "$USERPROFILE"
  else
    _log_error "Cannot determine home directory: neither HOME nor USERPROFILE is set"
    exit 1
  fi
}

USER_HOME="$(resolve_home)"
FORGE_USER_DIR="${USER_HOME}/.forge"

# --- Determine FORGE template source ---
resolve_source() {
  # If --source was provided, use it (auto-detect .forge/ subdirectory)
  if [[ -n "$SOURCE_PATH" ]]; then
    if [[ ! -d "$SOURCE_PATH" ]]; then
      _log_error "Source path does not exist: $SOURCE_PATH"
      exit 1
    fi
    # If source points to project root (has .forge/ subdir), use .forge/
    if [[ -d "${SOURCE_PATH}/.forge/lib" && -d "${SOURCE_PATH}/.forge/commands" ]]; then
      echo "${SOURCE_PATH}/.forge"
    # If source already points to .forge/ directory, use as-is
    elif [[ -d "${SOURCE_PATH}/lib" && -d "${SOURCE_PATH}/commands" ]]; then
      echo "$SOURCE_PATH"
    else
      _log_error "Source path does not look like a FORGE directory: $SOURCE_PATH"
      _log_error "Expected .forge/lib/ and .forge/commands/ to exist"
      exit 1
    fi
    return
  fi

  # Walk up from script location to find the FORGE template root
  # The script lives at <repo>/.forge/bin/forge-install.sh
  # The template source is <repo>/.forge/ (parent of bin/)
  local candidate
  candidate="$(cd "${SCRIPT_DIR}/.." && pwd)"

  # Verify this looks like a FORGE template directory
  if [[ -d "${candidate}/lib" && -d "${candidate}/commands" ]]; then
    echo "$candidate"
    return
  fi

  # Alternative: walk up looking for copier.yml (indicates we're in a FORGE repo)
  local dir="${SCRIPT_DIR}"
  while [[ "$dir" != "/" && "$dir" != "." ]]; do
    if [[ -f "${dir}/copier.yml" || -f "${dir}/copier.yaml" || -f "${dir}/cookiecutter.json" ]]; then
      # Check for .forge directory under this root
      if [[ -d "${dir}/.forge" ]]; then
        echo "${dir}/.forge"
        return
      fi
    fi
    dir="$(dirname "$dir")"
  done

  _log_error "Cannot find FORGE template source. Use --source to specify the path."
  exit 1
}

TEMPLATE_SOURCE="$(resolve_source)"
_log_info "FORGE template source: ${TEMPLATE_SOURCE}"

# --- Read FORGE version from update-manifest.yaml or git ---
resolve_version() {
  local source_dir="$1"

  # Try update-manifest.yaml
  local manifest="${source_dir}/update-manifest.yaml"
  if [[ -f "$manifest" ]]; then
    local version_line
    version_line="$(grep -m1 '^version:' "$manifest" 2>/dev/null || true)"
    if [[ -n "$version_line" ]]; then
      echo "$version_line" | sed 's/^version:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '"' | tr -d "'"
      return
    fi
  fi

  # Try git describe from the repo containing the source
  local repo_root
  repo_root="$(cd "$source_dir" && git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$repo_root" ]]; then
    local git_version
    git_version="$(cd "$repo_root" && git describe --tags --always 2>/dev/null || true)"
    if [[ -n "$git_version" ]]; then
      echo "$git_version"
      return
    fi
  fi

  echo "0.0.0-unknown"
}

# --- Auto-detect installed agents ---
detect_agents() {
  local agents=()

  # codex
  if command -v codex &>/dev/null || [[ -d "${USER_HOME}/.codex" ]]; then
    agents+=("codex")
  fi

  # claude-code
  if command -v claude &>/dev/null || [[ -d "${USER_HOME}/.claude" ]]; then
    agents+=("claude-code")
  fi

  # cursor — check for Cursor config dirs
  if [[ -d "${USER_HOME}/.cursor" ]] || \
     [[ -d "${USER_HOME}/Library/Application Support/Cursor" ]] || \
     [[ -d "${USER_HOME}/AppData/Roaming/Cursor" ]] || \
     [[ -d "${USER_HOME}/.config/Cursor" ]]; then
    agents+=("cursor")
  fi

  # copilot — check for GitHub config
  if [[ -d "${USER_HOME}/.github" ]] || command -v gh &>/dev/null; then
    agents+=("copilot")
  fi

  # cline — check for Cline config
  local cline_found=false
  if [[ -d "${USER_HOME}/.cline" ]]; then
    cline_found=true
  elif [[ -d "${USER_HOME}/.vscode/extensions" ]]; then
    for ext_dir in "${USER_HOME}/.vscode/extensions/"*cline*; do
      [[ -e "$ext_dir" ]] && { cline_found=true; break; }
    done
  fi
  if $cline_found; then
    agents+=("cline")
  fi

  # windsurf — check for Windsurf config
  if [[ -d "${USER_HOME}/.windsurf" ]] || \
     [[ -d "${USER_HOME}/Library/Application Support/Windsurf" ]] || \
     [[ -d "${USER_HOME}/AppData/Roaming/Windsurf" ]] || \
     [[ -d "${USER_HOME}/.config/Windsurf" ]]; then
    agents+=("windsurf")
  fi

  # Default to claude-code if nothing detected
  if [[ ${#agents[@]} -eq 0 ]]; then
    agents+=("claude-code")
  fi

  printf '%s\n' "${agents[@]}"
}

# --- Resolve agent list ---
resolve_agents() {
  if [[ -n "$AGENTS_ARG" ]]; then
    echo "$AGENTS_ARG" | tr ',' '\n'
  else
    detect_agents
  fi
}

# --- Validate agent names ---
validate_agents() {
  local valid_agents="codex claude-code cursor copilot cline windsurf"
  for agent in "$@"; do
    if [[ ! " $valid_agents " =~ [[:space:]]${agent}[[:space:]] ]]; then
      _log_error "Unknown agent: $agent"
      _log_error "Valid agents: $valid_agents"
      exit 2
    fi
  done
}

# --- Strip YAML frontmatter from stdin ---
strip_frontmatter() {
  local in_frontmatter=false
  local frontmatter_done=false
  while IFS= read -r line; do
    if ! $frontmatter_done; then
      if [[ "$line" == "---" ]] && ! $in_frontmatter; then
        in_frontmatter=true
        continue
      elif [[ "$line" == "---" ]] && $in_frontmatter; then
        frontmatter_done=true
        continue
      elif $in_frontmatter; then
        continue
      fi
    fi
    printf '%s\n' "$line"
  done
}

# --- Read frontmatter field from a file ---
read_frontmatter_field() {
  local file="$1"
  local field="$2"
  local in_frontmatter=false
  while IFS= read -r line; do
    if [[ "$line" == "---" ]] && ! $in_frontmatter; then
      in_frontmatter=true
      continue
    elif [[ "$line" == "---" ]] && $in_frontmatter; then
      break
    elif $in_frontmatter; then
      if [[ "$line" =~ ^${field}:[[:space:]]*\"?([^\"]*)\"? ]]; then
        echo "${BASH_REMATCH[1]}"
        return
      fi
    fi
  done < "$file"
}

# --- Copy directory contents ---
copy_dir() {
  local src="$1"
  local dst="$2"
  local label="$3"

  if [[ ! -d "$src" ]]; then
    _log_debug "Source directory does not exist, skipping: $src"
    return
  fi

  if $DRY_RUN; then
    _log_info "Would copy ${label}: $src -> $dst"
    return
  fi

  mkdir -p "$dst"
  # Use cp -R for cross-platform compatibility (works in Git Bash, macOS, Linux)
  cp -R "$src"/. "$dst"/ 2>/dev/null || cp -R "$src"/* "$dst"/ 2>/dev/null || true
  _log_info "Copied ${label}: $(find "$dst" -type f 2>/dev/null | wc -l | tr -d ' ') files"
}

# --- Write version.yaml ---
write_version_file() {
  local target_dir="$1"
  local version
  version="$(resolve_version "$TEMPLATE_SOURCE")"

  local agents_yaml=""
  for agent in "${AGENTS[@]}"; do
    agents_yaml="${agents_yaml}  - ${agent}
"
  done

  local timestamp
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  if $DRY_RUN; then
    _log_info "Would write ${target_dir}/version.yaml"
    return
  fi

  mkdir -p "$target_dir"
  cat > "${target_dir}/version.yaml" <<EOF
installed: ${timestamp}
source: ${TEMPLATE_SOURCE}
version: ${version}
installer: ${SCRIPT_VERSION}
agents:
${agents_yaml}
EOF

  _log_info "Wrote version.yaml (version: ${version})"
}

# --- Agent installer: Claude Code ---
install_claude_code() {
  local target_dir="${USER_HOME}/.claude/commands"
  local source_dir="${TEMPLATE_SOURCE}/commands"

  _log_step "Installing Claude Code commands"

  if [[ ! -d "$source_dir" ]]; then
    _log_warn "No commands directory found in source — skipping Claude Code"
    return
  fi

  if $DRY_RUN; then
    _log_info "Would create: $target_dir"
    local count=0
    for src_file in "$source_dir"/*.md "$source_dir"/*.md.jinja; do
      [[ -f "$src_file" ]] || continue
      count=$((count + 1))
    done
    _log_info "Would install $count commands to $target_dir"
    return
  fi

  mkdir -p "$target_dir"

  local installed=0
  for src_file in "$source_dir"/*.md "$source_dir"/*.md.jinja; do
    [[ -f "$src_file" ]] || continue

    local basename
    basename="$(basename "$src_file")"
    local dst_file="${target_dir}/${basename}"

    # Skip if existing non-FORGE file
    if [[ -f "$dst_file" ]]; then
      if ! head -5 "$dst_file" 2>/dev/null | grep -q "${FORGE_COMMAND_HEADER}" 2>/dev/null; then
        _log_warn "Skipping ${basename}: existing non-FORGE file"
        continue
      fi
    fi

    # Strip frontmatter and write
    strip_frontmatter < "$src_file" > "$dst_file"
    installed=$((installed + 1))
  done

  _log_info "Installed ${installed} Claude Code commands to ${target_dir}"
}

# --- Agent installer: Codex ---
install_codex() {
  local source_dir="${TEMPLATE_SOURCE}/commands"
  local codex_skills_dir="${USER_HOME}/.codex/skills"

  _log_step "Installing Codex skills"

  if [[ ! -d "$source_dir" ]]; then
    _log_warn "No commands directory found in source — skipping Codex"
    return
  fi

  if $DRY_RUN; then
    local count=0
    for src_file in "$source_dir"/*.md "$source_dir"/*.md.jinja; do
      [[ -f "$src_file" ]] || continue
      count=$((count + 1))
    done
    _log_info "Would install $count Codex skills to ${codex_skills_dir}/forge-*/"
    return
  fi

  local installed=0
  for src_file in "$source_dir"/*.md "$source_dir"/*.md.jinja; do
    [[ -f "$src_file" ]] || continue

    local basename
    basename="$(basename "$src_file" .md)"
    basename="${basename%.jinja}"  # strip .jinja if present

    local cmd_name
    cmd_name="$(read_frontmatter_field "$src_file" "name")"
    [[ -z "$cmd_name" ]] && cmd_name="$basename"

    local cmd_desc
    cmd_desc="$(read_frontmatter_field "$src_file" "description")"
    [[ -z "$cmd_desc" ]] && cmd_desc="FORGE command: ${cmd_name}"

    local skill_dir="${codex_skills_dir}/forge-${cmd_name}"
    local agents_dir="${skill_dir}/agents"

    mkdir -p "$agents_dir"

    # Generate SKILL.md
    {
      echo "---"
      echo "name: forge-${cmd_name}"
      echo "description: \"${cmd_desc}. Use when the user invokes /forge ${cmd_name} or asks about ${cmd_name}.\""
      echo "---"
      strip_frontmatter < "$src_file"
    } > "${skill_dir}/SKILL.md"

    # Generate agents/openai.yaml
    # Title-case the command name
    local title_name
    title_name="$(echo "$cmd_name" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')"

    cat > "${agents_dir}/openai.yaml" <<YAML
interface:
  display_name: "FORGE: ${title_name}"
  short_description: "${cmd_desc}"
YAML

    installed=$((installed + 1))
  done

  _log_info "Installed ${installed} Codex skills to ${codex_skills_dir}"
}

# --- Agent installer: Cursor ---
install_cursor() {
  local target_file="${USER_HOME}/.cursorrules"

  _log_step "Installing Cursor rules"

  if [[ -f "$target_file" ]]; then
    # Check if it's FORGE-managed
    if ! head -1 "$target_file" 2>/dev/null | grep -q "Managed by FORGE" 2>/dev/null; then
      _log_warn "Skipping Cursor: ${target_file} exists with non-FORGE content"
      return
    fi
  fi

  if $DRY_RUN; then
    _log_info "Would write: $target_file"
    return
  fi

  cat > "$target_file" <<'RULES'
# Managed by FORGE — do not edit manually
# This file was generated by forge-install.sh
# Re-run forge-install.sh --update to refresh

# FORGE Framework Rules
You are working in a project that uses the FORGE (Framework for Organized Reliable Gated Engineering) methodology.

## Core principles
1. Every change has a matching spec. No implementation without one.
2. Every session ends with a session log. No exceptions.

## Workflow
- Check docs/backlog.md for prioritized work items
- Find specs in docs/specs/README.md
- Follow the spec lifecycle: draft → in-progress → implemented → closed
- Use FORGE slash commands for structured workflows (/now, /spec, /implement, /close, /session)

## FORGE commands available
Run these as slash commands or ask about them:
/now — Review current project state
/spec — Create or update a spec
/implement — Implement a spec
/close — Close and validate a spec
/session — Log a session
/matrix — View prioritization matrix
/trace — Trace requirements to implementation
RULES

  _log_info "Wrote Cursor rules to ${target_file}"
}

# --- Agent installer: Copilot ---
install_copilot() {
  local target_dir="${USER_HOME}/.github"
  local target_file="${target_dir}/copilot-instructions.md"

  _log_step "Installing Copilot instructions"

  if [[ -f "$target_file" ]]; then
    if ! head -1 "$target_file" 2>/dev/null | grep -q "Managed by FORGE" 2>/dev/null; then
      _log_warn "Skipping Copilot: ${target_file} exists with non-FORGE content"
      return
    fi
  fi

  if $DRY_RUN; then
    _log_info "Would write: $target_file"
    return
  fi

  mkdir -p "$target_dir"

  cat > "$target_file" <<'INSTRUCTIONS'
<!-- Managed by FORGE — do not edit manually -->
<!-- Generated by forge-install.sh. Re-run forge-install.sh --update to refresh -->

# FORGE Framework Instructions

You are working in a project that uses the FORGE (Framework for Organized Reliable Gated Engineering) methodology.

## Core principles
1. Every change has a matching spec. No implementation without one.
2. Every session ends with a session log. No exceptions.

## Workflow
- Check docs/backlog.md for prioritized work items
- Find specs in docs/specs/README.md
- Follow the spec lifecycle: draft → in-progress → implemented → closed

## When implementing changes
1. Always reference the relevant spec number
2. Follow the acceptance criteria defined in the spec
3. Run tests and validation before marking complete
4. Update the spec status when implementation is done
INSTRUCTIONS

  _log_info "Wrote Copilot instructions to ${target_file}"
}

# --- Agent installer: Cline ---
install_cline() {
  local target_file="${USER_HOME}/.clinerules"

  _log_step "Installing Cline rules"

  if [[ -f "$target_file" ]]; then
    if ! head -1 "$target_file" 2>/dev/null | grep -q "Managed by FORGE" 2>/dev/null; then
      _log_warn "Skipping Cline: ${target_file} exists with non-FORGE content"
      return
    fi
  fi

  if $DRY_RUN; then
    _log_info "Would write: $target_file"
    return
  fi

  cat > "$target_file" <<'RULES'
# Managed by FORGE — do not edit manually
# Generated by forge-install.sh. Re-run forge-install.sh --update to refresh

# FORGE Framework Rules
You are working in a project that uses the FORGE methodology.

## Core principles
1. Every change has a matching spec. No implementation without one.
2. Every session ends with a session log.

## Workflow
- Check docs/backlog.md for prioritized work
- Follow spec lifecycle: draft → in-progress → implemented → closed
- Use FORGE commands for structured workflows
RULES

  _log_info "Wrote Cline rules to ${target_file}"
}

# --- Agent installer: Windsurf ---
install_windsurf() {
  local target_file="${USER_HOME}/.windsurfrules"

  _log_step "Installing Windsurf rules"

  if [[ -f "$target_file" ]]; then
    if ! head -1 "$target_file" 2>/dev/null | grep -q "Managed by FORGE" 2>/dev/null; then
      _log_warn "Skipping Windsurf: ${target_file} exists with non-FORGE content"
      return
    fi
  fi

  if $DRY_RUN; then
    _log_info "Would write: $target_file"
    return
  fi

  cat > "$target_file" <<'RULES'
# Managed by FORGE — do not edit manually
# Generated by forge-install.sh. Re-run forge-install.sh --update to refresh

# FORGE Framework Rules
You are working in a project that uses the FORGE methodology.

## Core principles
1. Every change has a matching spec. No implementation without one.
2. Every session ends with a session log.

## Workflow
- Check docs/backlog.md for prioritized work
- Follow spec lifecycle: draft → in-progress → implemented → closed
- Use FORGE commands for structured workflows
RULES

  _log_info "Wrote Windsurf rules to ${target_file}"
}

# --- Uninstall flow ---
do_uninstall() {
  _log_step "Uninstalling FORGE (user-level)"

  local removed=0

  # 1. Remove ~/.forge/ entirely
  if [[ -d "$FORGE_USER_DIR" ]]; then
    if $DRY_RUN; then
      _log_info "Would remove: $FORGE_USER_DIR"
    else
      rm -rf "$FORGE_USER_DIR"
      _log_info "Removed: $FORGE_USER_DIR"
    fi
    removed=$((removed + 1))
  fi

  # 2. Remove Codex skills (forge-* only)
  local codex_skills_dir="${USER_HOME}/.codex/skills"
  if [[ -d "$codex_skills_dir" ]]; then
    for skill_dir in "$codex_skills_dir"/forge-*/; do
      [[ -d "$skill_dir" ]] || continue
      if $DRY_RUN; then
        _log_info "Would remove: $skill_dir"
      else
        rm -rf "$skill_dir"
        _log_info "Removed: $skill_dir"
      fi
      removed=$((removed + 1))
    done
  fi

  # 3. Remove FORGE commands from ~/.claude/commands/
  local claude_cmd_dir="${USER_HOME}/.claude/commands"
  if [[ -d "$claude_cmd_dir" ]]; then
    for cmd_file in "$claude_cmd_dir"/*.md "$claude_cmd_dir"/*.md.jinja; do
      [[ -f "$cmd_file" ]] || continue
      if head -5 "$cmd_file" 2>/dev/null | grep -q "${FORGE_COMMAND_HEADER}" 2>/dev/null; then
        if $DRY_RUN; then
          _log_info "Would remove: $cmd_file"
        else
          rm -f "$cmd_file"
          _log_info "Removed: $cmd_file"
        fi
        removed=$((removed + 1))
      fi
    done
  fi

  # 4. Remove pointer files (only if FORGE-managed)
  local pointer_files=(
    "${USER_HOME}/.cursorrules"
    "${USER_HOME}/.clinerules"
    "${USER_HOME}/.windsurfrules"
    "${USER_HOME}/.github/copilot-instructions.md"
  )
  for pf in "${pointer_files[@]}"; do
    if [[ -f "$pf" ]]; then
      if head -1 "$pf" 2>/dev/null | grep -q "Managed by FORGE" 2>/dev/null; then
        if $DRY_RUN; then
          _log_info "Would remove: $pf"
        else
          rm -f "$pf"
          _log_info "Removed: $pf"
        fi
        removed=$((removed + 1))
      else
        _log_warn "Skipping: $pf (not FORGE-managed)"
      fi
    fi
  done

  echo ""
  echo "## forge-install --uninstall — Complete"
  echo "Items removed: ${removed}"
  if $DRY_RUN; then
    echo "Mode: dry-run (no files removed)"
  fi
}

# --- Install flow (user scope) ---
do_install_user() {
  local mode_label="Installing"
  if $UPDATE_MODE; then
    mode_label="Updating"
  fi

  _log_step "${mode_label} FORGE (user-level)"

  # Create ~/.forge/ directory structure
  if $DRY_RUN; then
    _log_info "Would create: ${FORGE_USER_DIR}/{lib,adapters,templates,commands,process-kit}"
  else
    mkdir -p "${FORGE_USER_DIR}"/{lib,adapters,templates,commands,process-kit}
  fi

  # Copy template source directories
  copy_dir "${TEMPLATE_SOURCE}/lib"       "${FORGE_USER_DIR}/lib"       "lib"
  copy_dir "${TEMPLATE_SOURCE}/adapters"  "${FORGE_USER_DIR}/adapters"  "adapters"
  copy_dir "${TEMPLATE_SOURCE}/templates" "${FORGE_USER_DIR}/templates" "templates"
  copy_dir "${TEMPLATE_SOURCE}/commands"  "${FORGE_USER_DIR}/commands"  "commands"

  # process-kit lives in docs/process-kit/ relative to the project root
  local process_kit_src=""
  # Try relative to template source (which is .forge/)
  if [[ -d "${TEMPLATE_SOURCE}/../docs/process-kit" ]]; then
    process_kit_src="$(cd "${TEMPLATE_SOURCE}/../docs/process-kit" && pwd)"
  fi
  if [[ -n "$process_kit_src" ]]; then
    copy_dir "$process_kit_src" "${FORGE_USER_DIR}/process-kit" "process-kit"
  else
    _log_warn "process-kit source not found — skipping"
  fi

  # Write version.yaml
  write_version_file "$FORGE_USER_DIR"

  # Install agent integrations
  for agent in "${AGENTS[@]}"; do
    case "$agent" in
      claude-code) install_claude_code ;;
      codex)       install_codex ;;
      cursor)      install_cursor ;;
      copilot)     install_copilot ;;
      cline)       install_cline ;;
      windsurf)    install_windsurf ;;
    esac
  done
}

# --- Install flow (project scope) ---
do_install_project() {
  _log_step "Installing FORGE (project-level)"

  # Project scope uses forge-sync-commands for the current project
  local sync_script="${SCRIPT_DIR}/forge-sync-commands.sh"
  if [[ -x "$sync_script" ]]; then
    local sync_args=()
    if [[ -n "$AGENTS_ARG" ]]; then
      sync_args+=("--agents" "$AGENTS_ARG")
    fi
    if $DRY_RUN; then
      sync_args+=("--dry-run")
    fi
    "$sync_script" "${sync_args[@]}"
  else
    _log_warn "forge-sync-commands.sh not found — skipping project-level install"
  fi
}

# --- Main ---
main() {
  echo ""
  echo "=== FORGE Installer v${SCRIPT_VERSION} ==="
  echo ""

  # Handle uninstall
  if $UNINSTALL_MODE; then
    do_uninstall
    exit 0
  fi

  # Resolve and validate agents
  mapfile -t AGENTS < <(resolve_agents)
  if [[ ${#AGENTS[@]} -eq 0 ]]; then
    AGENTS=("claude-code")
  fi
  validate_agents "${AGENTS[@]}"

  _log_info "Detected agents: ${AGENTS[*]}"
  _log_info "Scope: ${SCOPE}"
  _log_info "Source: ${TEMPLATE_SOURCE}"
  if $DRY_RUN; then
    _log_info "Mode: dry-run"
  fi
  if $UPDATE_MODE; then
    _log_info "Mode: update"
  fi

  # Execute install based on scope
  case "$SCOPE" in
    user)
      do_install_user
      ;;
    project)
      do_install_project
      ;;
    both)
      do_install_user
      do_install_project
      ;;
  esac

  # Summary
  local action="Installed"
  if $UPDATE_MODE; then action="Updated"; fi

  echo ""
  echo "## forge-install — Complete"
  echo "Action: ${action}"
  echo "Scope: ${SCOPE}"
  echo "Agents: ${AGENTS[*]}"
  if [[ "$SCOPE" == "user" || "$SCOPE" == "both" ]]; then
    echo "FORGE home: ${FORGE_USER_DIR}"
  fi
  if $DRY_RUN; then
    echo "Mode: dry-run (no files written)"
  fi
}

main

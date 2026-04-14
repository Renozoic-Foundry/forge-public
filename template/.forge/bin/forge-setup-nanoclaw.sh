#!/usr/bin/env bash
# FORGE NanoClaw Prerequisites Installer
# Installs: ykman (YubiKey Manager CLI), jq, curl, openssl
# Optional: libfido2 (for FIDO2 authentication provider)
#
# NOTE: PAL integration is a feature in development and not yet production-ready.
# Usage: forge-setup-nanoclaw.sh [--check-only]
#
# Supports: Linux (apt/dnf/pacman), macOS (brew), Windows (Git Bash)
# On Windows: installs ykman via MSI, downloads jq directly — no choco/scoop required.
set -euo pipefail

# FORGE_SCRIPT_DIR is set by .ps1 wrappers to the real script directory
# (BASH_SOURCE[0] points to a temp file when launched via .ps1)
if [[ -n "${FORGE_SCRIPT_DIR:-}" ]]; then
  FORGE_DIR="$(cd "${FORGE_SCRIPT_DIR}/.." && pwd)"
else
  FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
CHECK_ONLY=false
INSTALL_DIR=""
PLATFORM=""
PKG_MANAGER=""
INSTALL_FIDO2=false  # set to true if user wants FIDO2 provider

# Source shared utilities (forge_source, forge_ensure_yubico_path)
# shellcheck disable=SC1091
source "${FORGE_DIR}/lib/forge-utils.sh"
forge_ensure_yubico_path

# Source logging library
if [[ -f "${FORGE_DIR}/lib/logging.sh" ]]; then
  forge_source "${FORGE_DIR}/lib/logging.sh"
fi
forge_log_init "forge-setup-nanoclaw"

# Aliases for backward compat within this script
info()  { forge_log_info "$1"; }
warn()  { forge_log_warn "$1"; }
fail()  { forge_log_error "$1"; }
step()  { forge_log_step "$1"; }

# --- Parse args ---
if [[ "${1:-}" == "--check-only" ]]; then
  CHECK_ONLY=true
fi

# --- Detect platform ---
detect_platform() {
  local uname_out
  uname_out="$(uname -s)"
  case "$uname_out" in
    Linux*)   PLATFORM="linux" ;;
    Darwin*)  PLATFORM="macos" ;;
    MINGW*|MSYS*|CYGWIN*)  PLATFORM="windows" ;;
    *)        PLATFORM="unknown" ;;
  esac

  if [[ "$PLATFORM" == "linux" ]]; then
    if command -v apt-get &>/dev/null; then
      PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null; then
      PKG_MANAGER="dnf"
    elif command -v pacman &>/dev/null; then
      PKG_MANAGER="pacman"
    elif command -v apk &>/dev/null; then
      PKG_MANAGER="apk"
    fi
  elif [[ "$PLATFORM" == "macos" ]]; then
    if command -v brew &>/dev/null; then
      PKG_MANAGER="brew"
    fi
  elif [[ "$PLATFORM" == "windows" ]]; then
    PKG_MANAGER="direct"
    INSTALL_DIR="${HOME}/bin"
  fi
}

# --- Check individual tools ---
check_tool() {
  local name="$1"
  local cmd="${2:-$1}"
  if command -v "$cmd" &>/dev/null; then
    local version
    version="$("$cmd" --version 2>/dev/null | head -1 || echo "installed")"
    info "${name}: ${version}"
    return 0
  else
    fail "${name}: not found"
    return 1
  fi
}

# Check for ykman (R18 — direct ykman, no legacy wrapper dependency)
check_yk_tools() {
  if command -v ykman &>/dev/null; then
    local ykman_ver
    ykman_ver="$(ykman --version 2>/dev/null | head -1 || echo "installed")"
    info "ykman: ${ykman_ver}"
    return 0
  fi

  fail "ykman: not found (YubiKey Manager CLI)"
  return 1
}

# Check for optional libfido2 (FIDO2 provider)
check_fido2_tools() {
  if command -v fido2-token &>/dev/null; then
    local fido2_ver
    fido2_ver="$(fido2-token -V 2>/dev/null | head -1 || echo "installed")"
    info "libfido2: ${fido2_ver} (FIDO2 provider available)"
    return 0
  fi
  info "libfido2: not installed (optional — for FIDO2 authentication provider)"
  return 1
}

# Check for nanoclaw-forge bridge CLI (ncforge)
check_ncforge_bridge() {
  if command -v ncforge &>/dev/null; then
    local ncforge_ver
    ncforge_ver="$(ncforge version 2>/dev/null | head -1 || echo "installed")"
    info "ncforge (nanoclaw-forge bridge): ${ncforge_ver}"
    return 0
  fi

  # Read nanoclaw.enabled from AGENTS.md if available
  local project_dir
  project_dir="$(cd "${FORGE_DIR}/.." && pwd)"
  local agents_md="${project_dir}/AGENTS.md"
  local nc_enabled="false"

  if [[ -f "$agents_md" ]]; then
    nc_enabled="$(grep -A1 'nanoclaw:' "$agents_md" 2>/dev/null | grep 'enabled:' | head -1 | sed 's/.*enabled:[[:space:]]*//' | sed 's/[[:space:]]*#.*//')" || true
    nc_enabled="${nc_enabled:-false}"
  fi

  if [[ "$nc_enabled" == "true" ]]; then
    warn "ncforge: not installed (recommended — NanoClaw is enabled)"
    warn "  Install: pip install nanoclaw-forge"
    warn "  Or:      see https://github.com/Renozoic-Foundry/nanoclaw-forge"
    return 0  # Warning only, not blocking
  else
    info "ncforge: not installed (optional — NanoClaw is not enabled)"
    return 0
  fi
}

# Check for PAL (hardware gate authentication)
check_pal() {
  if command -v pal &>/dev/null; then
    local pal_ver
    pal_ver="$(pal version 2>/dev/null | head -1 || echo "installed")"
    info "pal: ${pal_ver}"
    return 0
  fi

  # Read gate.provider and lane from AGENTS.md if available
  local project_dir
  project_dir="$(cd "${FORGE_DIR}/.." && pwd)"
  local agents_md="${project_dir}/AGENTS.md"
  local gate_provider="prompt"
  local lane="A"

  if [[ -f "$agents_md" ]]; then
    # Simple YAML-ish extraction from the config block
    gate_provider="$(grep -A5 'gate:' "$agents_md" 2>/dev/null | grep 'provider:' | head -1 | sed 's/.*provider:[[:space:]]*//' | sed 's/[[:space:]]*#.*//')" || true
    lane="$(grep -A1 'forge:' "$agents_md" 2>/dev/null | grep 'lane:' | head -1 | sed 's/.*lane:[[:space:]]*//' | sed 's/[[:space:]]*#.*//')" || true
    gate_provider="${gate_provider:-prompt}"
    lane="${lane:-A}"
  fi

  if [[ "$lane" == "B" ]]; then
    fail "pal: not found (REQUIRED — Lane B requires hardware-authenticated gates)"
    fail "  Install PAL: pip install pal-gate  OR  see https://github.com/Renozoic-Foundry/pal"
    return 1
  elif [[ "$gate_provider" == "pal" ]]; then
    fail "pal: not found (REQUIRED — gate.provider is 'pal')"
    fail "  Install PAL: pip install pal-gate  OR  see https://github.com/Renozoic-Foundry/pal"
    return 1
  elif [[ "$gate_provider" == "auto" ]]; then
    info "pal: not installed (optional — gate.provider is 'auto', will fall back to prompt)"
    return 0  # Not a failure for auto mode
  else
    info "pal: not installed (optional — gate.provider is 'prompt')"
    return 0  # Not a failure for prompt mode
  fi
}

check_all() {
  step "Checking prerequisites"
  local missing=0

  check_tool "curl" || missing=$((missing + 1))
  check_tool "openssl" || missing=$((missing + 1))
  check_tool "jq" || missing=$((missing + 1))
  check_yk_tools || missing=$((missing + 1))
  check_fido2_tools || true  # optional — don't count as missing
  check_pal || missing=$((missing + 1))
  check_ncforge_bridge || true  # informational — don't count as missing

  echo ""
  if [[ "$missing" -eq 0 ]]; then
    info "All required prerequisites installed."
    return 0
  else
    warn "${missing} required tool group(s) missing."
    return 1
  fi
}

# --- Install functions per platform ---

install_jq_windows() {
  step "Installing jq (Windows — direct download)"
  mkdir -p "$INSTALL_DIR"

  local jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe"
  local jq_dest="${INSTALL_DIR}/jq.exe"

  if [[ -f "$jq_dest" ]]; then
    info "jq already exists at ${jq_dest}"
    return 0
  fi

  warn "Downloading jq from GitHub releases..."
  curl -sL "$jq_url" -o "$jq_dest" || {
    fail "Failed to download jq. Download manually from:"
    fail "  https://github.com/jqlang/jq/releases"
    fail "  Place jq.exe in: ${INSTALL_DIR}/"
    return 1
  }
  chmod +x "$jq_dest"
  info "jq installed to ${jq_dest}"
}

install_ykman_windows() {
  step "Installing YubiKey Manager CLI (ykman)"

  # Check if ykman is already available
  if command -v ykman &>/dev/null; then
    info "ykman already installed."
    return 0
  fi

  # Check common install locations from a prior MSI install
  local ykman_install_paths=(
    "/c/Program Files/Yubico/YubiKey Manager CLI"
    "/c/Program Files/Yubico/YubiKey Manager"
    "/c/Program Files (x86)/Yubico/YubiKey Manager CLI"
    "/c/Program Files (x86)/Yubico/YubiKey Manager"
  )
  for yp in "${ykman_install_paths[@]}"; do
    if [[ -f "${yp}/ykman.exe" ]]; then
      info "Found ykman at: ${yp}"
      export PATH="$PATH:${yp}"
      if ! grep -q "YubiKey Manager" "$HOME/.bashrc" 2>/dev/null; then
        {
          echo ""
          echo "# Yubico YubiKey Manager (added by FORGE setup)"
          echo "export PATH=\"\$PATH:${yp}\""
        } >> "$HOME/.bashrc"
      fi
      return 0
    fi
  done

  # Download and install YubiKey Manager MSI from GitHub releases
  local msi_url="https://github.com/Yubico/yubikey-manager/releases/latest/download/yubikey-manager-5.9.0-win64.msi"
  local msi_dest="${INSTALL_DIR}/yubikey-manager-win64.msi"

  mkdir -p "$INSTALL_DIR"
  warn "Downloading YubiKey Manager MSI from GitHub..."
  curl -sL "$msi_url" -o "$msi_dest" || {
    fail "Failed to download YubiKey Manager."
    fail "Download manually from: https://github.com/Yubico/yubikey-manager/releases"
    fail "Run the .msi installer, then re-run this script."
    return 1
  }

  info "Downloaded YubiKey Manager MSI."
  warn "Installing YubiKey Manager (requires admin privileges)..."

  # Convert MSYS path back to Windows path for msiexec
  local msi_win_path
  msi_win_path="$(cygpath -w "$msi_dest" 2>/dev/null || echo "$msi_dest")"

  # Run msiexec — /passive shows progress bar but doesn't require interaction
  msiexec //i "$msi_win_path" //passive //norestart || {
    fail "MSI installation failed. Try running manually:"
    fail "  msiexec /i \"${msi_win_path}\""
    rm -f "$msi_dest"
    return 1
  }

  # Clean up downloaded MSI
  rm -f "$msi_dest"

  # Add to PATH — check both possible install locations
  local ykman_dir=""
  if [[ -f "/c/Program Files/Yubico/YubiKey Manager CLI/ykman.exe" ]]; then
    ykman_dir="/c/Program Files/Yubico/YubiKey Manager CLI"
  elif [[ -f "/c/Program Files/Yubico/YubiKey Manager/ykman.exe" ]]; then
    ykman_dir="/c/Program Files/Yubico/YubiKey Manager"
  fi
  if [[ -n "$ykman_dir" ]]; then
    export PATH="$PATH:${ykman_dir}"
    if ! grep -q "YubiKey Manager" "$HOME/.bashrc" 2>/dev/null; then
      {
        echo ""
        echo "# Yubico YubiKey Manager (added by FORGE setup)"
        echo "export PATH=\"\$PATH:${ykman_dir}\""
      } >> "$HOME/.bashrc"
    fi
    info "YubiKey Manager installed."
    return 0
  else
    fail "Installation completed but ykman.exe not found at expected location."
    fail "Check C:\\Program Files\\Yubico\\YubiKey Manager\\"
    return 1
  fi
}

install_linux() {
  local tool="$1"

  case "$PKG_MANAGER" in
    apt)
      case "$tool" in
        jq)       sudo apt-get install -y jq ;;
        ykman)    sudo apt-get install -y yubikey-manager ;;
        libfido2) sudo apt-get install -y libfido2-dev fido2-tools ;;
        curl)     sudo apt-get install -y curl ;;
      esac
      ;;
    dnf)
      case "$tool" in
        jq)       sudo dnf install -y jq ;;
        ykman)    sudo dnf install -y yubikey-manager ;;
        libfido2) sudo dnf install -y libfido2 libfido2-devel fido2-tools ;;
        curl)     sudo dnf install -y curl ;;
      esac
      ;;
    pacman)
      case "$tool" in
        jq)       sudo pacman -S --noconfirm jq ;;
        ykman)    sudo pacman -S --noconfirm yubikey-manager ;;
        libfido2) sudo pacman -S --noconfirm libfido2 ;;
        curl)     sudo pacman -S --noconfirm curl ;;
      esac
      ;;
    apk)
      case "$tool" in
        jq)       sudo apk add jq ;;
        ykman)    pip3 install yubikey-manager ;;
        libfido2) sudo apk add libfido2 ;;
        curl)     sudo apk add curl ;;
      esac
      ;;
    *)
      fail "No supported package manager found. Install ${tool} manually."
      return 1
      ;;
  esac
}

install_macos() {
  local tool="$1"

  if [[ -z "$PKG_MANAGER" ]]; then
    fail "Homebrew not found. Install from: https://brew.sh"
    return 1
  fi

  case "$tool" in
    jq)       brew install jq ;;
    ykman)    brew install ykman ;;
    libfido2) brew install libfido2 ;;
    curl)     brew install curl ;;
  esac
}

# --- Main install logic ---

install_missing() {
  # curl and openssl are usually pre-installed; only install if missing
  if ! command -v curl &>/dev/null; then
    step "Installing curl"
    case "$PLATFORM" in
      linux)   install_linux "curl" ;;
      macos)   install_macos "curl" ;;
      windows) info "curl should be available in Git Bash. Check your Git installation." ;;
    esac
  fi

  # openssl — ships with Git Bash, most Linux distros, and macOS
  if ! command -v openssl &>/dev/null; then
    warn "openssl not found. It should be included with your system or Git installation."
    warn "Linux: sudo apt install openssl"
    warn "macOS: pre-installed"
    warn "Windows: included with Git Bash"
  fi

  # jq
  if ! command -v jq &>/dev/null; then
    case "$PLATFORM" in
      linux)   install_linux "jq" ;;
      macos)   install_macos "jq" ;;
      windows) install_jq_windows ;;
    esac
  fi

  # ykman (R18, R19 — direct ykman, no legacy ykpers dependency)
  if ! command -v ykman &>/dev/null; then
    case "$PLATFORM" in
      linux)   install_linux "ykman" ;;
      macos)   install_macos "ykman" ;;
      windows) install_ykman_windows ;;
    esac
  fi

  # PAL (optional/required depending on gate.provider and lane)
  if ! command -v pal &>/dev/null; then
    # Re-read gate config to decide whether to install
    local project_dir
    project_dir="$(cd "${FORGE_DIR}/.." && pwd)"
    local agents_md="${project_dir}/AGENTS.md"
    local gate_provider="prompt"
    local lane="A"
    if [[ -f "$agents_md" ]]; then
      gate_provider="$(grep -A5 'gate:' "$agents_md" 2>/dev/null | grep 'provider:' | head -1 | sed 's/.*provider:[[:space:]]*//' | sed 's/[[:space:]]*#.*//')" || true
      lane="$(grep -A1 'forge:' "$agents_md" 2>/dev/null | grep 'lane:' | head -1 | sed 's/.*lane:[[:space:]]*//' | sed 's/[[:space:]]*#.*//')" || true
      gate_provider="${gate_provider:-prompt}"
      lane="${lane:-A}"
    fi

    if [[ "$lane" == "B" || "$gate_provider" == "pal" ]]; then
      step "Installing PAL (hardware gate authentication)"
      if command -v pip3 &>/dev/null; then
        pip3 install pal-gate || {
          fail "Failed to install PAL via pip. Install manually:"
          fail "  pip install pal-gate  OR  see https://github.com/Renozoic-Foundry/pal"
        }
      elif command -v pip &>/dev/null; then
        pip install pal-gate || {
          fail "Failed to install PAL via pip. Install manually:"
          fail "  pip install pal-gate  OR  see https://github.com/Renozoic-Foundry/pal"
        }
      else
        fail "pip not found. Install PAL manually:"
        fail "  pip install pal-gate  OR  see https://github.com/Renozoic-Foundry/pal"
      fi
    elif [[ "$gate_provider" == "auto" ]]; then
      echo ""
      printf '→ Install PAL for hardware-authenticated gates? (y/N): '
      local pal_answer
      read -r pal_answer
      case "$pal_answer" in
        [yY]*)
          step "Installing PAL (hardware gate authentication)"
          if command -v pip3 &>/dev/null; then
            pip3 install pal-gate || warn "Failed to install PAL. Install manually: pip install pal-gate"
          elif command -v pip &>/dev/null; then
            pip install pal-gate || warn "Failed to install PAL. Install manually: pip install pal-gate"
          else
            warn "pip not found. Install PAL manually: pip install pal-gate"
          fi
          ;;
        *)
          info "Skipping PAL. Gate approval will use prompt-based mode."
          ;;
      esac
    fi
  fi

  # libfido2 (optional — for FIDO2 authentication provider)
  if ! command -v fido2-token &>/dev/null; then
    echo ""
    printf '→ Install libfido2 for FIDO2 authentication? (y/N): '
    local fido2_answer
    read -r fido2_answer
    case "$fido2_answer" in
      [yY]*)
        case "$PLATFORM" in
          linux)   install_linux "libfido2" ;;
          macos)   install_macos "libfido2" ;;
          windows)
            warn "libfido2 on Windows: download from https://github.com/niclas-ahden/libfido2/releases"
            warn "Or install via: winget install libfido2"
            ;;
        esac
        ;;
      *)
        info "Skipping libfido2. You can install it later for FIDO2 provider support."
        ;;
    esac
  fi
}

ensure_path() {
  # On Windows, ensure ~/bin is in PATH for direct-downloaded binaries
  if [[ "$PLATFORM" == "windows" && -d "$INSTALL_DIR" ]]; then
    case ":$PATH:" in
      *":${INSTALL_DIR}:"*) ;;
      *)
        export PATH="$PATH:${INSTALL_DIR}"
        if ! grep -q "HOME/bin" "$HOME/.bashrc" 2>/dev/null; then
          {
            echo ""
            echo "# FORGE local binaries (added by FORGE setup)"
            # shellcheck disable=SC2016
            echo 'export PATH="$PATH:$HOME/bin"'
          } >> "$HOME/.bashrc"
          warn "Added ~/bin to PATH in ~/.bashrc — restart terminal or: source ~/.bashrc"
        fi
        ;;
    esac
  fi
}

# --- Post-install: offer configuration wizard ---

offer_configure() {
  local configure_script="${FORGE_DIR}/bin/forge-configure-nanoclaw.sh"
  echo ""
  if [[ ! -f "$configure_script" ]]; then
    echo "Next: program YubiKeys, enroll, and configure AGENTS.md."
    echo "Full guide: docs/nanoclaw-setup.md"
    return 0
  fi

  printf '%b→%b %s' "${YELLOW}" "${RESET}" "Launch the configuration wizard now? (Y/n): "
  local answer
  read -r answer
  answer="${answer:-y}"
  case "$answer" in
    [yY]*)
      echo ""
      # Execute configuration script via forge_exec (handles Jinja2 tag stripping)
      export FORGE_SCRIPT_DIR="${FORGE_DIR}/bin"
      forge_exec "$configure_script"
      exit $?
      ;;
    *)
      echo ""
      echo "To configure later:"
      echo "  .forge/bin/forge-configure-nanoclaw.sh"
      echo "  .forge/bin/forge-configure-nanoclaw.sh --check-only   # status only"
      echo ""
      echo "Full guide: docs/nanoclaw-setup.md"
      ;;
  esac
}

# --- Main ---

echo "FORGE NanoClaw Prerequisites Installer"
echo "======================================="
echo ""

detect_platform
info "Platform: ${PLATFORM} ($(uname -s))"
if [[ -n "$PKG_MANAGER" ]]; then
  info "Package manager: ${PKG_MANAGER}"
fi
if [[ -n "$INSTALL_DIR" ]]; then
  info "Install directory: ${INSTALL_DIR}"
fi

if $CHECK_ONLY; then
  check_all
  exit $?
fi

# Ensure PATH includes install dir before checking
if [[ "$PLATFORM" == "windows" ]]; then
  ensure_path
fi

# Check what's already installed
echo ""
if check_all 2>/dev/null; then
  echo ""
  info "Nothing to install. All prerequisites are present."
  offer_configure
  exit 0
fi

step "Installing missing prerequisites"
install_missing

# Re-check after install
echo ""
if check_all; then
  echo ""
  info "Setup complete. All prerequisites installed."
  offer_configure
else
  echo ""
  warn "Some tools could not be installed automatically."
  warn "See the messages above for manual installation instructions."
  warn "After installing, re-run: .forge/bin/forge-setup-nanoclaw.sh --check-only"
  exit 1
fi

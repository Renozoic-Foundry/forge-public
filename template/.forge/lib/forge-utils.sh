#!/usr/bin/env bash
# FORGE Shared Utilities
# Spec 058 — Single definition of forge_source() and common bootstrap helpers.
#
# Source this file at the top of any FORGE script that needs to load libraries:
#   source "${FORGE_DIR}/lib/forge-utils.sh"
#   forge_source "${FORGE_DIR}/lib/logging.sh"

# forge_source — Source a bash file, stripping Jinja2 template tags if present.
# Copier template files (.jinja suffix) may contain {% raw %}/{% endraw %} lines.
# Non-template files are sourced directly with no overhead.
forge_source() {
  local src="$1"
  if grep -q '^{%' "$src" 2>/dev/null; then
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/forge-src-XXXXXX.sh")"
    grep -v '^{%' "$src" > "$tmp"
    # shellcheck disable=SC1090
    source "$tmp"
    rm -f "$tmp"
  else
    # shellcheck disable=SC1090
    source "$src"
  fi
}

# forge_exec — Execute a bash script in a subprocess, stripping Jinja2 tags if present.
# Unlike forge_source (which sources into the current shell), this runs the script
# as a separate process. Passes through all arguments after the script path.
# Returns the script's exit code.
forge_exec() {
  local src="$1"
  shift
  if grep -q '^{%' "$src" 2>/dev/null; then
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/forge-exec-XXXXXX.sh")"
    grep -v '^{%' "$src" > "$tmp"
    chmod +x "$tmp"
    bash "$tmp" "$@"
    local rc=$?
    rm -f "$tmp"
    return $rc
  else
    bash "$src" "$@"
  fi
}

# forge_ensure_yubico_path — Add standard Yubico install directories to PATH.
# Non-interactive bash (e.g., launched via PowerShell wrapper) may not source
# .bashrc, so ykman won't be found unless we add these explicitly.
forge_ensure_yubico_path() {
  local _yubi_dir
  for _yubi_dir in \
    "/c/Program Files/Yubico/YubiKey Manager CLI" \
    "/c/Program Files (x86)/Yubico/YubiKey Personalization Tool" \
    "/c/Program Files/Yubico/YubiKey Manager" \
    "$HOME/AppData/Local/Programs/Yubico/YubiKey Manager CLI"; do
    if [[ -d "$_yubi_dir" ]]; then
      case ":$PATH:" in
        *":$_yubi_dir:"*) ;;  # already in PATH
        *) PATH="$_yubi_dir:$PATH" ;;
      esac
    fi
  done
}

# forge_resolve_path — Convert a Unix-style path to OS-native format.
# On Windows (MINGW/MSYS/Cygwin), converts /tmp/ paths and uses cygpath.
# On Linux/Mac, returns the path unchanged.
# Usage: native_path="$(forge_resolve_path "/tmp/forge-test")"
forge_resolve_path() {
  local input_path="$1"
  local uname_out
  uname_out="$(uname -s)"

  case "$uname_out" in
    MINGW*|MSYS*|CYGWIN*)
      # Use cygpath if available (standard in Git Bash / MSYS2)
      if command -v cygpath &>/dev/null; then
        cygpath -w "$input_path"
      else
        # Fallback: manual /tmp/ → $TEMP conversion
        if [[ "$input_path" == /tmp/* ]]; then
          local remainder="${input_path#/tmp/}"
          echo "${TMPDIR:-${TEMP:-/tmp}}\\${remainder//\//\\}"
        else
          echo "$input_path"
        fi
      fi
      ;;
    *)
      # Linux, macOS — return unchanged
      echo "$input_path"
      ;;
  esac
}

# forge_resolve_dir — Resolve FORGE_DIR from script location.
# Accounts for FORGE_SCRIPT_DIR set by .ps1 wrappers.
# Usage: FORGE_DIR="$(forge_resolve_dir)"
forge_resolve_dir() {
  if [[ -n "${FORGE_SCRIPT_DIR:-}" ]]; then
    cd "${FORGE_SCRIPT_DIR}/.." && pwd
  else
    cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd
  fi
}

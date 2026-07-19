#!/usr/bin/env bash
# FORGE config.sh — Parse AGENTS.md runtime configuration
# Sourced by other FORGE scripts. Do not execute directly.

# Global associative array for config values
declare -gA FORGE_CONFIG

forge_config_load() {
  local agents_md="${1:-${PROJECT_DIR}/AGENTS.md}"

  if [[ ! -f "$agents_md" ]]; then
    echo "ERROR: AGENTS.md not found at $agents_md" >&2
    return 1
  fi

  # Extract the YAML block under "## Runtime Configuration"
  local in_block=false
  local in_yaml=false
  local yaml_content=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ Runtime\ Configuration ]]; then
      in_block=true
      continue
    fi
    if $in_block && [[ "$line" =~ ^\`\`\`yaml ]]; then
      in_yaml=true
      continue
    fi
    if $in_yaml && [[ "$line" =~ ^\`\`\` ]]; then
      break
    fi
    if $in_yaml; then
      yaml_content+="$line"$'\n'
    fi
  done < "$agents_md"

  if [[ -z "$yaml_content" ]]; then
    echo "WARN: No runtime configuration found in AGENTS.md — using defaults" >&2
    _forge_config_set_defaults
    return 0
  fi

  # Simple YAML parser — handles flat and one-level nested keys
  local current_section=""
  local current_subsection=""
  while IFS= read -r line; do
    # Skip comments and empty lines
    if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
    if [[ -z "${line// /}" ]]; then continue; fi

    # Top-level section (no leading whitespace, ends with :)
    if [[ "$line" =~ ^([a-z_]+):[[:space:]]*$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      current_subsection=""
      continue
    fi

    # Two-space nested section (ends with :)
    if [[ "$line" =~ ^[[:space:]][[:space:]]([a-z_]+):[[:space:]]*$ ]]; then
      current_subsection="${BASH_REMATCH[1]}"
      continue
    fi

    # Value line (has leading whitespace)
    if [[ "$line" =~ ^[[:space:]]+([a-z_]+):[[:space:]]*(.*) ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      # Strip inline comments
      value="${value%%#*}"
      # Trim trailing whitespace
      value="${value%"${value##*[![:space:]]}"}"

      local full_key=""
      if [[ -n "$current_section" && -n "$current_subsection" ]]; then
        full_key="${current_section}.${current_subsection}.${key}"
      elif [[ -n "$current_section" ]]; then
        full_key="${current_section}.${key}"
      else
        full_key="$key"
      fi
      FORGE_CONFIG["$full_key"]="$value"
      continue
    fi

    # Top-level key-value
    if [[ "$line" =~ ^([a-z_]+):[[:space:]]*(.*) ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      value="${value%%#*}"
      value="${value%"${value##*[![:space:]]}"}"
      FORGE_CONFIG["$key"]="$value"
    fi
  done <<< "$yaml_content"

  _forge_config_set_defaults
}

_forge_config_set_defaults() {
  if [[ -z "${FORGE_CONFIG[runtime.adapter]:-}" ]]; then FORGE_CONFIG["runtime.adapter"]="native"; fi
  if [[ -z "${FORGE_CONFIG[agent.adapter]:-}" ]]; then FORGE_CONFIG["agent.adapter"]="generic"; fi
  if [[ -z "${FORGE_CONFIG[agent.command]:-}" ]]; then FORGE_CONFIG["agent.command"]="claude"; fi
  if [[ -z "${FORGE_CONFIG[isolation.network]:-}" ]]; then FORGE_CONFIG["isolation.network"]="none"; fi
  if [[ -z "${FORGE_CONFIG[isolation.resource_limits.memory]:-}" ]]; then FORGE_CONFIG["isolation.resource_limits.memory"]="2g"; fi
  if [[ -z "${FORGE_CONFIG[isolation.resource_limits.cpus]:-}" ]]; then FORGE_CONFIG["isolation.resource_limits.cpus"]="2"; fi
  if [[ -z "${FORGE_CONFIG[isolation.resource_limits.timeout_seconds]:-}" ]]; then FORGE_CONFIG["isolation.resource_limits.timeout_seconds"]="600"; fi
}

forge_config_get() {
  local key="$1"
  local default="${2:-}"
  echo "${FORGE_CONFIG[$key]:-$default}"
}

# ---- Process-state path indirection (Spec 564) ----
# forge.paths.{specs,sessions,decisions,research,process_kit,backlog} — the SINGLE
# bash-side definition point for process-state path defaults (Req 2). Python twin:
# runtime_config.py `path <key>` action. Config source: nested `forge: paths:` in the
# AGENTS.md `## Runtime Configuration` YAML (parsed by forge_config_load above).
# Defaults are byte-identical to the pre-564 hardcoded layout — absent config changes
# nothing. Works without forge_config_load having run (defaults apply).
declare -gA FORGE_PATH_DEFAULTS=(
  [specs]="docs/specs"
  [sessions]="docs/sessions"
  [decisions]="docs/decisions"
  [research]="docs/research"
  [process_kit]="docs/process-kit"
  [backlog]="docs/backlog.md"
)

# Validate a forge.paths.* value (Spec 564 Req 1 + CISO consensus findings).
# Rejects: backslashes (own invalid class — DA c), POSIX absolutes, drive-letter,
# UNC (//server), `..` segments, and symlink escapes from the repo root.
# Exit nonzero with an error NAMING the offending key.
_forge_path_validate() {
  local key="$1" value="$2"
  local err="forge_path: invalid forge.paths.${key} value '${value}':"
  if [[ -z "$value" ]]; then
    echo "$err empty value" >&2; return 1
  fi
  if [[ "$value" == *\\* ]]; then
    echo "$err backslash in path — values are repo-relative forward-slash paths" >&2; return 1
  fi
  if [[ "$value" == /* ]]; then
    echo "$err absolute or UNC path rejected (must be repo-relative)" >&2; return 1
  fi
  if [[ "$value" =~ ^[A-Za-z]: ]]; then
    echo "$err drive-letter path rejected (must be repo-relative)" >&2; return 1
  fi
  if [[ "$value" == ".." || "$value" == ../* || "$value" == */../* || "$value" == */.. ]]; then
    echo "$err '..' segment rejected" >&2; return 1
  fi
  # Symlink-escape canonicalization: resolve and require containment in the repo
  # root. `realpath -m` (GNU coreutils: Git Bash, Linux); fallback = nearest existing
  # directory-ancestor cd/pwd -P walk (resolves dir symlinks; see Spec 564 Test Plan 4).
  local root="${PROJECT_DIR:-$(pwd)}"
  local root_canon
  root_canon="$(cd "$root" 2>/dev/null && pwd -P)" || { echo "$err repo root '$root' unresolvable" >&2; return 1; }
  local canon=""
  if command -v realpath >/dev/null 2>&1 && realpath -m / >/dev/null 2>&1; then
    canon="$(realpath -m "$root_canon/$value" 2>/dev/null)" || canon=""
  fi
  if [[ -z "$canon" ]]; then
    local anc="$root_canon/$value"
    while [[ ! -d "$anc" && "$anc" == "$root_canon/"* ]]; do anc="${anc%/*}"; done
    if [[ -d "$anc" ]]; then canon="$(cd "$anc" && pwd -P)"; else canon="$root_canon"; fi
  fi
  case "$canon" in
    "$root_canon"|"$root_canon"/*) : ;;
    *) echo "$err resolves outside the repo root (symlink escape) — '$canon' not under '$root_canon'" >&2; return 1 ;;
  esac
  return 0
}

# forge_path <key> — print the resolved repo-relative path for a process-state key.
# Config value (forge.paths.<key>) wins over the default; invalid values exit nonzero.
forge_path() {
  local key="${1:-}"
  local default="${FORGE_PATH_DEFAULTS[$key]:-}"
  if [[ -z "$default" ]]; then
    echo "forge_path: unknown path key '${key}' (known: specs sessions decisions research process_kit backlog)" >&2
    return 2
  fi
  local value="${FORGE_CONFIG[forge.paths.${key}]:-$default}"
  _forge_path_validate "$key" "$value" || return 1
  echo "$value"
}

# Parse budget ceilings from AGENTS.md
forge_config_get_budget() {
  local lane="$1"

  local -A token_limits=([hotfix]=50000 [small-change]=100000 [standard-feature]=300000 [process-only]=50000)
  local -A cost_ceilings=([hotfix]=2.00 [small-change]=5.00 [standard-feature]=15.00 [process-only]=2.00)
  local -A time_limits=([hotfix]=1800 [small-change]=3600 [standard-feature]=14400 [process-only]=1800)

  echo "token_limit=${token_limits[$lane]:-100000}"
  echo "cost_ceiling=${cost_ceilings[$lane]:-5.00}"
  echo "time_limit=${time_limits[$lane]:-3600}"
}

# ---- Onboarding seed readers (Spec 359) ----
# Read keys from .forge/onboarding.yaml. Read-only; the writer for these keys
# is governed by ADR-359 (Python+stdlib). Each function returns the value or
# empty string on null/absent — never errors.

# Internal: extract "  <field>: <value>" line from a named top-level YAML section.
# Args: $1 = section name (e.g., project), $2 = field name, $3 = file path
_forge_onboarding_section_field() {
  local section="$1" field="$2" file="$3"
  [[ -f "$file" ]] || { echo ""; return 0; }
  awk -v section="$section" -v field="$field" '
    BEGIN { in_section = 0 }
    # Empty inline map (e.g., "agents: {}") closes the section immediately.
    $0 ~ "^"section":[[:space:]]*\\{[[:space:]]*\\}" { exit }
    # Section header on its own line opens the block.
    $0 ~ "^"section":[[:space:]]*$" { in_section = 1; next }
    # Any other top-level key closes the block.
    /^[A-Za-z_]/ { in_section = 0 }
    in_section && $0 ~ "^  "field":[[:space:]]" {
      sub("^  "field":[[:space:]]*", "")
      sub("[[:space:]]*#.*$", "")
      sub("[[:space:]]+$", "")
      if ($0 == "null" || $0 == "~") $0 = ""
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$file"
}

# Resolve onboarding.yaml path: optional override arg, then PROJECT_DIR, then cwd.
_forge_onboarding_path() {
  if [[ -n "${1:-}" ]]; then echo "$1"; return 0; fi
  if [[ -n "${PROJECT_DIR:-}" ]]; then echo "${PROJECT_DIR}/.forge/onboarding.yaml"; return 0; fi
  echo ".forge/onboarding.yaml"
}

forge_onboarding_get_methodology() {
  _forge_onboarding_section_field "project" "methodology" "$(_forge_onboarding_path "${1:-}")"
}

forge_onboarding_get_autonomy_level() {
  _forge_onboarding_section_field "project" "autonomy_level" "$(_forge_onboarding_path "${1:-}")"
}

forge_onboarding_get_permission_mode() {
  _forge_onboarding_section_field "project" "permission_mode" "$(_forge_onboarding_path "${1:-}")"
}

forge_onboarding_get_agent_enabled() {
  local agent="$1"
  _forge_onboarding_section_field "agents" "$agent" "$(_forge_onboarding_path "${2:-}")"
}

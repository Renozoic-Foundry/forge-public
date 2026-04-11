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

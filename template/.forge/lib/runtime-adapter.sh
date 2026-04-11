#!/usr/bin/env bash
# FORGE runtime-adapter.sh — Runtime adapter interface
# Sourced by other FORGE scripts. Do not execute directly.
#
# Contract: each runtime adapter must implement:
#   forge_runtime_spawn(role, spec_id, working_dir)
#   forge_runtime_halt(agent_id)
#   forge_runtime_halt_all()
#   forge_runtime_status(agent_id)
#   forge_runtime_cleanup(agent_id)

FORGE_RUNTIME_ADAPTER=""

forge_runtime_load_adapter() {
  local adapter_name
  adapter_name="$(forge_config_get "runtime.adapter" "native")"
  local adapter_file="${FORGE_DIR}/adapters/runtime-${adapter_name}.sh"

  if [[ ! -f "$adapter_file" ]]; then
    echo "ERROR: Runtime adapter '${adapter_name}' not found at ${adapter_file}" >&2
    return 1
  fi

  source "$adapter_file"
  FORGE_RUNTIME_ADAPTER="$adapter_name"

  # Verify the adapter implements the required interface
  local required_fns=(forge_runtime_spawn forge_runtime_halt forge_runtime_halt_all forge_runtime_status forge_runtime_cleanup)
  for fn in "${required_fns[@]}"; do
    if ! declare -f "$fn" > /dev/null 2>&1; then
      echo "ERROR: Runtime adapter '${adapter_name}' does not implement ${fn}()" >&2
      return 1
    fi
  done

  echo "Runtime adapter loaded: ${adapter_name}" >&2
}

#!/usr/bin/env bash
# FORGE runtime-oci.sh — OCI container runtime adapter
# Implements the runtime adapter interface using OCI-compatible container runtimes.
# Works with: docker (dockerd/Rancher Desktop), podman, nerdctl.
# Enforces filesystem permissions via volume mounts with :ro/:rw flags.

FORGE_OCI_RUNTIME=""
FORGE_OCI_IMAGE=""
FORGE_CONTAINER_PREFIX="forge"

# --- Role permission matrix ---
# Defines volume mount access per role
_forge_oci_role_mounts() {
  local role="$1"
  local spec_scope="$2"  # Comma-separated list of writable paths
  local project_dir="$3"
  local audit_dir="$4"
  local handoff_dir="$5"

  local mounts=()

  case "$role" in
    spec-author)
      # Read all project files, write only to docs/specs/
      mounts+=("-v" "${project_dir}:/workspace:ro")
      mounts+=("-v" "${project_dir}/docs/specs:/workspace/docs/specs:rw")
      ;;
    devils-advocate)
      # Read all project files, write nothing (output via handoff volume only)
      mounts+=("-v" "${project_dir}:/workspace:ro")
      ;;
    implementer)
      # Read all project files, write to spec-scoped paths + tests
      mounts+=("-v" "${project_dir}:/workspace:ro")
      if [[ -n "$spec_scope" ]]; then
        IFS=',' read -ra scope_paths <<< "$spec_scope"
        for sp in "${scope_paths[@]}"; do
          sp="$(echo "$sp" | xargs)"  # trim whitespace
          if [[ -n "$sp" ]]; then
            mounts+=("-v" "${project_dir}/${sp}:/workspace/${sp}:rw")
          fi
        done
      fi
      mounts+=("-v" "${project_dir}/tests:/workspace/tests:rw")
      ;;
    validator)
      # Read all project files, execute tests, write nothing
      mounts+=("-v" "${project_dir}:/workspace:ro")
      ;;
    *)
      echo "WARN: Unknown role '${role}' — defaulting to read-only mounts" >&2
      mounts+=("-v" "${project_dir}:/workspace:ro")
      ;;
  esac

  # Audit and handoff volumes are always rw (shared host ↔ container)
  mounts+=("-v" "${audit_dir}:/workspace/.forge/audit:rw")
  mounts+=("-v" "${handoff_dir}:/workspace/.forge/handoffs:rw")

  echo "${mounts[@]}"
}

# --- OCI runtime detection ---
_forge_oci_detect_runtime() {
  local runtimes=("docker" "podman" "nerdctl")

  for rt in "${runtimes[@]}"; do
    if command -v "$rt" > /dev/null 2>&1; then
      if "$rt" info > /dev/null 2>&1; then
        FORGE_OCI_RUNTIME="$rt"
        echo "OCI runtime detected: ${rt}" >&2
        return 0
      fi
    fi
  done

  echo "WARN: No OCI runtime found (checked: docker, podman, nerdctl)" >&2
  echo "WARN: Falling back to native adapter. Install an OCI runtime for container isolation." >&2
  forge_audit_log "runtime" "fallback" "No OCI runtime found — falling back to native adapter"

  # Fall back to native adapter
  source "${FORGE_DIR}/adapters/runtime-native.sh"
  FORGE_RUNTIME_ADAPTER="native-fallback"
  return 0
}

# --- Interface implementation ---

forge_runtime_spawn() {
  local role="$1"
  local spec_id="$2"
  local working_dir="${3:-$PROJECT_DIR}"

  # Detect runtime if not already done
  if [[ -z "$FORGE_OCI_RUNTIME" ]]; then
    _forge_oci_detect_runtime
    if [[ "$FORGE_RUNTIME_ADAPTER" == "native-fallback" ]]; then
      forge_runtime_spawn "$@"
      return $?
    fi
  fi

  local agent_id="spec-${spec_id}-${role}"
  local container_name="${FORGE_CONTAINER_PREFIX}-${agent_id}"

  # Get image name from config
  FORGE_OCI_IMAGE="$(forge_config_get "runtime.image" "forge-agent:latest")"

  # Get resource limits
  local memory_limit
  memory_limit="$(forge_config_get "isolation.resource_limits.memory" "2g")"
  local cpu_limit
  cpu_limit="$(forge_config_get "isolation.resource_limits.cpus" "2")"
  local network
  network="$(forge_config_get "isolation.network" "none")"

  # Ensure audit and handoff directories exist on host
  local audit_dir="${FORGE_AUDIT_DIR:-${working_dir}/.forge/audit}"
  local handoff_dir="${FORGE_HANDOFF_DIR:-${working_dir}/.forge/handoffs}"
  mkdir -p "$audit_dir" "$handoff_dir"

  # Build volume mounts based on role
  local mount_args
  mount_args="$(_forge_oci_role_mounts "$role" "" "$working_dir" "$audit_dir" "$handoff_dir")"

  echo "Spawning OCI container: ${container_name} (role: ${role}, image: ${FORGE_OCI_IMAGE})" >&2
  forge_audit_log "$role" "spawn" "OCI container: ${container_name}, image: ${FORGE_OCI_IMAGE}, network: ${network}, memory: ${memory_limit}, cpus: ${cpu_limit}"

  # Remove any existing container with the same name
  $FORGE_OCI_RUNTIME rm -f "$container_name" 2>/dev/null || true

  # Create and start the container
  local container_id
  container_id="$($FORGE_OCI_RUNTIME run -d \
    --name "$container_name" \
    --label "forge.role=${role}" \
    --label "forge.spec=${spec_id}" \
    --label "forge.session=${SESSION_ID:-unknown}" \
    --label "forge.agent_id=${agent_id}" \
    --memory "$memory_limit" \
    --cpus "$cpu_limit" \
    --network "$network" \
    --workdir /workspace \
    $mount_args \
    "$FORGE_OCI_IMAGE" \
    sleep infinity 2>&1)" || {
    echo "ERROR: Failed to create container ${container_name}" >&2
    forge_audit_log "$role" "fail" "Container creation failed"
    return 1
  }

  echo "OCI container started: ${container_name} (${container_id:0:12})" >&2
  echo "${agent_id}|${container_name}"
}

forge_runtime_halt() {
  local agent_id="$1"
  local container_name="${FORGE_CONTAINER_PREFIX}-${agent_id}"

  if [[ -z "$FORGE_OCI_RUNTIME" ]]; then
    _forge_oci_detect_runtime
    if [[ "$FORGE_RUNTIME_ADAPTER" == "native-fallback" ]]; then
      forge_runtime_halt "$@"
      return $?
    fi
  fi

  echo "Stopping container: ${container_name}" >&2
  $FORGE_OCI_RUNTIME stop -t 10 "$container_name" 2>/dev/null || {
    $FORGE_OCI_RUNTIME kill "$container_name" 2>/dev/null || true
  }

  forge_audit_log "$agent_id" "halt" "OCI container stopped: ${container_name}"
  forge_audit_unregister_pid "$agent_id" "halted"
  echo "Container halted: ${container_name}" >&2
}

forge_runtime_halt_all() {
  if [[ -z "$FORGE_OCI_RUNTIME" ]]; then
    _forge_oci_detect_runtime
    if [[ "$FORGE_RUNTIME_ADAPTER" == "native-fallback" ]]; then
      forge_runtime_halt_all
      return $?
    fi
  fi

  echo "Kill switch activated — stopping all FORGE containers" >&2
  forge_audit_log "pipeline" "kill-switch" "Halting all OCI containers"

  local containers
  containers="$($FORGE_OCI_RUNTIME ps -q --filter "label=forge.role" 2>/dev/null)"

  local count=0
  for cid in $containers; do
    $FORGE_OCI_RUNTIME stop -t 10 "$cid" 2>/dev/null || \
      $FORGE_OCI_RUNTIME kill "$cid" 2>/dev/null || true
    (( count++ ))
  done

  echo "Halted ${count} container(s)" >&2
}

forge_runtime_status() {
  local agent_id="$1"
  local container_name="${FORGE_CONTAINER_PREFIX}-${agent_id}"

  if [[ -z "$FORGE_OCI_RUNTIME" ]]; then
    _forge_oci_detect_runtime
    if [[ "$FORGE_RUNTIME_ADAPTER" == "native-fallback" ]]; then
      forge_runtime_status "$@"
      return $?
    fi
  fi

  # Use format string compatible with docker, podman, nerdctl
  local state
  state="$($FORGE_OCI_RUNTIME inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null)" || {
    echo "unknown"
    return
  }

  echo "$state"
}

forge_runtime_cleanup() {
  local agent_id="$1"
  local container_name="${FORGE_CONTAINER_PREFIX}-${agent_id}"

  if [[ -z "$FORGE_OCI_RUNTIME" ]]; then
    _forge_oci_detect_runtime
    if [[ "$FORGE_RUNTIME_ADAPTER" == "native-fallback" ]]; then
      forge_runtime_cleanup "$@"
      return $?
    fi
  fi

  # Check exit code — preserve failed containers for debugging
  local exit_code
  exit_code="$($FORGE_OCI_RUNTIME inspect --format '{{.State.ExitCode}}' "$container_name" 2>/dev/null)" || exit_code=""

  if [[ "$exit_code" != "0" && -n "$exit_code" ]]; then
    echo "Preserving failed container ${container_name} for debugging" >&2
    echo "  Logs:  ${FORGE_OCI_RUNTIME} logs ${container_name}" >&2
    echo "  Shell: ${FORGE_OCI_RUNTIME} exec -it ${container_name} bash" >&2
    forge_audit_log "$agent_id" "cleanup" "Failed container preserved: ${container_name} (exit code: ${exit_code})"
    return 0
  fi

  # Remove successful containers
  $FORGE_OCI_RUNTIME rm -f "$container_name" 2>/dev/null || true
  echo "Cleaned up container: ${container_name}" >&2
  forge_audit_log "$agent_id" "cleanup" "Container removed: ${container_name}"
}

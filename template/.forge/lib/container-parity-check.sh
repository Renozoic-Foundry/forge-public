#!/usr/bin/env bash
# FORGE container/host parity gate (Spec 541).
#
# Usage:
#   container-parity-check.sh [spec_file] [host_package_json]
#
# Catches host-vs-container divergence at /implement Step 1c:
#   1. Container-name drift — every `docker exec <container>` invocation named in the
#      active spec text must correspond to a container in `docker ps`.
#   2. Package-parity — the host package.json is diffed (line count + dependency list)
#      against the package.json inside the first named container.
#
# Advisory only — never auto-remediates. No-ops cleanly (exit 0) when Docker is absent
# or the daemon is unreachable, so non-container consumers see no friction.
#
# Exit 0 on parity or no-Docker no-op. Exit 1 with a diagnostic on mismatch/drift.

set -euo pipefail

SPEC_FILE="${1:-}"
HOST_PKG="${2:-package.json}"
CONTAINER_APP_DIR="${FORGE_CONTAINER_APP_DIR:-/app}"

# --- No-Docker / no-daemon no-op (must not add friction to non-container consumers) ---
if ! command -v docker >/dev/null 2>&1; then
  echo "container-parity-check: docker not found — no-op (non-container consumer)."
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "container-parity-check: docker daemon not reachable — no-op."
  exit 0
fi

exit_code=0
named_containers=""

# --- Container-name drift: scan spec text for `docker exec <container>` ---
if [[ -n "$SPEC_FILE" && -f "$SPEC_FILE" ]]; then
  running_names="$(docker ps --format '{{.Names}}' 2>/dev/null || true)"
  named_containers="$(grep -oE 'docker exec [A-Za-z0-9_.-]+' "$SPEC_FILE" 2>/dev/null | awk '{print $3}' | sort -u || true)"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if ! grep -qxF "$name" <<< "$running_names"; then
      echo "container-parity-check: container '$name' not found in docker ps"
      exit_code=1
    fi
  done <<< "$named_containers"
fi

# --- Package parity: diff host package.json against the first named container's copy ---
first_container="$(printf '%s\n' "$named_containers" | head -1)"
if [[ -n "$first_container" && -f "$HOST_PKG" ]]; then
  if container_pkg="$(docker exec "$first_container" sh -c "cat '${CONTAINER_APP_DIR}/package.json'" 2>/dev/null)"; then
    host_lines="$(wc -l < "$HOST_PKG" | tr -d ' ')"
    container_lines="$(printf '%s\n' "$container_pkg" | wc -l | tr -d ' ')"
    host_deps="$(grep -oE '"[A-Za-z0-9@/_.-]+"[[:space:]]*:[[:space:]]*"[^"]+"' "$HOST_PKG" | sort -u || true)"
    container_deps="$(printf '%s\n' "$container_pkg" | grep -oE '"[A-Za-z0-9@/_.-]+"[[:space:]]*:[[:space:]]*"[^"]+"' | sort -u || true)"
    if [[ "$host_lines" != "$container_lines" || "$host_deps" != "$container_deps" ]]; then
      echo "container-parity-check: host/container package.json mismatch (host=${host_lines} lines, container=${container_lines} lines)."
      echo "Remediation: docker exec ${first_container} sh -c 'cd ${CONTAINER_APP_DIR} && npm install'"
      exit_code=1
    fi
  fi
fi

if [[ $exit_code -eq 0 ]]; then
  echo "container-parity-check: parity OK."
fi

exit $exit_code

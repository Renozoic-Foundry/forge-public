#!/usr/bin/env bash
# FORGE fetch-before-mint spec-ID helper (Spec 532 — R2).
#
# Prints the next spec ID (zero-padded, e.g. 538) as max+1 over the UNION of:  # forge:path-literal-ok (comment)
#   - the local corpus (docs/specs/ filenames in the current working tree), and
#   - the remote default branch's docs/specs/ listing (best-effort, time-bounded
#     `git fetch origin <default-branch>` + `git ls-tree FETCH_HEAD:docs/specs`).
#
# Two devs minting after the same base commit deterministically collide under a
# local-only max+1 scan; fetching the remote view first eliminates the dominant
# stale-local-view cause. The residual true-race window (neither side pushed
# yet) is detected by check-spec-id-uniqueness.sh at CI and repaired via the
# NNN[a-z] convention (docs/process-kit/parallelism-guide.md).  # forge:path-literal-ok (comment)
#
# Degradation contract (Spec 532 R2): offline / no-remote / fetch-failure /
# timeout → mint from the local-only view, exactly ONE warning line on stderr,
# exit 0. Never blocks, never prompts. READ-ONLY: fetch only, never push — the
# ADR-498 push guard is never in play. Multi-remote note: only the `origin`
# default-branch view is consulted.
#
# Exit 0 = ID printed; 2 = usage/corpus error (no specs dir).
# Run: bash .forge/bin/spec-next-id.sh [--specs-dir <dir>] [--timeout <secs>]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"; fi

# Spec 564: resolve the specs dir via forge.paths indirection (proving consumer).
# Guarded on bash-4 associative-array support so the pre-564 macOS bash-3.2
# degradation path survives: without it, the legacy default applies unchanged.
# An explicit --specs-dir flag below WINS over config resolution (DA precedence).
SPECS_REL="docs/specs"
if declare -A __forge_probe 2>/dev/null; then
  unset __forge_probe
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/../lib/config.sh"
  PROJECT_DIR="$REPO_ROOT" forge_config_load "$REPO_ROOT/AGENTS.md" >/dev/null 2>&1 || true
  if __resolved="$(PROJECT_DIR="$REPO_ROOT" forge_path specs)"; then
    SPECS_REL="$__resolved"
  else
    echo "spec-next-id: invalid forge.paths.specs value — see error above" >&2
    exit 2
  fi
fi
FETCH_TIMEOUT=10

while [ $# -gt 0 ]; do
  case "$1" in
    --specs-dir) SPECS_REL="${2:-}"; shift 2 ;;
    --timeout) FETCH_TIMEOUT="${2:-10}"; shift 2 ;;
    -h|--help) echo "usage: spec-next-id.sh [--specs-dir <rel-dir>] [--timeout <secs>]"; exit 0 ;;
    *) echo "spec-next-id: unknown arg: $1" >&2; exit 2 ;;
  esac
done

SPECS_DIR="$REPO_ROOT/$SPECS_REL"
if [ ! -d "$SPECS_DIR" ]; then
  echo "spec-next-id: specs dir not found: $SPECS_DIR" >&2
  exit 2
fi

# Max numeric ID from a newline list of "NNN[a-z]-slug.md" basenames on stdin.
# Suffixed IDs (532a) count as their numeric stem — the next PLAIN number must
# clear them too.
max_id_from_names() {
  awk '
    match($0, /^[0-9]+/) {
      id = substr($0, RSTART, RLENGTH) + 0
      if (id > max) max = id
    }
    END { print max + 0 }
  '
}

# `sed` basename-strip instead of GNU-only `find -printf` (macOS/BSD portability).
local_max=$(find "$SPECS_DIR" -maxdepth 1 -name '[0-9]*.md' 2>/dev/null | sed 's|.*/||' | max_id_from_names)
if [ -z "$local_max" ]; then local_max=0; fi

# --- Remote view (best-effort; every failure path degrades to local-only) ----
remote_max=0
warn=""
if git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
  # Resolve the remote default branch dynamically (DA: never hardcode `main` —
  # a non-main default branch must not silently degrade forever). Falls back to
  # `main` when origin/HEAD is unset locally (common in fresh clones).
  default_branch=$(git -C "$REPO_ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  if [ -z "$default_branch" ]; then default_branch="main"; fi

  # Time-bounded fetch: a hanging remote must never stall /spec. `timeout` is
  # present in Git for Windows' coreutils; degrade to an unbounded fetch only
  # when the wrapper itself is missing.
  if command -v timeout >/dev/null 2>&1; then
    fetch_cmd=(timeout "$FETCH_TIMEOUT" git -C "$REPO_ROOT" fetch --quiet origin "$default_branch")
  else
    fetch_cmd=(git -C "$REPO_ROOT" fetch --quiet origin "$default_branch")
  fi
  if "${fetch_cmd[@]}" 2>/dev/null; then
    remote_names=$(git -C "$REPO_ROOT" ls-tree --name-only "FETCH_HEAD:$SPECS_REL" 2>/dev/null || true)
    if [ -n "$remote_names" ]; then
      remote_max=$(printf '%s\n' "$remote_names" | max_id_from_names)
    fi
  else
    warn="fetch of origin/$default_branch failed or timed out (${FETCH_TIMEOUT}s)"
  fi
else
  warn="no 'origin' remote configured"
fi

if [ -n "$warn" ]; then
  echo "spec-next-id: warning — $warn; minting from local corpus only (CI uniqueness backstop still applies)" >&2
fi

max=$local_max
if [ "$remote_max" -gt "$max" ]; then max=$remote_max; fi
printf '%03d\n' "$((max + 1))"

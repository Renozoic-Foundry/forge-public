#!/usr/bin/env bash
# FORGE phase-D migration snapshot/restore (Spec 489 D6 / R7 / AC6; root resolution
# fixed by Spec 597 — see below).
#
# Before removing the rendered hooks during phase-D migration, snapshot the rollback-critical files;
# restore them verbatim on rollback. Rollback MUST NOT re-render from Copier — once the scaffolding-only
# shrink ships, a re-render no longer yields the framework hooks or full doctrine (the CTO temporal
# hazard). Restore therefore reads ONLY from the snapshot and refuses if the snapshot is absent.
#
# Project-root resolution (Spec 597 — explicit parameter wins over any location inference;
# NEVER falls back to guessing from this script's own physical path):
#   1. --root DIR       explicit flag (highest priority)
#   2. $PROJECT_ROOT    explicit env var (used only if --root is not given)
#   3. `git -C "$PWD" rev-parse --show-toplevel` — last-resort fallback for direct manual
#      invocation only (operator running the script by hand from inside their project)
#   4. neither resolves -> clear error, exit non-zero (never silently falls through to a
#      script-location guess)
set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: migration-snapshot.sh {snapshot|restore} [--root DIR]

Project root resolution (highest priority wins; see Spec 597):
  1. --root DIR       explicit flag
  2. $PROJECT_ROOT    explicit env var (if --root is not given)
  3. git -C "$PWD" rev-parse --show-toplevel   (direct manual invocation only)
  4. none resolve -> error, exit 2 (never guesses from this script's own location)
USAGE
}

ACTION=""
ROOT_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      ROOT_ARG="${2:-}"
      shift 2
      ;;
    --root=*)
      ROOT_ARG="${1#--root=}"
      shift
      ;;
    snapshot|restore)
      ACTION="$1"
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [ -z "$ACTION" ]; then
  usage
  exit 2
fi

if [ -n "$ROOT_ARG" ]; then
  PROJECT_ROOT="$ROOT_ARG"
elif [ -n "${PROJECT_ROOT:-}" ]; then
  PROJECT_ROOT="$PROJECT_ROOT"
else
  if ! PROJECT_ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "migration-snapshot: no --root/PROJECT_ROOT given and \"$PWD\" is not inside a git repository — cannot resolve the project root. Pass --root DIR or set PROJECT_ROOT." >&2
    exit 2
  fi
fi

if [ ! -d "$PROJECT_ROOT" ]; then
  echo "migration-snapshot: resolved PROJECT_ROOT '$PROJECT_ROOT' is not a directory." >&2
  exit 2
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

SNAP_DIR="$PROJECT_ROOT/.forge/state/migration-snapshot"
# Rollback-critical paths: the rendered hook registration + the full doctrine.
FILES=(".claude/settings.json" "CLAUDE.md" "AGENTS.md")

cmd_snapshot() {
  mkdir -p "$SNAP_DIR"
  local f n=0
  for f in "${FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/$f" ]; then
      mkdir -p "$SNAP_DIR/$(dirname "$f")"
      cp "$PROJECT_ROOT/$f" "$SNAP_DIR/$f"
      n=$((n+1))
    fi
  done
  echo "migration-snapshot: snapshotted $n rollback-critical path(s) -> $SNAP_DIR"
}

cmd_restore() {
  if [ ! -d "$SNAP_DIR" ]; then
    echo "migration-snapshot: no snapshot at $SNAP_DIR — refusing (rollback restores from the snapshot, never re-renders)." >&2
    return 1
  fi
  local f n=0
  for f in "${FILES[@]}"; do
    if [ -f "$SNAP_DIR/$f" ]; then
      mkdir -p "$PROJECT_ROOT/$(dirname "$f")"
      cp "$SNAP_DIR/$f" "$PROJECT_ROOT/$f"
      n=$((n+1))
    fi
  done
  echo "migration-snapshot: restored $n path(s) verbatim from snapshot (no re-render)."
}

case "$ACTION" in
  snapshot) cmd_snapshot ;;
  restore)  cmd_restore ;;
esac

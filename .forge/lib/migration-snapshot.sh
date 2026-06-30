#!/usr/bin/env bash
# FORGE phase-D migration snapshot/restore (Spec 489 D6 / R7 / AC6).
#
# Before removing the rendered hooks during phase-D migration, snapshot the rollback-critical files;
# restore them verbatim on rollback. Rollback MUST NOT re-render from Copier — once the scaffolding-only
# shrink ships, a re-render no longer yields the framework hooks or full doctrine (the CTO temporal
# hazard). Restore therefore reads ONLY from the snapshot and refuses if the snapshot is absent.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"   # .forge/lib -> repo root (two up)
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

case "${1:-}" in
  snapshot) cmd_snapshot ;;
  restore)  cmd_restore ;;
  *) echo "usage: migration-snapshot.sh {snapshot|restore}" >&2; exit 2 ;;
esac

#!/usr/bin/env bash
# validate-readme-stats.sh — Verify README.md counts match filesystem reality.
# Part of Spec 199 — Ship-Readiness Audit Fixes.
#
# Checks:
#   1. Spec count in README.md matches docs/specs/ filesystem
#   2. Session count in README.md matches docs/sessions/ filesystem
#
# Usage: scripts/validate-readme-stats.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README_FILE="${REPO_ROOT}/README.md"
SPECS_DIR="${REPO_ROOT}/docs/specs"
SESSIONS_DIR="${REPO_ROOT}/docs/sessions"

if [[ ! -f "$README_FILE" ]]; then
    echo "ERROR: $README_FILE not found"
    exit 1
fi

errors=0

# --- Count actual spec files ---
# Exclude: _template*.md, README.md, CHANGELOG.md
actual_specs=0
for f in "$SPECS_DIR"/*.md; do
    [[ -e "$f" ]] || continue
    basename="$(basename "$f")"
    case "$basename" in
        _template*.md|README.md|CHANGELOG.md) continue ;;
    esac
    (( actual_specs++ )) || true
done

# --- Count actual session files ---
# Exclude: _template.md, scratchpad.md, signals.md, pattern-analysis.md,
#   evolve-state.md, watchlist.md, context-snapshot.md, error-log.md,
#   insights-log.md, agent-file-registry.md, and parallel-*.md
actual_sessions=0
for f in "$SESSIONS_DIR"/*.md; do
    [[ -e "$f" ]] || continue
    basename="$(basename "$f")"
    case "$basename" in
        _template.md|scratchpad.md|signals.md|pattern-analysis.md) continue ;;
        evolve-state.md|watchlist.md|context-snapshot.md) continue ;;
        error-log.md|insights-log.md|agent-file-registry.md) continue ;;
        parallel-*.md) continue ;;
    esac
    (( actual_sessions++ )) || true
done

# --- Extract counts from README.md ---
# Look for pattern like "NNN specs across NNN sessions"
readme_specs=""
readme_sessions=""
while IFS= read -r line; do
    if [[ "$line" =~ ([0-9]+)[[:space:]]+specs?[[:space:]]+across[[:space:]]+([0-9]+)[[:space:]]+sessions? ]]; then
        readme_specs="${BASH_REMATCH[1]}"
        readme_sessions="${BASH_REMATCH[2]}"
        break
    fi
done < "$README_FILE"

if [[ -z "$readme_specs" || -z "$readme_sessions" ]]; then
    echo "WARNING: Could not find 'N specs across N sessions' pattern in README.md"
    echo "  Actual spec count:    $actual_specs"
    echo "  Actual session count: $actual_sessions"
    echo "  Update README.md manually with these counts."
    exit 1
fi

echo "=== README.md stat verification ==="
echo ""

# --- Compare spec counts ---
echo "Specs:"
echo "  README.md says: $readme_specs"
echo "  Filesystem has:  $actual_specs"
if [[ "$readme_specs" -ne "$actual_specs" ]]; then
    echo "  MISMATCH: README says $readme_specs, but $actual_specs spec files exist"
    (( errors++ )) || true
else
    echo "  OK"
fi

echo ""

# --- Compare session counts ---
echo "Sessions:"
echo "  README.md says: $readme_sessions"
echo "  Filesystem has:  $actual_sessions"
if [[ "$readme_sessions" -ne "$actual_sessions" ]]; then
    echo "  MISMATCH: README says $readme_sessions, but $actual_sessions session files exist"
    (( errors++ )) || true
else
    echo "  OK"
fi

# --- Summary ---
echo ""
echo "---"
if [[ $errors -eq 0 ]]; then
    echo "PASS: README.md stats match filesystem"
    exit 0
else
    echo "FAIL: $errors stat mismatch(es) found"
    echo "  Update the 'N specs across N sessions' line in README.md"
    exit 1
fi

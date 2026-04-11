#!/usr/bin/env bash
# smoke-test-runtime.sh — Cross-platform smoke test for FORGE agent runtime.
# Part of Spec 013 — Cross-Platform Agent Runtime Smoke Test.
#
# Exercises the pipeline in --dry-run mode against a rendered template.
# Works on Git Bash (Windows), bash (Linux/macOS).
#
# Usage: scripts/smoke-test-runtime.sh [rendered-dir]
#   rendered-dir: path to a rendered FORGE template (default: auto-renders via copier)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP + 1)); }

# --- Determine rendered template directory ---
RENDERED_DIR="${1:-}"

if [[ -z "$RENDERED_DIR" ]]; then
  # Auto-render via copier
  RENDER_PARENT="$(mktemp -d)"
  echo "=== Rendering template via copier ==="
  python -m copier copy "$REPO_DIR" "$RENDER_PARENT" --defaults
  # copier creates a subdirectory named after project_slug
  RENDERED_DIR="$(find "$RENDER_PARENT" -mindepth 1 -maxdepth 1 -type d | head -1)"
  echo "  Rendered to: $RENDERED_DIR"
  echo ""
fi

if [[ ! -d "$RENDERED_DIR/.forge" ]]; then
  echo "ERROR: $RENDERED_DIR/.forge not found. Not a valid rendered FORGE template." >&2
  exit 1
fi

FORGE_DIR="$RENDERED_DIR/.forge"

echo "=== FORGE Runtime Smoke Test ==="
echo "  Template: $RENDERED_DIR"
echo ""

# --- Check 1: Source all 6 library files ---
echo "--- Check 1: Source library files ---"

LIB_FILES=(
  "lib/config.sh"
  "lib/runtime-adapter.sh"
  "lib/agent-adapter.sh"
  "lib/audit.sh"
  "lib/handoff.sh"
  "lib/budget.sh"
)

for lib in "${LIB_FILES[@]}"; do
  lib_path="${FORGE_DIR}/${lib}"
  if [[ ! -f "$lib_path" ]]; then
    fail "$lib — file not found"
    continue
  fi
  # Source in a subshell to isolate side effects
  if (
    # Set required vars that libs may reference
    PROJECT_DIR="$RENDERED_DIR"
    export PROJECT_DIR
    source "$lib_path" 2>/dev/null
  ); then
    pass "$lib"
  else
    fail "$lib — sourcing error"
  fi
done
echo ""

# --- Check 2: Verify adapter files exist ---
echo "--- Check 2: Verify adapter files ---"

ADAPTER_FILES=(
  "adapters/runtime-native.sh"
  "adapters/runtime-oci.sh"
  "adapters/agent-generic.sh"
  "adapters/agent-claude-code.sh"
)

for adapter in "${ADAPTER_FILES[@]}"; do
  adapter_path="${FORGE_DIR}/${adapter}"
  if [[ -f "$adapter_path" ]]; then
    pass "$adapter"
  else
    fail "$adapter — file not found"
  fi
done
echo ""

# --- Check 3: Verify bin scripts exist and are parseable ---
echo "--- Check 3: Verify bin scripts ---"

BIN_FILES=(
  "bin/forge-orchestrate.sh"
  "bin/forge-kill.sh"
  "bin/forge-status.sh"
)

for bin in "${BIN_FILES[@]}"; do
  bin_path="${FORGE_DIR}/${bin}"
  if [[ ! -f "$bin_path" ]]; then
    fail "$bin — file not found"
    continue
  fi
  # Syntax check only (don't execute)
  if bash -n "$bin_path" 2>/dev/null; then
    pass "$bin — syntax OK"
  else
    fail "$bin — syntax error"
  fi
done
echo ""

# --- Check 4: Verify template files exist ---
echo "--- Check 4: Verify template files ---"

TEMPLATE_FILES=(
  "templates/handoff-schema.json"
  "templates/role-instructions/spec-author.md"
  "templates/role-instructions/devils-advocate.md"
  "templates/role-instructions/implementer.md"
  "templates/role-instructions/validator.md"
)

for tmpl in "${TEMPLATE_FILES[@]}"; do
  tmpl_path="${FORGE_DIR}/${tmpl}"
  if [[ -f "$tmpl_path" ]]; then
    pass "$tmpl"
  else
    fail "$tmpl — file not found"
  fi
done
echo ""

# --- Check 5: Dry-run orchestrator ---
echo "--- Check 5: Orchestrator dry-run ---"

# Create a minimal fixture spec
FIXTURE_DIR="${RENDERED_DIR}/docs/specs"
mkdir -p "$FIXTURE_DIR"
cat > "${FIXTURE_DIR}/000-smoke-test.md" << 'SPECEOF'
# Spec 000 - Smoke Test Fixture

- Status: draft
- Change-Lane: `small-change`

## Objective
Smoke test fixture — not a real spec.
SPECEOF

# The orchestrator needs AGENTS.md with runtime config to exist
if [[ ! -f "$RENDERED_DIR/AGENTS.md" ]]; then
  fail "AGENTS.md not found — cannot run orchestrator"
else
  # Initialize git repo if not already (orchestrator may need it for worktree ops)
  if [[ ! -d "$RENDERED_DIR/.git" ]]; then
    (cd "$RENDERED_DIR" && git init -q && git add -A && git commit -q -m "smoke test init" 2>/dev/null) || true
  fi

  # Run orchestrator in dry-run mode
  dry_run_output=""
  dry_run_exit=0
  dry_run_output="$(bash "${FORGE_DIR}/bin/forge-orchestrate.sh" --spec 000 --dry-run 2>&1)" || dry_run_exit=$?

  if [[ $dry_run_exit -eq 0 ]]; then
    pass "forge-orchestrate.sh --spec 000 --dry-run (exit 0)"
    # Verify it printed the pipeline plan
    if echo "$dry_run_output" | grep -q "Pipeline Plan"; then
      pass "dry-run output contains pipeline plan"
    else
      fail "dry-run output missing pipeline plan"
    fi
    if echo "$dry_run_output" | grep -q "DRY RUN"; then
      pass "dry-run output contains DRY RUN marker"
    else
      fail "dry-run output missing DRY RUN marker"
    fi
  else
    fail "forge-orchestrate.sh --spec 000 --dry-run (exit $dry_run_exit)"
    echo "    Output: $dry_run_output"
  fi
fi

# Clean up fixture
rm -f "${FIXTURE_DIR}/000-smoke-test.md"
echo ""

# --- Summary ---
echo "=== Summary ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "  Skipped: $SKIP"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "FAIL: $FAIL check(s) failed"
  exit 1
fi

echo "PASS: All checks passed"
exit 0

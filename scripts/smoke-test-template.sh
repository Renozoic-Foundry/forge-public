#!/usr/bin/env bash
# smoke-test-template.sh — Verify Copier template renders cleanly.
# Part of Spec 199 — Ship-Readiness Audit Fixes.
#
# Runs copier copy with defaults, then checks the output for:
#   1. .copier-answers.yml exists with _src_path
#   2. No raw Jinja2 artifacts ({% raw %}, {{ ) in output
#   3. Key files exist (CLAUDE.md, AGENTS.md, .claude/commands/, .forge/commands/)
#
# Usage: scripts/smoke-test-template.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORGE_TEST_DIR="${TMPDIR:-${TEMP:-/tmp}}/forge-smoke-test-$$"

# Cleanup on exit
cleanup() {
    if [[ -d "$FORGE_TEST_DIR" ]]; then
        rm -rf "$FORGE_TEST_DIR"
    fi
}
trap cleanup EXIT

errors=0
details=""

echo "=== FORGE Template Smoke Test ==="
echo "Source:  $REPO_ROOT"
echo "Target:  $FORGE_TEST_DIR"
echo ""

# --- Step 1: Run copier copy ---
echo "Step 1: Running copier copy --defaults ..."
if ! copier copy "$REPO_ROOT" "$FORGE_TEST_DIR" --defaults 2>&1; then
    echo "FAIL: copier copy exited with error"
    exit 1
fi
echo "  copier copy succeeded"
echo ""

# --- Step 2: Verify .copier-answers.yml ---
echo "Step 2: Checking .copier-answers.yml ..."
if [[ -f "$FORGE_TEST_DIR/.copier-answers.yml" ]]; then
    echo "  PASS: .copier-answers.yml exists"
    if grep -q "_src_path" "$FORGE_TEST_DIR/.copier-answers.yml"; then
        echo "  PASS: _src_path present"
    else
        echo "  FAIL: _src_path missing from .copier-answers.yml"
        details+="  - _src_path missing from .copier-answers.yml"$'\n'
        (( errors++ )) || true
    fi
else
    echo "  FAIL: .copier-answers.yml not found"
    details+="  - .copier-answers.yml not found"$'\n'
    (( errors++ )) || true
fi
echo ""

# --- Step 3: Check for Jinja2 artifacts ---
echo "Step 3: Checking for Jinja2 artifacts ..."
# Check for raw/endraw tags
jinja_raw=""
jinja_raw="$(grep -rl '{% raw %}' "$FORGE_TEST_DIR/" 2>/dev/null || true)"
if [[ -n "$jinja_raw" ]]; then
    echo "  FAIL: Found {% raw %} tags in output:"
    echo "$jinja_raw" | while IFS= read -r f; do echo "    $f"; done
    details+="  - Jinja2 {% raw %} tags found in rendered output"$'\n'
    (( errors++ )) || true
else
    echo "  PASS: No {% raw %} tags"
fi

# Check for unrendered {{ variable }} patterns (but skip .copier-answers.yml which is YAML)
jinja_vars=""
jinja_vars="$(grep -rlE '\{\{[^}]*\}\}' "$FORGE_TEST_DIR/" --include='*.md' --include='*.sh' --include='*.yml' --include='*.yaml' 2>/dev/null \
    | grep -v '.copier-answers.yml' || true)"
if [[ -n "$jinja_vars" ]]; then
    echo "  WARN: Possible unrendered {{ }} in output (may be intentional Jinja2 docs):"
    echo "$jinja_vars" | while IFS= read -r f; do echo "    $f"; done
else
    echo "  PASS: No unrendered {{ }} patterns"
fi
echo ""

# --- Step 4: Verify key files exist ---
echo "Step 4: Checking key files ..."
key_files=(
    "CLAUDE.md"
    "AGENTS.md"
    ".claude/commands"
    ".forge/commands"
)

for kf in "${key_files[@]}"; do
    if [[ -e "$FORGE_TEST_DIR/$kf" ]]; then
        echo "  PASS: $kf"
    else
        echo "  FAIL: $kf not found"
        details+="  - Key file/directory missing: $kf"$'\n'
        (( errors++ )) || true
    fi
done
echo ""

# --- Step 5: Check no cookiecutter references ---
echo "Step 5: Checking for stale cookiecutter references ..."
cookie_refs=""
cookie_refs="$(grep -rl 'cookiecutter' "$FORGE_TEST_DIR/" 2>/dev/null || true)"
if [[ -n "$cookie_refs" ]]; then
    echo "  FAIL: Found cookiecutter references in output:"
    echo "$cookie_refs" | while IFS= read -r f; do echo "    $f"; done
    details+="  - Stale cookiecutter references found"$'\n'
    (( errors++ )) || true
else
    echo "  PASS: No cookiecutter references"
fi
echo ""

# --- Summary ---
echo "---"
if [[ $errors -eq 0 ]]; then
    echo "PASS: Template smoke test passed"
    exit 0
else
    echo "FAIL: $errors error(s) found"
    echo ""
    echo "Details:"
    echo "$details"
    exit 1
fi

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
# `--trust` is required by Copier 9.x for templates that define `_tasks` (FORGE
# uses _tasks for the Spec 437 consent gate + Spec 400 migration hook). This is
# distinct from Spec 437's `accept_security_overrides` consent token, which gates
# arbitrary-command-execution via answer-file values. The smoke test asserts a
# clean default-bootstrap path, so --trust is the documented invocation here.
echo "Step 1: Running copier copy --defaults --trust ..."
if ! copier copy "$REPO_ROOT" "$FORGE_TEST_DIR" --defaults --trust 2>&1; then
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
# Check for raw/endraw tags. Filter out matches inside shell-comment lines
# (lines whose first non-whitespace character is `#`), which are intentional
# documentation strings describing the Jinja convention (e.g.,
# forge-utils.sh's "# .jinja files may contain {% raw %} lines" comment).
jinja_raw=""
jinja_raw="$(grep -rln '{% raw %}' "$FORGE_TEST_DIR/" 2>/dev/null \
    | awk -F: '{
        # Re-grep the matched line in the file; suppress if it begins with `#`.
        cmd = "sed -n " $2 "p \"" $1 "\" 2>/dev/null"
        cmd | getline line
        close(cmd)
        sub(/^[[:space:]]+/, "", line)
        if (substr(line, 1, 1) != "#") print $1
    }' | sort -u || true)"
if [[ -n "$jinja_raw" ]]; then
    echo "  FAIL: Found {% raw %} tags in non-comment lines:"
    echo "$jinja_raw" | while IFS= read -r f; do echo "    $f"; done
    details+="  - Jinja2 {% raw %} tags found in rendered output"$'\n'
    (( errors++ )) || true
else
    echo "  PASS: No {% raw %} tags (comment-line occurrences ignored)"
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
# Tightened pattern: only flag genuine unrendered cookiecutter VARIABLES
# ({{ cookiecutter.X }}), not scripts that intentionally grep for the token
# (e.g., forge-test-skills.sh detects pre-migration templates) or detection
# patterns in test fixtures.
echo "Step 5: Checking for stale cookiecutter variable expansions ..."
cookie_refs=""
cookie_refs="$(grep -rlE '\{\{ *cookiecutter\.' "$FORGE_TEST_DIR/" 2>/dev/null || true)"
if [[ -n "$cookie_refs" ]]; then
    echo "  FAIL: Found cookiecutter variable expansions in output:"
    echo "$cookie_refs" | while IFS= read -r f; do echo "    $f"; done
    details+="  - Stale {{ cookiecutter.X }} expansions found"$'\n'
    (( errors++ )) || true
else
    echo "  PASS: No unrendered {{ cookiecutter.X }} expansions"
fi
echo ""

# --- Step 6: Verify _skip_if_exists block declares Spec 441 protected files ---
# Static check on copier.yml — the three consumer-owned top-level files MUST
# appear in `_skip_if_exists` and MUST NOT appear in `_exclude`. Dynamic
# end-to-end `copier update` testing (modify CLAUDE.md, re-update, verify
# preservation) is out of scope for this smoke test because copier update
# requires a fully git-tracked source subproject — not reliably constructable
# in a self-contained smoke fixture. The static check catches the regression
# class (Spec 441) without the brittle integration path.
echo "Step 6: Checking _skip_if_exists declaration in copier.yml (Spec 441) ..."
copier_yml="$REPO_ROOT/copier.yml"
spec_441_files=("AGENTS.md" "CLAUDE.md" ".copier-answers.yml")
# Extract the _skip_if_exists block (lines from `_skip_if_exists:` until next
# top-level key — a line starting with `_` or non-whitespace at column 0).
skip_block="$(awk '
    /^_skip_if_exists:/ { in_block=1; next }
    in_block && /^[^[:space:]]/ { exit }
    in_block { print }
' "$copier_yml")"
exclude_block="$(awk '
    /^_exclude:/ { in_block=1; next }
    in_block && /^[^[:space:]]/ { exit }
    in_block { print }
' "$copier_yml")"
for f in "${spec_441_files[@]}"; do
    if echo "$skip_block" | grep -qE "^[[:space:]]*-[[:space:]]*\"?${f//./\\.}\"?[[:space:]]*$"; then
        if echo "$exclude_block" | grep -qE "^[[:space:]]*-[[:space:]]*\"?${f//./\\.}\"?[[:space:]]*$"; then
            echo "  FAIL: $f appears in BOTH _skip_if_exists AND _exclude (Spec 441 regression)"
            details+="  - $f double-listed in copier.yml"$'\n'
            (( errors++ )) || true
        else
            echo "  PASS: $f in _skip_if_exists (not in _exclude)"
        fi
    else
        echo "  FAIL: $f missing from _skip_if_exists in copier.yml"
        details+="  - $f not declared in _skip_if_exists (Spec 441 regression)"$'\n'
        (( errors++ )) || true
    fi
done
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

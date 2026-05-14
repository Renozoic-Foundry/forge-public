#!/usr/bin/env bash
# test-spec-385-mixed-corpus — AC7: mixed-corpus end-to-end detection (DA round-1 gap)
# Builds a fixture project with three .claude/commands/ files:
#   1. current-format wrapper (post-Spec-316 — 4-field frontmatter, marker on line 6)
#   2. legacy-format wrapper (5-field frontmatter with model_tier, marker on line 8)
#   3. foreign markdown file (no FORGE marker)
# Each has a matching canonical in .forge/commands/. Runs forge-sync-commands.sh --dry-run
# and asserts: zero CONFLICT for the two wrapper formats; one CONFLICT for the foreign file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# --- Build fixture project layout ---
mkdir -p "${TMP_ROOT}/.forge/bin" "${TMP_ROOT}/.forge/lib" "${TMP_ROOT}/.forge/commands"
mkdir -p "${TMP_ROOT}/.claude/commands"

# Copy the script + sourced libs into the fixture project so BASH_SOURCE-derived paths resolve
# to TMP_ROOT, not the live FORGE repo.
cp "${FORGE_DIR}/bin/forge-sync-commands.sh" "${TMP_ROOT}/.forge/bin/"
cp "${FORGE_DIR}/lib/sync-helpers.sh" "${TMP_ROOT}/.forge/lib/"
cp "${FORGE_DIR}/lib/logging.sh" "${TMP_ROOT}/.forge/lib/"

# --- Canonical commands (the "source of truth" the script reads from) ---
for name in cmd-current cmd-legacy cmd-foreign; do
  cat > "${TMP_ROOT}/.forge/commands/${name}.md" <<EOF
---
name: ${name}
description: "Test canonical for ${name}"
workflow_stage: test
---
# Framework: FORGE
Canonical body for ${name}.
EOF
done

# --- Existing wrappers — three different shapes ---
# Current-format (4-field frontmatter): marker on line 6
cat > "${TMP_ROOT}/.claude/commands/cmd-current.md" <<'EOF'
---
name: cmd-current
description: "Current-format wrapper"
workflow_stage: test
---
# Framework: FORGE
Existing body for cmd-current (current format).
EOF

# Legacy-format (5-field frontmatter with model_tier): marker on line 8
cat > "${TMP_ROOT}/.claude/commands/cmd-legacy.md" <<'EOF'
---
name: cmd-legacy
description: "Legacy-format wrapper"
workflow_stage: test
model_tier: haiku
---

# Framework: FORGE
Existing body for cmd-legacy (legacy format).
EOF

# Foreign markdown — frontmatter shape only, no FORGE marker anywhere
cat > "${TMP_ROOT}/.claude/commands/cmd-foreign.md" <<'EOF'
---
name: cmd-foreign
description: "Project-specific custom command — not FORGE-managed"
workflow_stage: custom
---
# Project Custom Command
This file shadows a canonical name but is NOT a FORGE wrapper.
It must produce a CONFLICT (skipped) when sync runs.
EOF

# --- Run the script in dry-run, capture both stdout and stderr ---
output_file="${TMP_ROOT}/sync.out"
if ! bash "${TMP_ROOT}/.forge/bin/forge-sync-commands.sh" --dry-run --agents claude-code \
    > "$output_file" 2>&1; then
  echo "FAIL: forge-sync-commands.sh exited non-zero" >&2
  cat "$output_file" >&2
  exit 1
fi

# --- Assertions ---
fail=0

# 1. Exactly one CONFLICT line, and it must be for cmd-foreign.
conflict_count="$(grep -c "CONFLICT:" "$output_file" || true)"
if [[ "$conflict_count" != "1" ]]; then
  echo "FAIL: expected 1 CONFLICT line, got $conflict_count" >&2
  grep "CONFLICT:" "$output_file" >&2 || true
  fail=1
fi

if ! grep -q "CONFLICT:.*cmd-foreign\.md" "$output_file"; then
  echo "FAIL: expected CONFLICT line for cmd-foreign.md, not found" >&2
  fail=1
fi

# 2. Zero CONFLICT lines for the two wrapper formats — they MUST be detected as FORGE.
for w in cmd-current cmd-legacy; do
  if grep -q "CONFLICT:.*${w}\.md" "$output_file"; then
    echo "FAIL: ${w}.md was classified as non-FORGE (CONFLICT emitted)" >&2
    fail=1
  fi
done

# 3. The two wrapper formats should be reported as "Would generate" (dry-run regen path).
for w in cmd-current cmd-legacy; do
  if ! grep -q "Would generate:.*${w}\.md" "$output_file"; then
    echo "FAIL: ${w}.md was not on the regeneration list" >&2
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "" >&2
  echo "--- Captured output ---" >&2
  cat "$output_file" >&2
  exit 1
fi

echo "PASS: mixed-corpus detection — current + legacy wrappers regenerated; foreign skipped (1 CONFLICT)"
exit 0

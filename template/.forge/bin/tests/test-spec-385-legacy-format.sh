#!/usr/bin/env bash
# test-spec-385-legacy-format — AC2: legacy-format wrapper detection
# 5-field YAML frontmatter (name, description, workflow_stage, model_tier) plus opening/closing
# --- and `# Framework: FORGE` on line 8. is_forge_command MUST return 0 (truthy).
#
# Backward-compat anchor: any haiku-tier wrapper that retained model_tier: pre-Spec-316 must
# still detect correctly under the new structural skip-past-`---` logic.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/sync-helpers.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Legacy wrapper: marker on line 8 (1:--- 2-5:fields 6:--- 7:blank 8:marker)
fixture="${TMP_ROOT}/legacy-format.md"
{
  printf -- '---\n'
  printf 'name: now\n'
  printf 'description: "Quick status check"\n'
  printf 'workflow_stage: status\n'
  printf 'model_tier: haiku\n'
  printf -- '---\n'
  printf '\n'
  printf '# Framework: FORGE\n'
  printf 'Body content for the wrapper.\n'
} > "$fixture"

marker_line="$(grep -n '^# Framework: FORGE' "$fixture" | head -1 | cut -d: -f1)"
if [[ "$marker_line" != "8" ]]; then
  echo "FAIL: fixture setup error — marker on line $marker_line, expected 8" >&2
  exit 1
fi

if is_forge_command "$fixture"; then
  echo "PASS: legacy-format wrapper (marker on line 8) detected"
  exit 0
else
  echo "FAIL: legacy-format wrapper (marker on line 8) NOT detected" >&2
  exit 1
fi

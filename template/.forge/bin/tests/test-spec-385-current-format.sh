#!/usr/bin/env bash
# test-spec-385-current-format — AC1: current-format wrapper detection
# 4-field YAML frontmatter (name, description, workflow_stage + opening/closing ---) and
# `# Framework: FORGE` on line 6. is_forge_command MUST return 0 (truthy).
#
# Spec 385 — structural skip-past-`---` detection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/sync-helpers.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Canonical post-Spec-316 wrapper: marker on line 6 (1:--- 2-4:fields 5:--- 6:marker)
fixture="${TMP_ROOT}/current-format.md"
{
  printf -- '---\n'
  printf 'name: implement\n'
  printf 'description: "Build a spec end-to-end with evidence gates"\n'
  printf 'workflow_stage: implementation\n'
  printf -- '---\n'
  printf '# Framework: FORGE\n'
  printf 'Body content for the wrapper.\n'
} > "$fixture"

# Sanity: confirm marker is actually on line 6
marker_line="$(grep -n '^# Framework: FORGE' "$fixture" | head -1 | cut -d: -f1)"
if [[ "$marker_line" != "6" ]]; then
  echo "FAIL: fixture setup error — marker on line $marker_line, expected 6" >&2
  exit 1
fi

if is_forge_command "$fixture"; then
  echo "PASS: current-format wrapper (marker on line 6) detected"
  exit 0
else
  echo "FAIL: current-format wrapper (marker on line 6) NOT detected" >&2
  exit 1
fi

#!/usr/bin/env bash
# test-spec-385-subcommand — AC3: subcommand wrapper detection
# Wrapper with `## Subcommand:` marker on line 7 (post-frontmatter). is_forge_command MUST
# return 0 (truthy). Subcommand wrappers don't carry `# Framework: FORGE` directly — the
# `## Subcommand:` heading is the alternate marker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/sync-helpers.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Subcommand wrapper: marker on line 7 (1:--- 2-4:fields 5:--- 6:blank 7:marker)
fixture="${TMP_ROOT}/subcommand.md"
{
  printf -- '---\n'
  printf 'name: forge-stoke\n'
  printf 'description: "Stoke subcommand wrapper"\n'
  printf 'workflow_stage: maintenance\n'
  printf -- '---\n'
  printf '\n'
  printf '## Subcommand: stoke\n'
  printf 'Body content for the subcommand.\n'
} > "$fixture"

marker_line="$(grep -n '^## Subcommand:' "$fixture" | head -1 | cut -d: -f1)"
if [[ "$marker_line" != "7" ]]; then
  echo "FAIL: fixture setup error — marker on line $marker_line, expected 7" >&2
  exit 1
fi

if is_forge_command "$fixture"; then
  echo "PASS: subcommand wrapper (## Subcommand: on line 7) detected"
  exit 0
else
  echo "FAIL: subcommand wrapper (## Subcommand: on line 7) NOT detected" >&2
  exit 1
fi

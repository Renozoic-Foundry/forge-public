#!/usr/bin/env bash
# test-spec-385-foreign-reject — AC4: foreign-file rejection
# Markdown file with frontmatter and prose but NO FORGE marker. is_forge_command MUST
# return 1 (falsy) regardless of frontmatter shape. The negative path must remain correct.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/sync-helpers.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Foreign file: frontmatter shape similar to a wrapper but no FORGE/Subcommand marker.
fixture="${TMP_ROOT}/foreign.md"
{
  printf -- '---\n'
  printf 'name: project-custom\n'
  printf 'description: "Project-specific command, not FORGE-managed"\n'
  printf 'workflow_stage: custom\n'
  printf -- '---\n'
  printf '\n'
  printf '# Project Custom Command\n'
  printf 'This file looks like a wrapper but has no FORGE marker.\n'
  printf 'It must remain skipped under sync (not classified as FORGE).\n'
  for i in 1 2 3 4 5; do
    printf 'Padding line %d.\n' "$i"
  done
} > "$fixture"

if is_forge_command "$fixture"; then
  echo "FAIL: foreign file incorrectly classified as FORGE" >&2
  exit 1
else
  echo "PASS: foreign file correctly rejected"
  exit 0
fi

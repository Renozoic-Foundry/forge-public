#!/usr/bin/env bash
# test-spec-387-no-prompt-on-unrelated-diff — AC3.
# safety_config_match_diff returns empty when diff paths don't match any registered pattern.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/safety-config.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
yaml="${TMP}/registry.yaml"
cat > "$yaml" << 'EOF'
patterns:
  - AGENTS.md
  - .forge/safety-config-paths.yaml
EOF

unrelated=$'docs/specs/123-foo.md\nREADME.md\nsrc/foo.py'
result="$(echo "$unrelated" | safety_config_match_diff "$yaml")"
if [[ -z "$result" ]]; then
  echo "PASS: unrelated diff produces empty match set (no prompt fires)"
  exit 0
fi
echo "FAIL: unrelated diff produced match set: $result" >&2
exit 1

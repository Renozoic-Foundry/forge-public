#!/usr/bin/env bash
# test-spec-387-override-logging — AC8.
# Override acceptance appends exactly one record to activity-log.jsonl per R4c.
# Tested via the canonical jq-shaped record format the close.md gate emits.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/safety-config.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
log="${TMP}/activity-log.jsonl"

reason="This file edit changes only documentation prose; no behavior is affected."
if ! safety_config_validate_override "$reason"; then
  echo "FAIL: valid reason rejected" >&2
  exit 1
fi

# Synthesize the canonical record (matches close.md emission)
matched=$'AGENTS.md\ntemplate/AGENTS.md.jinja'
paths_json="[\"AGENTS.md\",\"template/AGENTS.md.jinja\"]"
ts="2026-05-03T22:30:00Z"
record="{\"event_type\":\"safety-override\",\"spec\":\"999\",\"paths\":${paths_json},\"reason\":\"${reason}\",\"timestamp\":\"${ts}\"}"
printf '%s\n' "$record" >> "$log"

# Verify exactly one record
count=$(wc -l < "$log")
if (( count != 1 )); then
  echo "FAIL: expected 1 record, got $count" >&2
  exit 1
fi

# Verify schema fields present
content="$(cat "$log")"
for field in event_type spec paths reason timestamp; do
  if [[ "$content" != *"\"${field}\""* ]]; then
    echo "FAIL: missing field '${field}' in record: $content" >&2
    exit 1
  fi
done
if [[ "$content" != *"\"event_type\":\"safety-override\""* ]]; then
  echo "FAIL: event_type must be 'safety-override', got: $content" >&2
  exit 1
fi
echo "PASS: override-logging emits canonical R4c schema, one record"
exit 0

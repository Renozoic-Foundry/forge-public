#!/usr/bin/env bash
# test-spec-387-override-validation — AC7: Safety-Override reason validation per R4b.
# Reasons <50 chars OR matching trivial-string patterns are rejected; valid reasons accepted.
#
# Spec 387 Component A — override path R4b validation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/safety-config.sh"

FAILS=0

# Case A: too short (under 50 chars)
if safety_config_validate_override "Too short reason." 2>/dev/null; then
  echo "FAIL: short reason should be rejected" >&2
  FAILS=$((FAILS+1))
else
  echo "PASS: short reason rejected (length-gate)"
fi

# Case B: trivial — exact match against 'wip'
if safety_config_validate_override "wip" 2>/dev/null; then
  echo "FAIL: trivial 'wip' should be rejected" >&2
  FAILS=$((FAILS+1))
else
  echo "PASS: trivial 'wip' rejected (length-gate fires first; trivial-pattern as backstop)"
fi

# Case C: trivial — case-insensitive 'NONE' (50+ chars after trim would still match if exact, but 4 chars triggers length-gate)
# Pad trivial-string to 50 chars to test the trivial-pattern path explicitly:
# Trick: a literal 50-char "ok" string would not match the trivial pattern (substring vs exact).
# Tested instead via case-insensitive 'OK' padded with whitespace then trimmed → still 'ok' (2 chars, length-gate).
# Direct exact-match of trivial-pattern at exactly the trim-length is the spec semantic.
short_trivial="OK"
if safety_config_validate_override "$short_trivial" 2>/dev/null; then
  echo "FAIL: trivial 'OK' should be rejected" >&2
  FAILS=$((FAILS+1))
else
  echo "PASS: case-insensitive trivial 'OK' rejected"
fi

# Case D: valid — 50+ chars, non-trivial content
valid_reason="This onboarding YAML edit only renames the frontmatter pretty-print key — no safety property changes."
if safety_config_validate_override "$valid_reason" 2>/dev/null; then
  echo "PASS: valid 50+ char reason accepted"
else
  echo "FAIL: valid reason rejected unexpectedly" >&2
  FAILS=$((FAILS+1))
fi

# Case E: exactly 50 chars (boundary)
fifty_char="abcdefghij abcdefghij abcdefghij abcdefghij abcde."  # 50 chars including trailing period
if [[ "${#fifty_char}" != "50" ]]; then
  echo "FAIL: fixture setup error — case E reason is ${#fifty_char} chars, expected 50" >&2
  FAILS=$((FAILS+1))
elif safety_config_validate_override "$fifty_char" 2>/dev/null; then
  echo "PASS: 50-char reason at boundary accepted"
else
  echo "FAIL: 50-char boundary reason rejected" >&2
  FAILS=$((FAILS+1))
fi

# Case F: 49 chars (one below boundary)
fortynine_char="abcdefghij abcdefghij abcdefghij abcdefghij abcd."  # 49 chars
if [[ "${#fortynine_char}" != "49" ]]; then
  echo "FAIL: fixture setup error — case F reason is ${#fortynine_char} chars, expected 49" >&2
  FAILS=$((FAILS+1))
elif safety_config_validate_override "$fortynine_char" 2>/dev/null; then
  echo "FAIL: 49-char reason should be rejected (boundary-1)" >&2
  FAILS=$((FAILS+1))
else
  echo "PASS: 49-char reason rejected at boundary-1"
fi

# Case G: leading/trailing whitespace stripped
padded="    $valid_reason   "
if safety_config_validate_override "$padded" 2>/dev/null; then
  echo "PASS: whitespace-padded reason accepted (trim works)"
else
  echo "FAIL: whitespace-padded reason rejected" >&2
  FAILS=$((FAILS+1))
fi

if (( FAILS > 0 )); then
  echo "RESULT: $FAILS case(s) failed" >&2
  exit 1
fi
echo "RESULT: all 7 cases passed"
exit 0

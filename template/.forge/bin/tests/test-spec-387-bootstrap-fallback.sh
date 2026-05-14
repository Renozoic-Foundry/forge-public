#!/usr/bin/env bash
# test-spec-387-bootstrap-fallback — AC9: bootstrap fallback fires on registry add/delete.
# When .forge/safety-config-paths.yaml is added or deleted, Component A's prompt path must
# fire even when the registry contents at HEAD are empty or missing (R1c).
#
# Spec 387 Component A — registry self-monitoring + bootstrap fallback.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/safety-config.sh"

FAILS=0

# Case A: diff with registry add (A status) → fallback fires
input_a=$'A\t.forge/safety-config-paths.yaml\nM\tREADME.md'
if echo "$input_a" | safety_config_bootstrap_fallback; then
  echo "PASS: A-status on registry triggers bootstrap fallback"
else
  echo "FAIL: A-status on registry did NOT trigger bootstrap fallback" >&2
  FAILS=$((FAILS+1))
fi

# Case B: diff with registry delete (D status) → fallback fires
input_b=$'D\t.forge/safety-config-paths.yaml'
if echo "$input_b" | safety_config_bootstrap_fallback; then
  echo "PASS: D-status on registry triggers bootstrap fallback"
else
  echo "FAIL: D-status on registry did NOT trigger bootstrap fallback" >&2
  FAILS=$((FAILS+1))
fi

# Case C: diff with registry modify (M status) → fallback does NOT fire (R1a registry-content path handles M)
input_c=$'M\t.forge/safety-config-paths.yaml'
if echo "$input_c" | safety_config_bootstrap_fallback; then
  echo "FAIL: M-status on registry incorrectly triggered bootstrap fallback (R1c is add/delete only)" >&2
  FAILS=$((FAILS+1))
else
  echo "PASS: M-status on registry correctly skips bootstrap fallback"
fi

# Case D: diff without registry → fallback does NOT fire
input_d=$'M\tAGENTS.md\nA\tdocs/specs/123-foo.md'
if echo "$input_d" | safety_config_bootstrap_fallback; then
  echo "FAIL: unrelated diff incorrectly triggered bootstrap fallback" >&2
  FAILS=$((FAILS+1))
else
  echo "PASS: unrelated diff correctly skips bootstrap fallback"
fi

if (( FAILS > 0 )); then
  echo "RESULT: $FAILS case(s) failed" >&2
  exit 1
fi
echo "RESULT: all 4 cases passed"
exit 0

#!/usr/bin/env bash
# check-consensus-classifier-parity.sh (Spec 524 Req 8 / AC9).
#
# The consensus divergence-classifier logic lives in ONE canonical source
# (.forge/lib/consensus-classifier.js). Workflow scripts cannot import modules
# at runtime, so .forge/workflows/consensus.workflow.js embeds a duplicated copy.
# This gate byte-compares the two copies of the sentinel-delimited CLASSIFIER-CORE
# block and FAILs on any divergence — making the anti-drift guarantee structural,
# not dependent on an implementer remembering to run the fixture.
#
# Wired into forge-parity.sh (a new surface). Exit 0 = in sync, 1 = drift, 2 = setup error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CANON="${ROOT}/lib/consensus-classifier.js"
WORKFLOW="${ROOT}/workflows/consensus.workflow.js"

START='>>> forge:consensus-classifier-core'
END='<<< forge:consensus-classifier-core'

extract() {
  # Print the lines strictly between the START and END sentinel markers.
  awk -v s="$START" -v e="$END" '
    index($0, s) { grab=1; next }
    index($0, e) { grab=0 }
    grab { print }
  ' "$1"
}

for f in "$CANON" "$WORKFLOW"; do
  if [[ ! -f "$f" ]]; then
    echo "check-consensus-classifier-parity: missing file $f" >&2
    exit 2
  fi
done

canon_block="$(extract "$CANON")"
wf_block="$(extract "$WORKFLOW")"

if [[ -z "$canon_block" || -z "$wf_block" ]]; then
  echo "check-consensus-classifier-parity: CLASSIFIER-CORE sentinel block empty or missing in one copy" >&2
  exit 2
fi

# CR-normalized compare (.js mirrors may materialize CRLF on Windows checkouts).
if diff <(printf '%s' "$canon_block" | tr -d '\r') <(printf '%s' "$wf_block" | tr -d '\r') >/dev/null 2>&1; then
  echo "consensus-classifier parity: OK (canonical lib == workflow embed)"
  exit 0
else
  echo "  DRIFT: consensus-classifier core differs between .forge/lib/consensus-classifier.js and .forge/workflows/consensus.workflow.js" >&2
  echo "  Edit BOTH sentinel blocks together (Spec 524 Req 8)." >&2
  exit 1
fi

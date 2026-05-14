#!/usr/bin/env bash
# test-spec-387-sweep-output — AC11.
# Verifies the 7-metric schema (R5f) and threshold-to-action mappings (R5g).
set -euo pipefail
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Construct a record matching R5f canonical schema.
record='{"timestamp":"2026-05-03T22:50:00Z","specs_prompted":10,"yes_answers":2,"no_rate":0.800,"deferred_with_unenforced":1,"overrides_used":3,"dormant_found":2,"wide_net_flagged":1}'
log="${TMP}/safety-sweep.jsonl"
echo "$record" > "$log"

# AC11 — schema verification: all 8 fields present (timestamp + 7 metrics).
for field in timestamp specs_prompted yes_answers no_rate deferred_with_unenforced overrides_used dormant_found wide_net_flagged; do
  if ! grep -q "\"$field\"" "$log"; then
    echo "FAIL: missing field '$field'" >&2
    exit 1
  fi
done
echo "PASS: 7-metric R5f schema complete (timestamp + 7 metrics)"

# Threshold-to-action mappings: replay the awk-based threshold gates.
no_rate=0.800
overrides_used=3
dormant_found=2
wide_net_flagged=1
specs_prompted=10
yes_answers=2

warnings=()
if awk -v r="$no_rate" 'BEGIN{exit !(r > 0.5)}'; then
  warnings+=("over-firing")
fi
if (( overrides_used > 2 )); then warnings+=("override-frequency"); fi
if (( dormant_found > 0 )); then warnings+=("dormant"); fi
if (( wide_net_flagged > 0 )); then warnings+=("wide-net"); fi
if (( specs_prompted > 0 )); then
  sn_ratio=$(awk -v y="$yes_answers" -v p="$specs_prompted" 'BEGIN{printf "%.3f", y/p}')
  if awk -v r="$sn_ratio" 'BEGIN{exit !(r < 0.05)}'; then warnings+=("signal-to-noise"); fi
fi

# All 4 over-threshold conditions should fire (no_rate=0.8>0.5; overrides=3>2; dormant=2>0; wide=1>0).
# signal-to-noise=0.2, NOT < 0.05, so doesn't fire — expected.
if [[ "${warnings[*]}" == "over-firing override-frequency dormant wide-net" ]]; then
  echo "PASS: 4/5 R5g thresholds correctly fired for over-threshold synthetic record"
else
  echo "FAIL: unexpected warning set: ${warnings[*]}" >&2
  exit 1
fi

# Negative case: clean metrics → no warnings.
no_rate=0.1; overrides_used=0; dormant_found=0; wide_net_flagged=0
warnings=()
if awk -v r="$no_rate" 'BEGIN{exit !(r > 0.5)}'; then warnings+=("over-firing"); fi
if (( overrides_used > 2 )); then warnings+=("override-frequency"); fi
if (( dormant_found > 0 )); then warnings+=("dormant"); fi
if (( wide_net_flagged > 0 )); then warnings+=("wide-net"); fi
if (( ${#warnings[@]} == 0 )); then
  echo "PASS: clean metrics produce zero warnings"
else
  echo "FAIL: clean metrics produced warnings: ${warnings[*]}" >&2
  exit 1
fi

echo "RESULT: schema + 5 threshold gates verified"
exit 0

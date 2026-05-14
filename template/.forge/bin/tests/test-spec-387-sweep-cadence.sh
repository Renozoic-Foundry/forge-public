#!/usr/bin/env bash
# test-spec-387-sweep-cadence — AC10.
# /evolve runs the safety sweep when prior-sweep timestamp ≥90 days old or absent; skips otherwise.
set -euo pipefail
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

ninety_days=$((90*24*60*60))
now_epoch=$(date -u +%s)

# Replays the cadence gate from evolve.md Step S in isolation.
should_run() {
  local last_ts="$1"
  local last_sweep_epoch=0
  if [[ -n "$last_ts" ]]; then
    last_sweep_epoch=$(date -u -d "$last_ts" +%s 2>/dev/null || echo 0)
  fi
  local age=$((now_epoch - last_sweep_epoch))
  if (( last_sweep_epoch > 0 && age < ninety_days )); then return 1; fi
  return 0
}

# Case A: no prior sweep → runs
if should_run ""; then
  echo "PASS: absent prior sweep triggers run"
else
  echo "FAIL: absent prior sweep should trigger run" >&2
  exit 1
fi

# Case B: 30 days old → skips
recent=$(date -u -d "30 days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-30d +%Y-%m-%dT%H:%M:%SZ)
if should_run "$recent"; then
  echo "FAIL: 30-day-old sweep should skip" >&2
  exit 1
fi
echo "PASS: 30-day-old sweep correctly skips"

# Case C: 91 days old → runs
old=$(date -u -d "91 days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-91d +%Y-%m-%dT%H:%M:%SZ)
if should_run "$old"; then
  echo "PASS: 91-day-old sweep correctly triggers run"
else
  echo "FAIL: 91-day-old sweep should run" >&2
  exit 1
fi

echo "RESULT: 3/3 cases passed"
exit 0

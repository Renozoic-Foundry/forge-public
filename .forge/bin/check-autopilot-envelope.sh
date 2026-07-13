#!/usr/bin/env bash
# FORGE autopilot-envelope validator — thin wrapper (Spec 531).
# Logic lives once, in .forge/lib/autopilot_envelope.py (yaml.safe_load core via
# forge-py — the strategic-scope.py precedent; no hand-rolled YAML parsing here).
#
# Always-strict; no advisory mode. Exit codes: 0 valid/absent; 2 parse (fail
# closed); 3 consent missing/non-matching; 4 unknown key/invalid value.
# Run: bash .forge/bin/check-autopilot-envelope.sh [--agents-md <path>] [--audit <path>]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/forge-py" "$SCRIPT_DIR/../lib/autopilot_envelope.py" "$@"

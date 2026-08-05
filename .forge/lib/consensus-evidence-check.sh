#!/usr/bin/env bash
# FORGE consensus-evidence check (Spec 623) — /implement Step 0d cross-check helper.
#
# Compares a spec's `Consensus-Rounds: <N>` frontmatter marker against the Spec 258
# session-artifact consensus records (`consensus_reviews[]` in docs/sessions/*.json).
# The anchor semantic (Spec 623 Req 3): MAX parseable round for this spec_id across
# ALL matching records across ALL sidecar files. Round fields SHOULD be integers 1-5;
# the parse extracts standalone integers bounded 1-9 and takes the max — unrelated
# large digits in a prose value (e.g. "round 999", timestamps) never inflate it.
#
# Usage: consensus-evidence-check.sh <spec-file> [sessions-dir]
#   sessions-dir defaults to docs/sessions relative to the repo root (two levels up
#   from this script). Tests pass a fixture directory.
#
# Stdout (single line) + exit code:
#   PASS rounds=<N> recorded=<M>            exit 0  (record >= marker)
#   FAIL inflated marker=<N> recorded=<M>   exit 1  (record < marker — tamper-evidence,
#                                                    never crash residue: /consensus flushes
#                                                    the sidecar BEFORE the marker, Req 1)
#   ADJUDICATE <reason> marker=<raw>        exit 2  (could-not-check: no-record |
#                                                    unparseable-rounds | malformed-marker |
#                                                    helper-degraded — routes to the Spec 395
#                                                    exemption/operator-adjudication path;
#                                                    never a silent pass, never the forgery FAIL)
#   NONE no-marker                          exit 3  (no Consensus-Rounds marker — Step 0d
#                                                    proceeds exactly as pre-623: SHA/exempt/FAIL)
set -uo pipefail

SPEC_FILE="${1:?usage: consensus-evidence-check.sh <spec-file> [sessions-dir]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# forge:path-literal-ok (classic-default fallback only; callers pass a forge_path-resolved dir as $2)
SESSIONS_DIR="${2:-${REPO_ROOT}/docs/sessions}"

if [[ ! -f "$SPEC_FILE" ]]; then
  echo "ADJUDICATE helper-degraded marker=spec-file-missing"
  exit 2
fi

# --- Extract the marker (frontmatter form: "- Consensus-Rounds: N") ---
marker_raw="$(grep -m1 -E '^-[[:space:]]*Consensus-Rounds:' "$SPEC_FILE" | sed -E 's/^-[[:space:]]*Consensus-Rounds:[[:space:]]*//' | tr -d '[:space:]' || true)"
if [[ -z "$marker_raw" ]]; then
  echo "NONE no-marker"
  exit 3
fi
if ! [[ "$marker_raw" =~ ^[1-9]$ ]]; then
  echo "ADJUDICATE malformed-marker marker=${marker_raw}"
  exit 2
fi

# --- Spec id from the filename (NNN-*.md) ---
spec_id="$(basename "$SPEC_FILE" | sed -E 's/^([0-9]+)-.*/\1/')"
if ! [[ "$spec_id" =~ ^[0-9]{3,}$ ]]; then
  echo "ADJUDICATE helper-degraded marker=${marker_raw}"
  exit 2
fi

# --- Cross-check needs JSON parsing: python via forge-py or python3. Degraded
#     environments route to could-not-check (never silent pass, never hard error). ---
PYBIN="${REPO_ROOT}/.forge/bin/forge-py"
if [[ ! -x "$PYBIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then PYBIN="python3"; else PYBIN=""; fi
fi
if [[ -z "$PYBIN" ]]; then
  echo "ADJUDICATE helper-degraded marker=${marker_raw}"
  exit 2
fi

result="$("$PYBIN" - "$SESSIONS_DIR" "$spec_id" <<'PYEOF'
import glob, json, os, re, sys
sessions_dir, spec_id = sys.argv[1], sys.argv[2]
found_records = 0
max_round = 0
unparseable = 0
for path in glob.glob(os.path.join(sessions_dir, "*.json")):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        continue  # unreadable sidecar contributes nothing (not this spec's problem)
    for rec in (data.get("consensus_reviews") or []):
        if str(rec.get("spec_id", "")) != spec_id:
            continue
        found_records += 1
        raw = str(rec.get("round", ""))
        # Bounded parse (Spec 623 Req 3): standalone integers 1-9 only; unrelated
        # large digits (999, timestamps) never inflate the max.
        ints = [int(m) for m in re.findall(r"(?<!\d)([1-9])(?!\d)", raw)]
        if ints:
            max_round = max(max_round, max(ints))
        else:
            unparseable += 1
print(f"{found_records} {max_round} {unparseable}")
PYEOF
)" || { echo "ADJUDICATE helper-degraded marker=${marker_raw}"; exit 2; }

read -r found_records max_round _unparseable <<< "$result"

if [[ "$found_records" -eq 0 ]]; then
  echo "ADJUDICATE no-record marker=${marker_raw}"
  exit 2
fi
if [[ "$max_round" -eq 0 ]]; then
  echo "ADJUDICATE unparseable-rounds marker=${marker_raw}"
  exit 2
fi
if [[ "$max_round" -ge "$marker_raw" ]]; then
  echo "PASS rounds=${marker_raw} recorded=${max_round}"
  exit 0
fi
echo "FAIL inflated marker=${marker_raw} recorded=${max_round}"
exit 1

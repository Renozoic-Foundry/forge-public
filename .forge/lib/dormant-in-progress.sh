#!/usr/bin/env bash
# FORGE dormant in-progress detector (Spec 621) — /now Step 1c delegate.
#
# Prints EXACTLY ONE advisory line when any spec with `Status: in-progress` has a
# `Last updated:` STRICTLY older than <threshold-days>; prints nothing at zero.
# Silent-skip (Req 3): specs with a missing OR unparseable `Last updated:` are excluded
# BEFORE any date arithmetic — never the `date -d || printf 0` epoch-0 idiom (it would
# count the spec with a huge age, inverting the requirement). Date math is python.
#
# Status parity (Spec 028 / DA 2026-07-30): the spec FILE's `Status:` frontmatter is the
# single authoritative source; derived_state.py is itself a parser over these same files,
# so this scan and /now Step 1b's helper read the same ground truth. Disjoint from the
# Spec 498 surface by status (in-progress here, implemented there) — no double-count.
#
# Bash-only by the freshness.sh precedent (invoked directly from a /now step).
# Strictly read-only. Always exit 0 (advisory).
#
# Usage: dormant-in-progress.sh [specs-dir] [threshold-days] [today-YYYY-MM-DD]
#   specs-dir defaults to docs/specs under the repo root; threshold defaults to 21;
#   today is injectable for deterministic fixtures.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# forge:path-literal-ok (classic-default fallback only; callers pass a forge_path-resolved dir as $1)
SPECS_DIR="${1:-${ROOT}/docs/specs}"
THRESHOLD="${2:-21}"
TODAY="${3:-}"

PYBIN="${ROOT}/.forge/bin/forge-py"
if [[ ! -x "$PYBIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then PYBIN="python3"; else PYBIN=""; fi
fi
if [[ -z "$PYBIN" ]]; then
  # Degraded environment: advisory line simply absent (deliberate non-reporting — Req 3
  # class; no gate rides on this surface).
  exit 0
fi

"$PYBIN" - "$SPECS_DIR" "$THRESHOLD" "$TODAY" <<'PYEOF' || true
import datetime, glob, os, re, sys

specs_dir, threshold_s, today_s = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    threshold = int(threshold_s)
except ValueError:
    threshold = 21
if today_s:
    try:
        today = datetime.date.fromisoformat(today_s)
    except ValueError:
        sys.exit(0)
else:
    today = datetime.date.today()

dormant = []
for path in sorted(glob.glob(os.path.join(specs_dir, "[0-9]*.md"))):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            head = fh.read(4000)
    except OSError:
        continue
    m_status = re.search(r"^-\s*Status:\s*(\S+)", head, re.M)
    if not m_status or m_status.group(1) != "in-progress":
        continue
    m_updated = re.search(r"^-\s*Last updated:\s*(\S+)", head, re.M)
    if not m_updated:
        continue  # missing — silent skip (Req 3)
    try:
        updated = datetime.date.fromisoformat(m_updated.group(1))
    except ValueError:
        continue  # present-but-unparseable — silent skip BEFORE arithmetic (Req 3)
    age = (today - updated).days
    if age > threshold:  # strictly greater (Req 1)
        m_id = re.match(r"(\d+)-", os.path.basename(path))
        dormant.append(m_id.group(1) if m_id else os.path.basename(path))

if dormant:
    print(f"Dormant in-progress: {len(dormant)} spec(s) untouched >{threshold}d — {', '.join(dormant)}")
PYEOF

exit 0

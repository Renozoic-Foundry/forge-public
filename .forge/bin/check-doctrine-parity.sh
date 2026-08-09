#!/usr/bin/env bash
# check-doctrine-parity.sh — Spec 640 AC1b.
#
# Regenerates the consumer authorization-core managed block from THIS repo's own
# AGENTS.md into a scratch file, then diffs FORGE's declared authorization surface
# (Priority ordering, Requires Confirmation, Authorization-required commands,
# Prohibited) against that generated block. FAILs if any upstream item is missing
# downstream — this is the mechanical backstop that keeps "condense to 60-80 lines"
# from silently becoming "condense away a gate" (doctrine_gen.py's own extraction and
# rendering are what this script regression-tests, not a hand-maintained duplicate).
#
# Usage:
#   bash check-doctrine-parity.sh                 # check this repo's AGENTS.md
#   bash check-doctrine-parity.sh --root <DIR>    # check a fixture/copied tree
# Exit 0 = PASS, 1 = FAIL (missing item(s) named), 2 = usage/extraction error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

AGENTS_MD="$ROOT/AGENTS.md"
GEN="$ROOT/.forge/lib/doctrine_gen.py"
PY="$(command -v python3 || command -v python || true)"

if [ ! -f "$AGENTS_MD" ]; then
  echo "SKIP: $AGENTS_MD missing"
  exit 0
fi
if [ -z "$PY" ]; then
  echo "SKIP: no python3/python on PATH"
  exit 0
fi

TMPD="$(mktemp -d "${TMPDIR:-${TEMP:-/tmp}}/forge-doctrine-parity-XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
SCRATCH_TARGET="$TMPD/consumer-AGENTS.md"
printf '%s\n' "<!-- FORGE:DOCTRINE-ANCHOR id=authorization-core -->" > "$SCRATCH_TARGET"

if ! "$PY" "$GEN" generate --source "$AGENTS_MD" --target "$SCRATCH_TARGET" --version scratch >/dev/null; then
  echo "FAIL: could not generate the scratch consumer block from $AGENTS_MD (extraction error)"
  exit 2
fi

"$PY" "$GEN" parity-check --upstream "$AGENTS_MD" --downstream "$SCRATCH_TARGET"
exit $?

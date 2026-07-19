#!/usr/bin/env bash
# FORGE spec-ID uniqueness backstop (Spec 532 — R1).
#
# Detects the two duplicate-ID defect shapes that today merge SILENTLY (the
# title-join maps in render_changelog.py / derived_state.py are last-write-wins
# by spec_id, so a second spec sharing an ID simply shadows the first):
#   (a) cross-file collision — two spec files resolve to the same spec_id
#       (frontmatter `# Spec NNN` header, filename fallback — the same
#       resolution spec_frontmatter.py uses, reused read-only);
#   (b) intra-file mismatch — a file whose filename ID differs from its own
#       frontmatter header ID (a misnamed file is a collision waiting to happen).
#
# Exit 0 = corpus clean; 1 = violation(s), every offending path named;
# 2 = usage error; 3 = python/helper unavailable.
# Run: bash .forge/bin/check-spec-id-uniqueness.sh [--specs-dir <dir>]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Spec 575 — resolve process-state paths via forge.paths (classic defaults when unset)
SPECS_REL="docs/specs"
_cfg="${SCRIPT_DIR}/../lib/config.sh"
if [ -f "$_cfg" ]; then
  # shellcheck source=/dev/null
  . "$_cfg"
  PROJECT_DIR="$REPO_ROOT" forge_config_load "$REPO_ROOT/AGENTS.md" >/dev/null 2>&1 || true
  __resolved="$(PROJECT_DIR="$REPO_ROOT" forge_path specs 2>/dev/null)" && SPECS_REL="$__resolved"
fi
SPECS_DIR="$REPO_ROOT/$SPECS_REL"

while [ $# -gt 0 ]; do
  case "$1" in
    --specs-dir) SPECS_DIR="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: check-spec-id-uniqueness.sh [--specs-dir <dir>]"; exit 0 ;;
    *) echo "check-spec-id-uniqueness: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ ! -d "$SPECS_DIR" ]; then
  echo "check-spec-id-uniqueness: specs dir not found: $SPECS_DIR" >&2
  exit 2
fi

# The parser lib lives in THIS checkout, even when --specs-dir points at a
# fixture corpus under a test tmpdir that has no .forge/ of its own.
FORGE_CHECKER_LIB="${FORGE_CHECKER_LIB:-$REPO_ROOT/.forge/lib}"
export FORGE_CHECKER_LIB

"$SCRIPT_DIR/forge-py" - "$SPECS_DIR" <<'PY'
import os
import re
import sys
from pathlib import Path

specs_dir = Path(sys.argv[1])
lib = Path(os.environ["FORGE_CHECKER_LIB"])
if not (lib / "spec_frontmatter.py").is_file():
    sys.stderr.write(f"check-spec-id-uniqueness: spec_frontmatter.py not found under {lib}\n")
    raise SystemExit(3)
sys.path.insert(0, str(lib))

from spec_frontmatter import iter_spec_files, parse_frontmatter  # noqa: E402

_FILENAME_ID_RE = re.compile(r"^(\d+[a-z]?)-")

by_id: dict[str, list[str]] = {}
mismatches: list[tuple[str, str, str]] = []

for f in iter_spec_files(specs_dir):
    try:
        text = f.read_text(encoding="utf-8", errors="replace")
    except OSError:
        continue
    fm = parse_frontmatter(text)
    header_id = fm.get("spec_id", "")
    m = _FILENAME_ID_RE.match(f.name)
    filename_id = m.group(1) if m else ""
    if header_id and filename_id and header_id != filename_id:
        mismatches.append((str(f), filename_id, header_id))
    effective = header_id or filename_id
    if effective:
        by_id.setdefault(effective, []).append(str(f))

fail = False
for sid in sorted(by_id):
    paths = by_id[sid]
    if len(paths) > 1:
        fail = True
        print(f"DUPLICATE spec_id {sid}:")
        for p in sorted(paths):
            print(f"  - {p}")
for path, fn_id, hdr_id in sorted(mismatches):
    fail = True
    print(f"MISMATCH {path}: filename ID {fn_id} != frontmatter header ID {hdr_id}")

if fail:
    print("check-spec-id-uniqueness: FAIL — repair convention: the not-yet-merged "
          "side re-suffixes to NNN[a-z] (see docs/process-kit/parallelism-guide.md)")  # forge:path-literal-ok (comment)
    raise SystemExit(1)
print(f"check-spec-id-uniqueness: OK — {len(by_id)} unique spec IDs")
PY

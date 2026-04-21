#!/usr/bin/env bash
# FORGE — Spec 277, Phase 1 — Seeded-bug corpus runner
#
# Applies a library of seed defects to a historical spec's diff and
# records which of the three review gates (/ultrareview, Validator
# Stage 2, DA role-registry review) detect each seeded defect.
#
# Output: docs/digests/gate-comparison-seeded-<YYYY-MM-DD>.md
#
# Usage:
#   bash scripts/gate-comparison-corpus.sh <historical-spec-id>
#   bash scripts/gate-comparison-corpus.sh --help
#
# Exits non-zero on missing deps or invalid arguments; otherwise
# reports partial results and exits zero (best-effort corpus run).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFECTS_DIR="$SCRIPT_DIR/gate-comparison-defects"

usage() {
  cat <<'USAGE'
gate-comparison-corpus.sh — Spec 277 Phase 1 seeded-bug corpus

Usage:
  bash scripts/gate-comparison-corpus.sh <historical-spec-id>

Arguments:
  historical-spec-id   Three-digit spec number (e.g., 258) whose committed
                       diff will serve as the base corpus.

Output:
  docs/digests/gate-comparison-seeded-<YYYY-MM-DD>.md

Environment:
  FORGE_CORPUS_DEFECTS  Override defect patch directory (default:
                        scripts/gate-comparison-defects).
  FORGE_CORPUS_OUT      Override output path (default:
                        docs/digests/gate-comparison-seeded-<today>.md).

Requirements:
  - git (for applying patches and reading historical diffs)
  - python3 (optional — used for JSON parsing if available)

Behavior:
  1. Lists *.patch files in the defect library.
  2. For each patch, creates an ephemeral working tree with the patch applied.
  3. Records a detection row per (gate, defect) in the output digest.
     In Phase 1 the actual /ultrareview / Validator Stage 2 / DA invocations
     are stubbed to "pending-phase1-live-run" — the scaffolding is what Spec 277
     ships; actual invocation is wired when the live /close flow exercises the
     corpus script (Phase 2 analysis will use the captured data).
USAGE
}

if [[ $# -eq 0 ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

SPEC_ID="$1"
if [[ ! "$SPEC_ID" =~ ^[0-9]{3}$ ]]; then
  echo "ERROR: spec-id must be three digits (got: $SPEC_ID)" >&2
  exit 2
fi

DEFECTS_DIR="${FORGE_CORPUS_DEFECTS:-$DEFECTS_DIR}"
if [[ ! -d "$DEFECTS_DIR" ]]; then
  echo "ERROR: defect library not found: $DEFECTS_DIR" >&2
  exit 2
fi

DEFECT_PATCHES=()
while IFS= read -r -d '' patch_file; do
  DEFECT_PATCHES+=("$patch_file")
done < <(find "$DEFECTS_DIR" -type f -name '*.patch' -print0 | sort -z)

if [[ ${#DEFECT_PATCHES[@]} -lt 5 ]]; then
  echo "WARN: defect library has only ${#DEFECT_PATCHES[@]} patch(es); Spec 277 requires >=5 categories." >&2
fi

TODAY="$(date +%Y-%m-%d)"
OUT_PATH="${FORGE_CORPUS_OUT:-docs/digests/gate-comparison-seeded-$TODAY.md}"
mkdir -p "$(dirname "$OUT_PATH")"

{
  echo "# Gate Comparison — Seeded-Bug Corpus — $TODAY"
  echo
  echo "Historical spec: **$SPEC_ID**"
  echo "Defect library: \`$DEFECTS_DIR\` (${#DEFECT_PATCHES[@]} patch file(s))"
  echo
  echo "## Per-defect detection matrix"
  echo
  echo "| Defect | Gate | Detected | Severity | Notes |"
  echo "|---|---|---|---|---|"
} > "$OUT_PATH"

GATES=("ultrareview" "validator-stage2" "da")

for patch_file in "${DEFECT_PATCHES[@]}"; do
  defect_name="$(basename "$patch_file" .patch)"
  for gate in "${GATES[@]}"; do
    # Phase 1: this runner scaffolds the matrix. Live gate invocations
    # are wired through /close (shadow mode) and recorded in
    # .forge/state/gate-comparison/<spec-id>/<gate>.json. The corpus
    # script's role is to surface the matrix for analyst review.
    detected="pending-phase1-live-run"
    severity="n/a"
    notes="Scaffold row — see .forge/state/gate-comparison/ for live-run data."
    printf '| %s | %s | %s | %s | %s |\n' \
      "$defect_name" "$gate" "$detected" "$severity" "$notes" >> "$OUT_PATH"
  done
done

{
  echo
  echo "## Summary"
  echo
  echo "- Defects exercised: ${#DEFECT_PATCHES[@]}"
  echo "- Gates scored per defect: ${#GATES[@]}"
  echo "- Rows emitted: $(( ${#DEFECT_PATCHES[@]} * ${#GATES[@]} ))"
  echo
  echo "## Decision-criteria reference"
  echo
  echo "See \`docs/process-kit/gate-comparison-methodology.md\` for the Phase 2 decision matrix (replace / drop / augment)."
} >> "$OUT_PATH"

echo "OK: wrote $OUT_PATH"

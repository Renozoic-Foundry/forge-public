#!/usr/bin/env bash
# FORGE render-time visual-verification fixture (Spec 545).
#
# Given an HTML/visual artifact path, walks the operator through a render-time
# visual check (open the artifact in the render target, confirm layout/content/
# theme, record the outcome) and writes a manifest entry in the SAME evidence
# convention as Spec 093/540 browser evidence:
#   tmp/evidence/SPEC-NNN-browser-YYYYMMDD/manifest.json
# There is exactly one manifest family — this fixture does not invent a second
# convention. See docs/process-kit/human-validation-runbook.md section H.  # forge:path-literal-ok (comment)
#
# Usage:
#   forge-visual-verify.sh <spec-number> <artifact-path> [options]
#
# Options:
#   --result pass|fail     Record outcome without prompting (non-interactive / CI use)
#   --notes "<text>"       Notes to attach to the recorded step (default: none)
#   --evidence-dir <path>  Override evidence output directory
#   -h, --help             Show this help
set -euo pipefail

usage() {
  sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# //' | sed 's/^#//'
}

SPEC_NUM=""
ARTIFACT_PATH=""
RESULT=""
NOTES=""
EVIDENCE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --result) RESULT="$2"; shift 2 ;;
    --notes) NOTES="$2"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$SPEC_NUM" ]]; then
        SPEC_NUM="$1"
      elif [[ -z "$ARTIFACT_PATH" ]]; then
        ARTIFACT_PATH="$1"
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$SPEC_NUM" || -z "$ARTIFACT_PATH" ]]; then
  echo "Usage: forge-visual-verify.sh <spec-number> <artifact-path> [--result pass|fail] [--notes \"text\"]" >&2
  exit 1
fi

if [[ ! -f "$ARTIFACT_PATH" ]]; then
  echo "Artifact not found: $ARTIFACT_PATH" >&2
  exit 1
fi

SPEC_DISPLAY="$(printf '%03d' "$SPEC_NUM" 2>/dev/null || echo "$SPEC_NUM")"

if [[ -z "$EVIDENCE_DIR" ]]; then
  EVIDENCE_DIR="tmp/evidence/SPEC-${SPEC_DISPLAY}-browser-$(date +%Y%m%d)"
fi
mkdir -p "$EVIDENCE_DIR"

echo "FORGE render-time visual verification — Spec ${SPEC_DISPLAY}"
echo "Artifact: ${ARTIFACT_PATH}"
echo "Evidence dir: ${EVIDENCE_DIR}"

# --- Walk the operator through the check (interactive unless --result given) ---
if [[ -z "$RESULT" ]]; then
  echo ""
  echo "Open the artifact in the render target (browser) and confirm:"
  echo "  1. Layout renders as expected (no broken CSS/overflow)"
  echo "  2. Content matches the spec's expected copy/data"
  echo "  3. Theme (light/dark) renders correctly if applicable"
  read -r -p "Did the artifact pass the visual check? (y/n): " ans
  if [[ "$ans" =~ ^[Yy] ]]; then
    RESULT="pass"
  else
    RESULT="fail"
  fi
  read -r -p "Notes (optional): " NOTES
fi

if [[ "$RESULT" != "pass" && "$RESULT" != "fail" ]]; then
  echo "--result must be 'pass' or 'fail', got: $RESULT" >&2
  exit 1
fi

PASSED_BOOL="false"
if [[ "$RESULT" == "pass" ]]; then
  PASSED_BOOL="true"
fi

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOTES_ESC="$(json_escape "$NOTES")"
ARTIFACT_ESC="$(json_escape "$ARTIFACT_PATH")"

TOTAL=1
PASSED=0
FAILED=0
if [[ "$PASSED_BOOL" == "true" ]]; then PASSED=1; else FAILED=1; fi

MANIFEST="${EVIDENCE_DIR}/manifest.json"
cat > "$MANIFEST" << EOF
{
  "spec": "${SPEC_DISPLAY}",
  "startTime": "${NOW}",
  "endTime": "${NOW}",
  "steps": [
    {
      "index": 0,
      "action": "render-time visual verification",
      "artifact": "${ARTIFACT_ESC}",
      "assessment": {
        "passed": ${PASSED_BOOL},
        "notes": "${NOTES_ESC}"
      }
    }
  ],
  "summary": { "total": ${TOTAL}, "passed": ${PASSED}, "failed": ${FAILED}, "warnings": 0 },
  "videoPath": null
}
EOF

SUMMARY="${EVIDENCE_DIR}/summary.md"
{
  echo "# Visual Evidence Summary — Spec ${SPEC_DISPLAY}"
  echo ""
  echo "- Artifact: ${ARTIFACT_PATH}"
  echo "- Results: ${PASSED}/${TOTAL} passed"
  if [[ "$FAILED" -gt 0 ]]; then
    echo "  (${FAILED} failed)"
  fi
  echo "- Notes: ${NOTES:-none}"
} > "$SUMMARY"

echo ""
echo "Manifest: ${MANIFEST}"
echo "Summary: ${SUMMARY}"

if [[ "$RESULT" == "fail" ]]; then
  exit 1
fi
exit 0

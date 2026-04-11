#!/usr/bin/env bash
# FORGE Browser Test Runner — run Puppeteer/Playwright tests and capture visual evidence
# Usage: forge-browser-test.sh <spec-number> [options]
#
# Options:
#   --url <base-url>       Application URL (default: http://localhost:3000)
#   --headed               Run browser in headed mode (visible window)
#   --no-video             Disable video recording
#   --runner <name>        Force "puppeteer" or "playwright" (auto-detected by default)
#   --browser <type>       Browser: chromium, firefox, webkit (Playwright only, default: chromium)
#   --test-file <path>     Path to test script (default: auto-generated from spec)
#   --evidence-dir <path>  Override evidence output directory
#   -h, --help             Show this help
set -euo pipefail

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${FORGE_DIR}/.." && pwd)"

source "${FORGE_DIR}/lib/logging.sh"

forge_log_init "forge-browser-test"

# --- Defaults ---
SPEC_NUM=""
BASE_URL="http://localhost:3000"
HEADLESS="true"
VIDEO="true"
RUNNER=""
BROWSER="chromium"
TEST_FILE=""
EVIDENCE_DIR=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) BASE_URL="$2"; shift 2 ;;
    --headed) HEADLESS="false"; shift ;;
    --no-video) VIDEO="false"; shift ;;
    --runner) RUNNER="$2"; shift 2 ;;
    --browser) BROWSER="$2"; shift 2 ;;
    --test-file) TEST_FILE="$2"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    *)
      if [[ -z "$SPEC_NUM" ]]; then
        SPEC_NUM="$1"
      else
        forge_log error "Unknown argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$SPEC_NUM" ]]; then
  forge_log error "Spec number required. Usage: forge-browser-test.sh <spec-number>"
  exit 1
fi

# Normalize spec number (strip leading zeros for dir, keep for display)
SPEC_DISPLAY="$(printf '%03d' "$SPEC_NUM" 2>/dev/null || echo "$SPEC_NUM")"

# --- Set evidence directory ---
if [[ -z "$EVIDENCE_DIR" ]]; then
  EVIDENCE_DIR="${PROJECT_DIR}/tmp/evidence/SPEC-${SPEC_DISPLAY}-browser-$(date +%Y%m%d)"
fi

mkdir -p "$EVIDENCE_DIR"

forge_log info "FORGE Browser Test — Spec ${SPEC_DISPLAY}"
forge_log info "Evidence dir: ${EVIDENCE_DIR}"

# --- Check Node.js ---
if ! command -v node &>/dev/null; then
  forge_log error "Node.js is required for browser tests. Install from https://nodejs.org/"
  exit 1
fi

# --- Auto-detect runner if not specified ---
if [[ -z "$RUNNER" ]]; then
  if [[ -d "${PROJECT_DIR}/node_modules/playwright" ]]; then
    RUNNER="playwright"
  elif [[ -d "${PROJECT_DIR}/node_modules/puppeteer" ]]; then
    RUNNER="puppeteer"
  else
    forge_log warn "No browser test framework found."
    forge_log info "Install one:"
    forge_log info "  npm install --save-dev playwright"
    forge_log info "  npm install --save-dev puppeteer"
    exit 1
  fi
fi

forge_log info "Runner: ${RUNNER}"
forge_log info "Base URL: ${BASE_URL}"
forge_log info "Headless: ${HEADLESS}"
forge_log info "Video: ${VIDEO}"

# --- Locate test file ---
if [[ -z "$TEST_FILE" ]]; then
  # Look for spec-specific browser test
  TEST_FILE=$(find "${PROJECT_DIR}" -maxdepth 3 -name "browser-test-${SPEC_DISPLAY}.js" -o -name "browser-test-${SPEC_DISPLAY}.ts" 2>/dev/null | head -1)

  if [[ -z "$TEST_FILE" ]]; then
    # Look for generic test in evidence dir
    TEST_FILE="${EVIDENCE_DIR}/browser-test.js"
    if [[ ! -f "$TEST_FILE" ]]; then
      forge_log warn "No browser test script found for Spec ${SPEC_DISPLAY}."
      forge_log info "Generate one by running /implement with UI acceptance criteria,"
      forge_log info "or create manually at: browser-test-${SPEC_DISPLAY}.js"
      forge_log info ""
      forge_log info "Template available at: ${FORGE_DIR}/templates/browser-test-template.js"
      exit 0
    fi
  fi
fi

forge_log info "Test file: ${TEST_FILE}"

# --- Run the test ---
export FORGE_SPEC="$SPEC_DISPLAY"
export FORGE_EVIDENCE_DIR="$EVIDENCE_DIR"
export FORGE_BASE_URL="$BASE_URL"
export FORGE_HEADLESS="$HEADLESS"
export FORGE_VIDEO="$VIDEO"
export FORGE_RUNNER="$RUNNER"
export FORGE_BROWSER="$BROWSER"

forge_log info "Running browser test..."

cd "$PROJECT_DIR"
if node "$TEST_FILE"; then
  forge_log info "Browser test completed successfully."
  EXIT_CODE=0
else
  EXIT_CODE=$?
  forge_log warn "Browser test exited with code ${EXIT_CODE}."
fi

# --- Report evidence ---
if [[ -f "${EVIDENCE_DIR}/manifest.json" ]]; then
  forge_log info "Evidence manifest: ${EVIDENCE_DIR}/manifest.json"

  SCREENSHOT_COUNT=$(find "$EVIDENCE_DIR" -name "*.png" 2>/dev/null | wc -l)
  forge_log info "Screenshots captured: ${SCREENSHOT_COUNT}"

  if [[ -f "${EVIDENCE_DIR}/summary.md" ]]; then
    forge_log info "Summary report: ${EVIDENCE_DIR}/summary.md"
  fi

  VIDEO_COUNT=$(find "$EVIDENCE_DIR" -name "*.mp4" -o -name "*.webm" 2>/dev/null | wc -l)
  if [[ "$VIDEO_COUNT" -gt 0 ]]; then
    forge_log info "Video recordings: ${VIDEO_COUNT}"
  fi
else
  forge_log warn "No evidence manifest generated. Check test script output."
fi

forge_log info "FORGE Browser Test — complete"
exit "$EXIT_CODE"

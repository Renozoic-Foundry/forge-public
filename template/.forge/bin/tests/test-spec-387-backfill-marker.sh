#!/usr/bin/env bash
# test-spec-387-backfill-marker — AC13.
# Audit script writes the .forge/state/safety-backfill-deadline.txt marker on completion
# AND --dry-run mode does NOT write the marker.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Walk up to find the repo-root scripts/safety-backfill-audit.sh.
# (Template-side fixtures live under template/.forge/...; own-copy under .forge/...; both
# share the same scripts/ directory at the actual repo root.)
find_repo_root() {
  local dir="$1"
  while [[ "$dir" != "/" && "$dir" != "" ]]; do
    if [[ -f "$dir/scripts/safety-backfill-audit.sh" ]]; then
      printf '%s' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}
REPO_ROOT="$(find_repo_root "$FORGE_DIR")"
if [[ -z "${REPO_ROOT:-}" ]]; then
  echo "FAIL: cannot locate scripts/safety-backfill-audit.sh from $FORGE_DIR" >&2
  exit 1
fi
AUDIT_SCRIPT="${REPO_ROOT}/scripts/safety-backfill-audit.sh"

if [[ ! -x "$AUDIT_SCRIPT" ]]; then
  chmod +x "$AUDIT_SCRIPT" 2>/dev/null || true
fi
if [[ ! -x "$AUDIT_SCRIPT" ]]; then
  echo "FAIL: audit script not executable: $AUDIT_SCRIPT" >&2
  exit 1
fi

# Run --dry-run in a synthetic workspace; verify NO marker is written.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "${TMP}/.forge/lib" "${TMP}/.forge/state" "${TMP}/scripts" "${TMP}/docs/specs"
cp "${FORGE_DIR}/lib/safety-config.sh" "${TMP}/.forge/lib/safety-config.sh"
cp "${FORGE_DIR}/safety-config-paths.yaml" "${TMP}/.forge/safety-config-paths.yaml"
cp "$AUDIT_SCRIPT" "${TMP}/scripts/safety-backfill-audit.sh"
chmod +x "${TMP}/scripts/safety-backfill-audit.sh"

cd "$TMP"
bash scripts/safety-backfill-audit.sh --dry-run > /dev/null
if [[ -f .forge/state/safety-backfill-deadline.txt ]]; then
  echo "FAIL: --dry-run wrote the deadline marker" >&2
  exit 1
fi
echo "PASS: --dry-run does not write deadline marker"

# Run full mode; verify marker IS written.
bash scripts/safety-backfill-audit.sh > /dev/null
if [[ ! -f .forge/state/safety-backfill-deadline.txt ]]; then
  echo "FAIL: full mode did not write the deadline marker" >&2
  exit 1
fi
deadline=$(cat .forge/state/safety-backfill-deadline.txt)
# Sanity: deadline is in the future.
deadline_epoch=$(date -u -d "$deadline" +%s 2>/dev/null \
  || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$deadline" +%s 2>/dev/null)
now_epoch=$(date -u +%s)
if (( deadline_epoch <= now_epoch )); then
  echo "FAIL: deadline ($deadline) is not in the future" >&2
  exit 1
fi
delta=$((deadline_epoch - now_epoch))
# Should be ~30 days (allow slack: 29-31 days).
if (( delta < 29*86400 || delta > 31*86400 )); then
  echo "FAIL: deadline delta is $((delta/86400)) days, expected ~30" >&2
  exit 1
fi
echo "PASS: full mode writes deadline marker, delta is ~30 days from now"
echo "RESULT: marker behavior verified for both modes"
exit 0

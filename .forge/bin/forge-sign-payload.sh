#!/usr/bin/env bash
# FORGE plugin payload signing — release step (Spec 488).
#
# Builds the canonical payload manifest (.forge/lib/payload-manifest.sh), writes it into
# the payload, and produces a minisign DETACHED signature whose SIGNED trusted comment
# carries `tier=<tier> version=<version>` (downgrade/tier-swap protection, R2/R10).
#
# FAIL-CLOSED (R8/AC13): any failure aborts non-zero AND removes a partial manifest/sig so
# a release/sync pipeline can never ship an unsigned or partial payload.
#
# Per-tier signing happens at each tier's release step AFTER its transform (R6); this tool
# signs whatever payload `--root` points at, with whatever `--key` the tier provides.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/../lib/payload-manifest.sh"

usage() {
  echo "usage: forge-sign-payload.sh --tier <t> --version <v> --key <seckey> [--root <dir>] [--password-file <f>]" >&2
}

TIER="" VERSION="" KEY="" ROOT="" PWFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --key) KEY="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    --password-file) PWFILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "forge-sign-payload: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$TIER" ] || [ -z "$VERSION" ] || [ -z "$KEY" ]; then
  echo "forge-sign-payload: --tier, --version, --key are required" >&2; usage; exit 2
fi
if ! command -v minisign >/dev/null 2>&1; then
  echo "forge-sign-payload: minisign not found — cannot sign (fail-closed)" >&2; exit 3
fi
ROOT="${ROOT:-${FORGE_ASSET_ROOT:-$PWD}}"
ROOT="$(printf '%s' "$ROOT" | tr '\\' '/')"
if [ ! -f "$KEY" ]; then
  echo "forge-sign-payload: secret key not found: $KEY" >&2; exit 3
fi

MANIFEST="$ROOT/$FORGE_MANIFEST_RELPATH"
SIG="$ROOT/$FORGE_MANIFEST_SIG_RELPATH"
TMP_MANIFEST="$(mktemp)"
cleanup() { rm -f "$TMP_MANIFEST"; }
trap cleanup EXIT

if ! forge_build_manifest "$ROOT" > "$TMP_MANIFEST"; then
  echo "forge-sign-payload: manifest build failed (fail-closed)" >&2; exit 4
fi
if [ ! -s "$TMP_MANIFEST" ]; then
  echo "forge-sign-payload: empty manifest (fail-closed)" >&2; exit 4
fi
mkdir -p "$(dirname "$MANIFEST")"
cp "$TMP_MANIFEST" "$MANIFEST" || { echo "forge-sign-payload: cannot write manifest" >&2; exit 4; }

TRUSTED="tier=$TIER version=$VERSION"
abort_unsigned() {
  rm -f "$MANIFEST" "$SIG"
  echo "forge-sign-payload: signing FAILED — removed partial manifest/sig (fail-closed)" >&2
  exit 5
}

if [ -n "$PWFILE" ]; then
  minisign -S -s "$KEY" -m "$MANIFEST" -t "$TRUSTED" -x "$SIG" < "$PWFILE" || abort_unsigned
else
  # Passwordless keys (generated with `minisign -G -W`) do not prompt. A feed of an empty
  # line is harmless if a prompt ever appears.
  printf '\n' | minisign -S -s "$KEY" -m "$MANIFEST" -t "$TRUSTED" -x "$SIG" || abort_unsigned
fi

if [ ! -f "$SIG" ]; then abort_unsigned; fi
echo "forge-sign-payload: signed $(wc -l < "$MANIFEST" | tr -d ' ') payload files (tier=$TIER version=$VERSION)"
echo "  manifest:  $MANIFEST"
echo "  signature: $SIG"

#!/usr/bin/env bash
# FORGE plugin — SessionStart integrity verification (Spec 488; upgrades the Spec 463
# DECORATIVE check to a real, fail-closed, signature-verifying gate).
#
# ============================ INTEGRITY POSTURE ============================
# This hook verifies a minisign DETACHED signature over a deterministic payload manifest
# against an EXTERNALLY-ANCHORED public key. The pubkey, version floor, and expected tier
# are read from the anchor (managed-settings.json or a pinned anchor) and NEVER from the
# payload (R5) — so a swapped payload carrying a swapped embedded key still fails.
#
#   - Installed mode  (CLAUDE_PLUGIN_ROOT set): verify; FAIL CLOSED on tamper/mismatch.
#   - Source/dev mode (CLAUDE_PLUGIN_ROOT unset): SKIP verification (warn-only) so the
#     FORGE dev loop is never bricked by an in-progress payload edit (reuses Spec 487
#     resolve-root semantics).
#
# Verifier-missing posture (Spec 488 AC8): a signature MISMATCH fails closed (block); a
# missing minisign BINARY degrades loud (machine-parseable SIGNAL) but does NOT brick —
# permitted only because install.sh hard-enforces minisign at install (R9).
# Offline / no-anchor posture (AC11): an unreachable/absent anchor FAILS CLOSED, no grace.
# ==========================================================================
set -uo pipefail

EXIT_OK=0
EXIT_FAIL=1   # fail-closed block

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()    { echo "[forge:plugin-integrity] $*" >&2; }
# Machine-parseable signal line for monitoring/alerting (CISO/AC8).
signal() { echo "[forge:plugin-integrity] SIGNAL=$1 severity=$2" >&2; }

# ---- Mode detection (Spec 487 resolve-root) ------------------------------------------
# Source/dev mode: CLAUDE_PLUGIN_ROOT unset -> skip verification entirely (AC4).
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  log "source/dev mode (CLAUDE_PLUGIN_ROOT unset) — integrity verification skipped (warn-only)."
  exit $EXIT_OK
fi

ASSET_ROOT="$(printf '%s' "$CLAUDE_PLUGIN_ROOT" | tr '\\' '/')"
MANIFEST_LIB="$ASSET_ROOT/.forge/lib/payload-manifest.sh"
MANIFEST="$ASSET_ROOT/.claude-plugin/payload-manifest.txt"
SIG="$ASSET_ROOT/.claude-plugin/payload-manifest.txt.minisig"

# ---- minisign-missing: loud warn + machine-parseable degrade, NOT brick (AC8) --------
if ! command -v minisign >/dev/null 2>&1; then
  signal "minisign-missing" "degraded"
  log "minisign binary not found — integrity verification DEGRADED. install.sh is expected"
  log "to guarantee minisign (R9); continuing (degrade, not brick) per Spec 488 AC8."
  exit $EXIT_OK
fi

# ---- External anchor resolution (R5) — pubkey/floor/tier NEVER from the payload ------
# Priority: FORGE_PLUGIN_ANCHOR (explicit anchor dir/file) > managed-settings.json.
ANCHOR_PUBKEY="" ANCHOR_FLOOR="" ANCHOR_TIER="" ANCHOR_SRC=""

# Refuse an anchor that lives inside the payload (an attacker-controlled in-payload key
# must never become the trust root).
anchor_is_external() {
  case "$1" in
    "$ASSET_ROOT"|"$ASSET_ROOT"/*) return 1 ;;
    *) return 0 ;;
  esac
}

if [ -n "${FORGE_PLUGIN_ANCHOR:-}" ]; then
  if ! anchor_is_external "$FORGE_PLUGIN_ANCHOR"; then
    log "anchor inside payload ($FORGE_PLUGIN_ANCHOR) — refused (R5: anchor must be external). FAIL CLOSED."
    exit $EXIT_FAIL
  fi
  if [ -d "$FORGE_PLUGIN_ANCHOR" ]; then
    [ -f "$FORGE_PLUGIN_ANCHOR/pubkey" ]        && ANCHOR_PUBKEY="$(tail -1 "$FORGE_PLUGIN_ANCHOR/pubkey")"
    [ -f "$FORGE_PLUGIN_ANCHOR/version-floor" ] && ANCHOR_FLOOR="$(tr -d ' \t\r\n' < "$FORGE_PLUGIN_ANCHOR/version-floor")"
    [ -f "$FORGE_PLUGIN_ANCHOR/tier" ]          && ANCHOR_TIER="$(tr -d ' \t\r\n' < "$FORGE_PLUGIN_ANCHOR/tier")"
    ANCHOR_SRC="anchor-dir:$FORGE_PLUGIN_ANCHOR"
  elif [ -f "$FORGE_PLUGIN_ANCHOR" ]; then
    ANCHOR_PUBKEY="$(tail -1 "$FORGE_PLUGIN_ANCHOR")"
    ANCHOR_SRC="anchor-file:$FORGE_PLUGIN_ANCHOR"
  fi
else
  MANAGED=""
  for m in "${FORGE_MANAGED_SETTINGS:-}" "/etc/forge/managed-settings.json" "$HOME/.forge/managed-settings.json"; do
    [ -n "$m" ] && [ -f "$m" ] && { MANAGED="$m"; break; }
  done
  if [ -n "$MANAGED" ]; then
    ANCHOR_PUBKEY="$(grep -oE '"pubkey"[[:space:]]*:[[:space:]]*"[^"]*"' "$MANAGED" | head -1 | sed -E 's/.*"pubkey"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
    ANCHOR_FLOOR="$(grep -oE '"version_floor"[[:space:]]*:[[:space:]]*"[^"]*"' "$MANAGED" | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/')"
    ANCHOR_TIER="$(grep -oE '"tier"[[:space:]]*:[[:space:]]*"[^"]*"' "$MANAGED" | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/')"
    ANCHOR_SRC="managed-settings:$MANAGED"
  fi
fi

# Offline / no-anchor posture: anchor unreachable/absent -> FAIL CLOSED, no grace (AC11).
if [ -z "$ANCHOR_PUBKEY" ]; then
  log "external anchor (pubkey) unresolved — FAIL CLOSED (no grace window). Provide the"
  log "anchor via managed-settings.json or FORGE_PLUGIN_ANCHOR."
  exit $EXIT_FAIL
fi

# ---- Manifest + signature presence ---------------------------------------------------
if [ ! -f "$MANIFEST" ] || [ ! -f "$SIG" ]; then
  log "signed manifest or signature missing under payload — FAIL CLOSED."
  exit $EXIT_FAIL
fi

# ---- LF-canonicalize the manifest for verification (Spec 518 — eol-agnostic) ----------
# Distribution channels that bypass .gitattributes (zip/tarball release assets, Copier
# renders without .git, pre-Spec-517 clones under core.autocrlf) can materialize the
# manifest with CRLF endings while the signature was made over LF bytes. Strip CR into a
# TEMP copy — the same canonicalization the manifest algorithm applies to file content
# (payload-manifest.sh R3) — and verify against that canonical copy, so verification is
# line-ending-agnostic. The on-disk manifest is NEVER mutated; the DETACHED SIGNATURE
# (.minisig) is BINARY and NEVER normalized. This normalizes line endings ONLY: the
# signature check and the recompute-diff below are unchanged in presence and strictness —
# a tampered manifest cannot hide behind CR stripping, because verification requires the
# canonical bytes to be byte-identical to the signed bytes.
NORM_MANIFEST="$(mktemp)" || { log "temp file creation failed — FAIL CLOSED."; exit $EXIT_FAIL; }
RECOMPUTED="$(mktemp)" || { rm -f "$NORM_MANIFEST"; log "temp file creation failed — FAIL CLOSED."; exit $EXIT_FAIL; }
trap 'rm -f "$NORM_MANIFEST" "$RECOMPUTED"' EXIT
if ! tr -d '\r' < "$MANIFEST" > "$NORM_MANIFEST"; then
  log "manifest LF-normalization failed — FAIL CLOSED."
  exit $EXIT_FAIL
fi

# ---- Verify the signature against the ANCHORED pubkey (R5/AC1/AC2/AC5/AC6) ------------
VERIFY_OUT=""
if ! VERIFY_OUT="$(minisign -V -P "$ANCHOR_PUBKEY" -m "$NORM_MANIFEST" -x "$SIG" 2>&1)"; then
  log "signature verification FAILED against anchored pubkey ($ANCHOR_SRC) — FAIL CLOSED."
  printf '%s\n' "$VERIFY_OUT" | sed 's/^/[forge:plugin-integrity]   /' >&2
  exit $EXIT_FAIL
fi

# ---- Recompute the manifest from disk and diff (proves files match the signed manifest)
if [ ! -f "$MANIFEST_LIB" ]; then log "manifest lib missing — FAIL CLOSED."; exit $EXIT_FAIL; fi
# shellcheck source=/dev/null
. "$MANIFEST_LIB" || { log "cannot load manifest lib — FAIL CLOSED."; exit $EXIT_FAIL; }
if ! forge_build_manifest "$ASSET_ROOT" > "$RECOMPUTED" 2>/dev/null; then
  log "manifest recompute failed — FAIL CLOSED."; exit $EXIT_FAIL
fi
# Diff against the SAME canonical (CR-stripped) copy the signature was verified over —
# forge_build_manifest emits LF by construction, so a CRLF on-disk manifest must not
# false-tamper here (Spec 518). Any CONTENT mismatch still FAILS CLOSED.
if ! diff "$RECOMPUTED" "$NORM_MANIFEST" >/dev/null 2>&1; then
  log "payload does not match the signed manifest (tamper detected) — FAIL CLOSED."
  exit $EXIT_FAIL
fi

# ---- Downgrade / tier protection — floor + tier from the EXTERNAL anchor (R10/AC7/AC14)
TC_LINE="$(printf '%s\n' "$VERIFY_OUT" | grep -iE 'trusted comment' | head -1)"
SIG_TIER="$(printf '%s' "$TC_LINE" | sed -nE 's/.*tier=([^ ]+).*/\1/p')"
SIG_VERSION="$(printf '%s' "$TC_LINE" | sed -nE 's/.*version=([^ ]+).*/\1/p')"

if [ -n "$ANCHOR_TIER" ] && [ "$SIG_TIER" != "$ANCHOR_TIER" ]; then
  log "tier mismatch (payload tier=$SIG_TIER, anchor expects $ANCHOR_TIER) — FAIL CLOSED."
  exit $EXIT_FAIL
fi
if [ -n "$ANCHOR_FLOOR" ] && [ -n "$SIG_VERSION" ]; then
  lowest="$(printf '%s\n%s\n' "$ANCHOR_FLOOR" "$SIG_VERSION" | LC_ALL=C sort -V | head -1)"
  if [ "$SIG_VERSION" != "$ANCHOR_FLOOR" ] && [ "$lowest" = "$SIG_VERSION" ]; then
    log "downgrade rejected (payload version=$SIG_VERSION < anchored floor=$ANCHOR_FLOOR) — FAIL CLOSED."
    exit $EXIT_FAIL
  fi
fi

log "plugin payload integrity verified — signed, tier=$SIG_TIER version=$SIG_VERSION, anchor=$ANCHOR_SRC. PASS."
exit $EXIT_OK

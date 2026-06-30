#!/usr/bin/env bash
# FORGE plugin — SessionStart integrity self-check (Spec 463, P3=B).
#
# ============================ HONESTY STATEMENT ============================
# This check is DECORATIVE under unsigned slice 1. The checksum it verifies
# lives in (or is derived alongside) the same payload it is verifying — under
# P2=A unsigned (no external root-of-trust), an attacker who controls the
# payload also controls the verifier. It detects ACCIDENTAL corruption
# (a truncated file, a botched local edit) but CANNOT withstand an attacker
# who controls the payload. It becomes architectural only when signing lands
# in a follow-up spec (CISO R1 critical + CTO R1 "decorative, not architectural").
# ==========================================================================
#
# Failure mode: warn-and-continue (P3=B). The hook NEVER blocks a session.
# It prints a warning to stderr and exits 0 so the operator is never locked
# out by an accidental local edit.
set -uo pipefail

# Resolve the plugin root robustly. CLAUDE_PLUGIN_ROOT is set by Claude Code
# when the hook fires; fall back to deriving it from this script's location so
# the hook is runnable standalone (and testable).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -z "$PLUGIN_ROOT" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # .claude-plugin/hooks/ -> repo root is two levels up.
  PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi

MANIFEST="${PLUGIN_ROOT}/.claude-plugin/plugin.json"

# The literal honesty statement — load-bearing, verified verbatim by AC6.
HONESTY_STATEMENT="plugin integrity check is DECORATIVE under unsigned slice 1 — accidental corruption may be detected but compromised payloads cannot be"

emit_warning() {
  local reason="$1"
  {
    echo "[forge:plugin-integrity] WARNING: ${reason}"
    echo "[forge:plugin-integrity] ${HONESTY_STATEMENT} detected. Continuing (warn-and-continue, P3=B)."
    echo "[forge:plugin-integrity] Signing/verification is deferred to a follow-up spec; see docs/process-kit/plugin-architecture.md."
  } >&2
}

# Pick a checksum tool that exists on this platform.
checksum_tool() {
  if command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
  else
    echo ""
  fi
}

TOOL="$(checksum_tool)"
if [[ -z "$TOOL" ]]; then
  # No checksum tool — nothing to verify against. Decorative check is a no-op.
  exit 0
fi

if [[ ! -f "$MANIFEST" ]]; then
  emit_warning "plugin manifest missing at ${MANIFEST}"
  exit 0
fi

# DECORATIVE integrity computation: hash the manifest itself as a stand-in for a
# payload digest. The expected value lives in the optional sidecar
# .claude-plugin/hooks/integrity.sha256 (part of the same payload — self-referential
# by construction; see HONESTY STATEMENT). If the sidecar is absent, we skip the
# comparison silently (slice 1 ships no pinned checksum; the sidecar is a hook for
# the future signed slice and a test affordance).
SIDECAR="${PLUGIN_ROOT}/.claude-plugin/hooks/integrity.sha256"
if [[ ! -f "$SIDECAR" ]]; then
  exit 0
fi

EXPECTED="$(tr -d ' \t\r\n' < "$SIDECAR" || true)"
ACTUAL="$($TOOL "$MANIFEST" 2>/dev/null | awk '{print $1}' || true)"

if [[ -z "$ACTUAL" ]]; then
  emit_warning "could not compute payload checksum"
  exit 0
fi

if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  emit_warning "payload checksum mismatch (expected ${EXPECTED:0:12}…, got ${ACTUAL:0:12}…)"
  exit 0
fi

# Match — nothing to report. Still decorative; a matching checksum proves nothing
# under an attacker who controls both payload and sidecar.
exit 0

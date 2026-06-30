#!/usr/bin/env bash
# FORGE telemetry helper — durable security-gate verdict ledger (Spec 495).
#
# Records security-gate PASS *and* FAIL verdicts to a TRACKED, durable ledger so
# the verdict trail survives a clean clone (the "un-loseable capture" objective;
# closes the Spec 258 silent-lapse class). Mirrors the score-audit.sh primitives
# (Spec 368) — atomic-append, shell-derived timestamps, advisory exit-0 — rather
# than events.py, whose append is not advisory-safe (DA Step-2b finding).
#
# Usage:
#   telemetry.sh record-security-gate <gate_name> <PASS|FAIL> <exit_code> [sha]
#
# The verdict is derived from the gate's OWN exit code by the caller — never from
# an operator-writable field (CISO trust-boundary). This ledger is TELEMETRY ONLY:
# it is append-by-convention, NOT tamper-evident, and MUST NOT be promoted to an
# authority for any "approved/verified" claim without a hash-chain/signing scheme.
# See docs/process-kit/telemetry-capture-guide.md.
#
# Ledger path: $FORGE_SECURITY_GATE_FILE (default: .forge/state/security-gate.jsonl).
# This helper is advisory; failures emit WARN to stderr but always exit 0.

SECURITY_GATE_FILE="${FORGE_SECURITY_GATE_FILE:-.forge/state/security-gate.jsonl}"
ATOMIC_BOUND_BYTES=4000

_iso_ts_utc() { date -u +%FT%TZ; }
_git_sha_or_unknown() { git rev-parse HEAD 2>/dev/null || printf 'unknown'; }

_ensure_log_dir() {
  local dir
  dir="$(dirname "$SECURITY_GATE_FILE")"
  if ! mkdir -p "$dir" 2>/dev/null; then return 1; fi
  if [ ! -f "$SECURITY_GATE_FILE" ]; then
    if ! ( : > "$SECURITY_GATE_FILE" ) 2>/dev/null; then return 1; fi
    chmod 0644 "$SECURITY_GATE_FILE" 2>/dev/null || true
  fi
  [ -w "$SECURITY_GATE_FILE" ] || return 1
  return 0
}

_atomic_append() {
  local record="$1"
  if [ "${#record}" -ge "$ATOMIC_BOUND_BYTES" ]; then
    printf 'WARN: telemetry record exceeds atomic-append bound; skipping\n' >&2
    return 0
  fi
  if ! printf '%s\n' "$record" >> "$SECURITY_GATE_FILE" 2>/dev/null; then
    printf 'WARN: security-gate append failed (advisory; caller continues)\n' >&2
    return 0
  fi
  return 0
}

_json_escape() {
  local s="${1-}"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

cmd_record_security_gate() {
  # <gate_name> <PASS|FAIL> <exit_code> [sha]
  if [ "$#" -lt 3 ]; then
    printf 'WARN: record-security-gate needs <gate_name> <PASS|FAIL> <exit_code> [sha] (advisory; skipping)\n' >&2
    return 0
  fi
  local gate="$1" result="$2" exit_code="$3" sha="${4:-}"
  case "$result" in
    PASS|FAIL) : ;;
    *) printf 'WARN: result must be PASS or FAIL (got: %s); skipping\n' "$result" >&2; return 0 ;;
  esac
  [ -n "$sha" ] || sha="$(_git_sha_or_unknown)"
  if ! _ensure_log_dir; then
    printf 'WARN: security-gate ledger not writable (advisory; caller continues)\n' >&2
    return 0
  fi
  local rec
  rec=$(printf '{"timestamp":"%s","gate":"%s","result":"%s","exit_code":"%s","sha":"%s"}' \
    "$(_iso_ts_utc)" "$(_json_escape "$gate")" "$result" "$(_json_escape "$exit_code")" "$(_json_escape "$sha")")
  _atomic_append "$rec"
  return 0
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    record-security-gate) cmd_record_security_gate "$@" ;;
    *)
      printf 'WARN: unknown telemetry subcommand: %s (advisory; no-op)\n' "$cmd" >&2
      ;;
  esac
  return 0
}

main "$@"
exit 0

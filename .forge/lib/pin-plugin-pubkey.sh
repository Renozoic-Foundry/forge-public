#!/usr/bin/env bash
# FORGE plugin pubkey pinning + minisign enforcement (Spec 488).
#
# Sourced by install.sh to (a) HARD-ENFORCE the minisign binary at install time (R9 — the
# precondition that lets the SessionStart hook degrade rather than brick on a later-missing
# binary, AC8), and (b) pin the forge-public tier pubkey ONLY after verifying it against an
# OUT-OF-BAND checksum (R5/R9/AC12) — a raw TLS-TOFU fetch from a GitHub raw URL is not
# trusted on its own (the DA/CTO/CISO consensus weakest-link finding).
set -uo pipefail

# Post-install integrity check (R9). Non-zero if minisign is absent so install.sh can FAIL
# rather than silently leave an unenforceable plugin install.
forge_enforce_minisign() {
  if command -v minisign >/dev/null 2>&1; then
    return 0
  fi
  echo "forge: minisign is REQUIRED but was not found after install (R9 hard-enforce)." >&2
  echo "      Install it (e.g. 'scoop install minisign' / 'brew install minisign') and re-run." >&2
  return 1
}

forge_pubkey_checksum_tool() {
  if command -v sha256sum >/dev/null 2>&1; then echo "sha256sum"
  elif command -v shasum >/dev/null 2>&1; then echo "shasum -a 256"
  else echo ""; fi
}

# forge_pin_pubkey <fetched-pubkey-file> <expected-sha256> <dest-anchor-file>
# Pins the fetched pubkey to the local anchor ONLY if its out-of-band checksum matches.
# Refuses to pin (non-zero) on mismatch or missing checksum (R5/AC12).
forge_pin_pubkey() {
  local fetched="$1" expected="$2" dest="$3"
  local tool; tool="$(forge_pubkey_checksum_tool)"
  if [ -z "$tool" ]; then echo "forge_pin_pubkey: no sha256 tool available" >&2; return 2; fi
  if [ ! -f "$fetched" ]; then echo "forge_pin_pubkey: fetched pubkey not found: $fetched" >&2; return 2; fi
  if [ -z "$expected" ]; then
    echo "forge_pin_pubkey: no out-of-band checksum supplied — refusing to pin (R5: TLS-TOFU alone is insufficient)." >&2
    return 2
  fi
  local actual
  actual="$(tr -d '\r' < "$fetched" | $tool | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "forge_pin_pubkey: out-of-band checksum MISMATCH (expected ${expected:0:12}…, got ${actual:0:12}…) — refusing to pin (R5/AC12)." >&2
    return 1
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$fetched" "$dest" || { echo "forge_pin_pubkey: cannot write anchor: $dest" >&2; return 2; }
  echo "forge_pin_pubkey: pinned out-of-band-verified pubkey -> $dest"
  return 0
}

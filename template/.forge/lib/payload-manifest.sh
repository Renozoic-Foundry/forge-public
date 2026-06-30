#!/usr/bin/env bash
# FORGE plugin payload manifest builder (Spec 488).
#
# Produces a DETERMINISTIC, line-ending-canonical manifest of the plugin payload:
#   one "<sha256>  <relpath>" line per payload file, LC_ALL=C sorted by relpath.
#
# CRLF canonicalization (R3): each file's bytes are LF-normalized (CR stripped) before
# hashing, so a payload checked out with CRLF on Windows produces a byte-identical
# manifest to one checked out with LF. The payload is all text (.sh/.md/.json/.ps1/...).
#
# This library is the SINGLE source of the manifest algorithm, shared by:
#   - forge-sign-payload.sh        (sign side — release step)
#   - session-start-integrity.sh   (verify side — SessionStart hook)
# so the two can never drift (CTO consensus: clean shared boundary).
set -uo pipefail

# Payload roots relative to the asset root (the plugin payload set per Spec 487).
FORGE_PAYLOAD_DIRS=(
  ".claude/commands"
  ".claude/agents"
  ".claude/skills"
  ".claude-plugin"
  ".forge/bin"
  ".forge/lib"
  ".forge/templates"
  ".forge/modules"
  ".forge/adapters"
)

# Payload paths excluded from the public sync copy (Spec 506). SINGLE SOURCE — consumed by
# all three scripts/sync-to-public.sh copy paths (cp/payload-mirror blocks, the rsync
# --exclude flags, and the Python-fallback exclusion set), projected mechanically rather than
# hand-duplicated into three syntaxes. These trees carry PII-token test fixtures
# (.forge/bin/tests, .forge/bin/autonomy-test) and untracked bytecode (__pycache__/*.pyc)
# that must not ship to forge-public. Each entry is a basename/glob matched at any depth.
#
# NOTE (Spec 506 ↔ 508 boundary): forge_build_manifest below deliberately does NOT consume
# PAYLOAD_EXCLUDE yet — wiring the exclusions into the signed-manifest builder (so the manifest
# excludes these at the algorithm level even when run against the source/template tree) is
# Spec 508's scope. 506 applies PAYLOAD_EXCLUDE on the sync side only.
PAYLOAD_EXCLUDE=(
  "tests"
  "autonomy-test"
  "__pycache__"
  "*.pyc"
)

# The manifest + its signature are OUTPUTS, never hashed as inputs (would self-reference).
FORGE_MANIFEST_RELPATH=".claude-plugin/payload-manifest.txt"
FORGE_MANIFEST_SIG_RELPATH=".claude-plugin/payload-manifest.txt.minisig"

forge_manifest_checksum_tool() {
  if command -v sha256sum >/dev/null 2>&1; then echo "sha256sum"
  elif command -v shasum >/dev/null 2>&1; then echo "shasum -a 256"
  else echo ""; fi
}

# LF-normalized sha256 of a single file ($1) using the resolved tool ($2).
# `tr -d '\r'` collapses CRLF->LF so CRLF and LF checkouts hash identically (R3).
forge_manifest_file_hash() {
  local file="$1" tool="$2"
  tr -d '\r' < "$file" | $tool | awk '{print $1}'
}

# Build the manifest for the payload rooted at $1 (default: FORGE_ASSET_ROOT or cwd).
# Prints the manifest to stdout. Returns non-zero on error (fail-closed for callers).
forge_build_manifest() {
  local root="${1:-${FORGE_ASSET_ROOT:-$PWD}}"
  root="$(printf '%s' "$root" | tr '\\' '/')"
  local tool; tool="$(forge_manifest_checksum_tool)"
  if [ -z "$tool" ]; then echo "payload-manifest: no sha256 tool available" >&2; return 1; fi
  if [ ! -d "$root" ]; then echo "payload-manifest: root not found: $root" >&2; return 1; fi

  local d f rel; local files=()
  for d in "${FORGE_PAYLOAD_DIRS[@]}"; do
    [ -d "$root/$d" ] || continue
    while IFS= read -r f; do files+=("$f"); done < <(find "$root/$d" -type f 2>/dev/null)
  done
  if [ "${#files[@]}" -eq 0 ]; then echo "payload-manifest: no payload files under $root" >&2; return 1; fi

  {
    for f in "${files[@]}"; do
      rel="${f#"$root"/}"
      [ "$rel" = "$FORGE_MANIFEST_RELPATH" ] && continue
      [ "$rel" = "$FORGE_MANIFEST_SIG_RELPATH" ] && continue
      printf '%s  %s\n' "$(forge_manifest_file_hash "$f" "$tool")" "$rel"
    done
  } | LC_ALL=C sort -k2
}

# Executed directly (not sourced): build + print the manifest for the requested root.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  forge_build_manifest "${1:-}"
fi

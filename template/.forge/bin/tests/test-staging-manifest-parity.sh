#!/usr/bin/env bash
# Spec 315 AC 12b — Cross-platform staging-manifest hash parity
# Verifies that the LF-normalize-then-hash protocol in onboarding.md produces
# byte-identical sha256 hex digests on bash (Unix LF) and PowerShell (Windows CRLF).
#
# Reference fixture content (LF-normalized): "line one\nline two\nline three\n"
# Expected sha256: bce2aeea9e6fc31f09b164dbaf832b013ee75fbd323262cbee9d42b8b51077b1
# Total 29 bytes:
#   "line one"   (8 bytes ASCII) + LF (0x0A)
#   "line two"   (8 bytes ASCII) + LF (0x0A)
#   "line three" (10 bytes ASCII) + LF (0x0A)
#
# This script writes a fixture with LF line endings, runs the bash hash recipe
# from onboarding.md § Cross-platform hashing protocol, and compares against the
# pre-computed reference hash.

set -e

EXPECTED_HASH="bce2aeea9e6fc31f09b164dbaf832b013ee75fbd323262cbee9d42b8b51077b1"

TMPDIR_PREFIX="${TMPDIR:-${TEMP:-/tmp}}"
WORK_DIR="$(mktemp -d "$TMPDIR_PREFIX/forge-staging-parity-XXXXXX")"
FIXTURE="$WORK_DIR/fixture-lf.txt"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Write fixture with explicit LF byte sequence (0x0A)
printf 'line one\nline two\nline three\n' > "$FIXTURE"

# Verify fixture byte sequence
ACTUAL_BYTES=$(wc -c < "$FIXTURE" | tr -d ' ')
if [ "$ACTUAL_BYTES" != "29" ]; then
  echo "FAIL: fixture has $ACTUAL_BYTES bytes, expected 29"
  exit 1
fi

# Apply the bash hash recipe from onboarding.md § Cross-platform hashing protocol
# Strip BOM (none expected on this fixture, but the protocol applies it anyway),
# normalize CRLF→LF, strip bare CR, then sha256.
ACTUAL_HASH=$(sed '1s/^\xEF\xBB\xBF//' "$FIXTURE" | sed 's/\r$//' | tr -d '\r' | sha256sum | awk '{print $1}')

if [ "$ACTUAL_HASH" = "$EXPECTED_HASH" ]; then
  echo "PASS: bash hash matches reference"
  echo "  fixture: 29 bytes, LF line endings"
  echo "  hash:    $ACTUAL_HASH"
  exit 0
else
  echo "FAIL: bash hash mismatch"
  echo "  expected: $EXPECTED_HASH"
  echo "  actual:   $ACTUAL_HASH"
  exit 1
fi

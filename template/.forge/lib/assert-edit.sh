#!/usr/bin/env bash
# FORGE assert-edit — verify-after-scripted-edit helpers (Spec 483).
# Sourceable: pure functions, no main execution.
#
# Closes the silent-no-op-edit failure mode: a scripted edit (bash `sed -i`,
# `python -c "...open(...,'w')..."`, heredoc rewrite) that matched NOTHING but
# reported success. Unlike the Edit tool (which errors on no-match), scripted
# edits in command flows have no gate that verifies the edit actually changed
# the target. The author believes the edit applied; it didn't; the defect
# surfaces downstream (SIG-451-EA-425 recurred 4x; SIG-451-B / SIG-460-B).
#
# Convention (capture-before, assert-after):
#     before="$(assert_edit_sha "$file")"   # capture baseline
#     sed -i 's/old/new/' "$file"           # the scripted edit
#     assert_changed "$file" "$before"      # FAIL if the edit was a no-op
#     assert_contains "$file" "new"         # FAIL if the expected string is absent
#
# Public functions:
#   assert_edit_sha <file>
#       — print a content hash of <file> (sha256, falls back to cksum). Capture
#         this BEFORE a scripted edit; pass it to assert_changed afterward.
#   assert_changed <file> <before_sha>
#       — exit 0 silently if <file>'s current hash differs from <before_sha>;
#         else emit `ASSERT-EDIT FAIL: <file> — unchanged (...)` to stderr and
#         exit non-zero. Catches the EA-425 silent-no-op class.
#   assert_contains <file> <expected_string>
#       — exit 0 silently if <expected_string> is present in <file>; else emit
#         `ASSERT-EDIT FAIL: <file> — missing expected string ...` to stderr and
#         exit non-zero. Catches the SIG-460-B verbatim-string class.
#
# Advisory by default: these return non-zero, but whether a FAIL halts the
# surrounding flow is the caller's decision (`assert_changed ... || exit 1`
# to make it fatal; bare call under `set -e` is already fatal).
#
# See docs/process-kit/scripted-edit-conventions.md.

# Print a content hash of a file. Used to capture a pre-edit baseline.
# Falls back across sha256sum -> shasum -> cksum so it works on minimal hosts.
assert_edit_sha() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    # A missing file hashes to a sentinel so a create-then-assert still works.
    printf '%s\n' "__assert_edit_absent__"
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    cksum "$file" | awk '{print $1"-"$2}'
  fi
}

# assert_changed <file> <before_sha>
# Non-zero + FAIL line if the file is unchanged vs the captured baseline.
assert_changed() {
  local file="$1" before="${2:-}"
  if [[ -z "$before" ]]; then
    printf 'ASSERT-EDIT FAIL: %s — no baseline sha passed to assert_changed (capture with assert_edit_sha BEFORE the edit)\n' "$file" >&2
    return 2
  fi
  local after
  after="$(assert_edit_sha "$file")"
  if [[ "$after" == "$before" ]]; then
    printf 'ASSERT-EDIT FAIL: %s — unchanged (scripted edit was a silent no-op; the pattern matched nothing)\n' "$file" >&2
    return 1
  fi
  return 0
}

# assert_contains <file> <expected_string>
# Non-zero + FAIL line if the expected (literal) string is absent post-edit.
assert_contains() {
  local file="$1" expected="${2:-}"
  if [[ ! -f "$file" ]]; then
    printf 'ASSERT-EDIT FAIL: %s — file does not exist (expected to contain: %s)\n' "$file" "$expected" >&2
    return 1
  fi
  if [[ -z "$expected" ]]; then
    printf 'ASSERT-EDIT FAIL: %s — no expected string passed to assert_contains\n' "$file" >&2
    return 2
  fi
  # -F fixed-string (verbatim, no regex), -q quiet.
  if grep -Fq -- "$expected" "$file"; then
    return 0
  fi
  printf 'ASSERT-EDIT FAIL: %s — missing expected string after edit: %s\n' "$file" "$expected" >&2
  return 1
}

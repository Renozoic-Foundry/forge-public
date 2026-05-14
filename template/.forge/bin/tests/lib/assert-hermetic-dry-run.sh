#!/usr/bin/env bash
# assert-hermetic-dry-run.sh — Spec 404
#
# Asserts that running a command does not mutate the contents of a staging
# directory. Used to verify that --dry-run flags on FORGE-shipped scripts
# leave their target dir byte-identical before/after.
#
# Calling convention:
#   source .forge/bin/tests/lib/assert-hermetic-dry-run.sh
#   assert_hermetic_dry_run "<staging-dir>" -- <command> [args...]
#
# Returns:
#   0  if the staging-dir manifest is unchanged after the command runs
#   1  if the manifest changed (non-hermetic command)
#   2  if invocation was malformed (caller error)
#
# Byte-identity definition: SHA-256 over a sorted manifest of
#   "<sha256-of-file>  <relative-path>"
# for every file under the staging dir. Excludes mtime, ownership, empty dirs.

# Compute a manifest hash for a directory.
# Stdout: 64-char lowercase hex. Empty dir → SHA-256 of empty string.
forge_hermetic_manifest() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        printf 'ERROR: not a directory: %s\n' "$dir" >&2
        return 2
    fi
    # find -> per-file sha256 + relative path, sort, then hash the whole stream
    (
        cd "$dir" || return 2
        # -L: follow symlinks; -type f: only files; -print0/xargs-0: handle spaces
        # On empty dirs find prints nothing → sha256sum hashes empty stream.
        find -L . -type f -print0 2>/dev/null \
            | xargs -0 -I{} sha256sum -- "{}" 2>/dev/null \
            | LC_ALL=C sort
    ) | sha256sum | awk '{print $1}'
}

assert_hermetic_dry_run() {
    if [ "$#" -lt 3 ]; then
        printf 'usage: assert_hermetic_dry_run <dir> -- <command> [args...]\n' >&2
        return 2
    fi
    local dir="$1"
    shift
    if [ "$1" != "--" ]; then
        printf 'expected "--" separator after dir, got: %s\n' "$1" >&2
        return 2
    fi
    shift

    local before after
    before=$(forge_hermetic_manifest "$dir") || return 2

    "$@"
    local rc=$?

    after=$(forge_hermetic_manifest "$dir") || return 2

    if [ "$before" != "$after" ]; then
        printf 'NON-HERMETIC: staging dir changed during command run\n' >&2
        printf '  dir:    %s\n' "$dir" >&2
        printf '  before: %s\n' "$before" >&2
        printf '  after:  %s\n' "$after" >&2
        printf '  cmd-rc: %s\n' "$rc" >&2
        return 1
    fi

    return 0
}

#!/usr/bin/env bash
# validate-scripted-edits.sh — advisory verify-after-scripted-edit lint (Spec 483).
#
# Flags EXECUTED in-place rewrites in script files that are NOT paired with a
# verification (an assert_* / Assert-* call or a grep-based post-condition)
# within a small proximity window. Catches the silent-no-op-edit defect class:
# a `sed -i` / python file-rewrite that matched nothing but reported success
# (SIG-451-EA-425, recurred 4x; SIG-460-B verbatim-string class).
#
# SCOPE (R4 — stay low-noise): only literal executed rewrites in
#   .forge/commands/*.md   (rare; command bodies usually describe edits in prose)
#   scripts/**/*.sh
# Command *prose* that merely describes an edit is not an executed rewrite; the
# patterns below match the executable forms (`sed -i ...`, python open-for-write).
#
# MODE: advisory at first ship — WARN to stderr, ALWAYS exit 0. Flip to strict
# (exit non-zero on findings) later per operator decision via --strict.
#
# Usage: scripts/validate-scripted-edits.sh [--strict] [--verbose]
#
# PowerShell note: this lint is bash-side only (it scans .sh + command bodies).
# The runtime helper has full .ps1 parity (.forge/lib/assert-edit.ps1); the lint
# itself is not mirrored because the surfaces it scans are bash/markdown.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRICT=false
VERBOSE=false
for arg in "$@"; do
    case "$arg" in
        --strict)  STRICT=true ;;
        --verbose) VERBOSE=true ;;
    esac
done

# Proximity window: lines after (and before, to accept a pre-edit guard) the
# rewrite that we scan for a verification token.
WINDOW=4

# Verification tokens that count as a paired post-condition / guard.
VERIFY_RE='assert_changed|assert_contains|assert_edit_sha|Assert-Changed|Assert-Contains|Get-AssertEditSha|grep -[A-Za-z]*q|grep -q|test -|\[\[ '

# Executed in-place rewrite patterns (NOT prose):
#   sed -i ...                          (GNU/BSD in-place)
#   python ... open(<path>, 'w'...)     (file opened for writing)
REWRITE_RE="sed -i|open\\([^)]*['\"]w['\"]"

# Collect target files: scripts/**/*.sh + .forge/commands/*.md
mapfile -t files < <(
    { find "$REPO_ROOT/scripts" -name '*.sh' -type f 2>/dev/null
      find "$REPO_ROOT/.forge/commands" -name '*.md' -type f 2>/dev/null
    } | sort
)

findings=0
details=""

for file in "${files[@]}"; do
    [[ -f "$file" ]] || continue
    relative="${file#"$REPO_ROOT"/}"
    # This lint's own helper/doc/test must not flag themselves (definitional).
    case "$relative" in
        scripts/validate-scripted-edits.sh) continue ;;
        .forge/bin/tests/*) continue ;;
    esac

    # Find rewrite lines (skip comment lines).
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        lineno="${match%%:*}"
        content="${match#*:}"
        # Skip comment-only lines (executed rewrites are not comments).
        [[ "$content" =~ ^[[:space:]]*# ]] && continue

        # Scan WINDOW lines before and after for a verification token.
        start=$(( lineno > WINDOW ? lineno - WINDOW : 1 ))
        end=$(( lineno + WINDOW ))
        context="$(sed -n "${start},${end}p" "$file")"
        if echo "$context" | grep -Eq "$VERIFY_RE"; then
            if $VERBOSE; then
                echo "OK:   $relative:$lineno — rewrite paired with verification"
            fi
            continue
        fi

        details+="  WARN: $relative:$lineno — scripted in-place rewrite without a paired verification (assert_changed/assert_contains or grep post-condition within ${WINDOW} lines). See docs/process-kit/scripted-edit-conventions.md"$'\n'
        (( findings++ )) || true
    done < <(grep -nE "$REWRITE_RE" "$file" || true)
done

echo "=== verify-after-scripted-edit lint (Spec 483, advisory) ==="
echo "Scanned ${#files[@]} files (scripts/**/*.sh + .forge/commands/*.md)."
echo "Found $findings unverified scripted rewrite(s)."

if [[ $findings -gt 0 ]]; then
    echo ""
    printf '%s' "$details"
    echo ""
    if $STRICT; then
        echo "STRICT mode: failing on findings."
        exit 1
    fi
    echo "Advisory mode: not failing (exit 0). Pair each rewrite with an assert_* / grep post-condition,"
    echo "or run with --strict to enforce."
fi

exit 0

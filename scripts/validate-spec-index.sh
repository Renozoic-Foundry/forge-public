#!/usr/bin/env bash
# validate-spec-index.sh — Verify docs/specs/README.md matches the filesystem.
# Part of Spec 199 — Ship-Readiness Audit Fixes.
#
# Checks:
#   1. Every .md file in docs/specs/ (excluding special files) has a row in README.md
#   2. Every row in README.md references a file that exists on disk
#   3. No duplicate spec entries in README.md
#
# Usage: scripts/validate-spec-index.sh [--verbose]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPECS_DIR="${REPO_ROOT}/docs/specs"
INDEX_FILE="${SPECS_DIR}/README.md"
VERBOSE=""

for arg in "$@"; do
    case "$arg" in
        --verbose) VERBOSE="1" ;;
    esac
done

if [[ ! -f "$INDEX_FILE" ]]; then
    echo "ERROR: $INDEX_FILE not found"
    exit 1
fi

errors=0

# Regex for extracting filenames from markdown links: [slug](./slug.md)
# Stored in a variable to avoid bash escaping issues with literal parentheses in =~
link_re='\]\(\./([^)]+\.md)\)'

# --- Check 1: Every spec file on disk has an entry in README.md ---
echo "=== Check 1: Spec files on disk have README.md entries ==="
disk_count=0
disk_missing=0

for spec_file in "$SPECS_DIR"/*.md; do
    [[ -e "$spec_file" ]] || continue
    basename="$(basename "$spec_file")"

    # Skip special files
    case "$basename" in
        _template*.md|README.md|CHANGELOG.md) continue ;;
    esac

    (( disk_count++ )) || true
    stem="${basename%.md}"

    if grep -q "\[${stem}\]" "$INDEX_FILE"; then
        [[ -n "$VERBOSE" ]] && echo "  OK: $basename has index entry"
    else
        echo "  MISSING from index: $basename"
        (( disk_missing++ )) || true
        (( errors++ )) || true
    fi
done

echo "  $disk_count spec files on disk, $disk_missing missing from index"

# --- Check 2: Every README.md entry references an existing file ---
echo ""
echo "=== Check 2: README.md entries reference existing files ==="
index_count=0
index_orphan=0

while IFS= read -r line; do
    if [[ "$line" =~ $link_re ]]; then
        ref_file="${BASH_REMATCH[1]}"
        (( index_count++ )) || true

        if [[ -f "${SPECS_DIR}/${ref_file}" ]]; then
            [[ -n "$VERBOSE" ]] && echo "  OK: $ref_file exists"
        else
            echo "  ORPHAN entry: $ref_file (file not found)"
            (( index_orphan++ )) || true
            (( errors++ )) || true
        fi
    fi
done < "$INDEX_FILE"

echo "  $index_count entries in index, $index_orphan orphaned"

# --- Check 3: Duplicate entries ---
echo ""
echo "=== Check 3: Duplicate spec entries ==="
dup_count=0

# Extract all spec numbers from index entries
declare -A seen_specs
while IFS= read -r line; do
    if [[ "$line" =~ $link_re ]]; then
        ref_file="${BASH_REMATCH[1]}"
        if [[ -n "${seen_specs[$ref_file]:-}" ]]; then
            echo "  DUPLICATE: $ref_file appears multiple times"
            (( dup_count++ )) || true
            (( errors++ )) || true
        else
            seen_specs["$ref_file"]=1
        fi
    fi
done < "$INDEX_FILE"

if [[ $dup_count -eq 0 ]]; then
    echo "  No duplicates found"
fi

# --- Summary ---
echo ""
echo "---"
if [[ $errors -eq 0 ]]; then
    echo "PASS: Spec index is consistent ($disk_count files, $index_count entries)"
    exit 0
else
    echo "FAIL: $errors error(s) found"
    exit "$errors"
fi

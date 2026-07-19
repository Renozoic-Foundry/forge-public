#!/usr/bin/env bash
# two-list-bypass-detect.sh — Detect a COORDINATED two-list bypass in the AGENTS.md
# drift-detector alias map (Spec 411).
#
# Threat: an action suppressed on BOTH sides of the Spec 330 drift detector —
#   its prose token in `ignore_prose:` (dropped from the prose action-set) AND its
#   block-action name in `ignore_block:` (dropped from the block action-set) — disappears
#   from both sets, so the drift detector computes ZERO drift for it. Drift detection is
#   silently neutralized for that action. Because both sides are suppressed, the existing
#   single-list checks cannot see it; this cross-list check is the only thing that can.
#
# Matching rule (Spec 411 R2 — the heart of the feature): for each `ignore_prose` entry,
# compute its block-action name with the SAME pipeline the drift detector uses for prose
# tokens (apply_alias if the alias map maps the phrase, else slugify). A coordinated bypass
# is flagged when that normalized name is ALSO present in `ignore_block:`. Literal string
# equality between the raw prose phrase and the block name is insufficient
# (`force push` != `git_push_force`) and is NOT the rule.
#
# This detector is the single source of truth; scripts/validate-agents-md-drift.{sh,ps1}
# invoke it. It is NOT suppressible via any ignore-list entry (Spec 411 R6) — it never
# consults the ignore lists to decide whether to run.
#
# Usage: two-list-bypass-detect.sh [--alias-map <file>] [--json] [--help]
# Exit:  0 no coordinated bypass | 1 coordinated bypass found | 2 usage/config error

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEFAULT_ALIAS_MAP="${REPO_ROOT}/scripts/agents-md-action-aliases.yaml"

ALIAS_MAP_FILE=""
JSON_OUTPUT=""

usage() {
    # forge:path-literal-ok (comment/fixture) — heredoc help text below references docs/specs/411-...md
    cat <<'EOF'
two-list-bypass-detect.sh — Spec 411 coordinated two-list bypass detector

Usage: two-list-bypass-detect.sh [--alias-map <file>] [--json] [--help]

Parses the alias map's `aliases:`, `ignore_prose:`, and `ignore_block:` sections. For each
`ignore_prose` entry it computes the block-action name (alias-map lookup, else slugify) and
reports a COORDINATED BYPASS when that name is also present in `ignore_block:` — i.e. the
action is suppressed on both sides and is invisible to the Spec 330 drift detector.

Options:
  --alias-map <file>  Path to the alias map (default scripts/agents-md-action-aliases.yaml).
  --json              Emit a JSON report instead of the GATE line.
  --help              Print this help.

Exit codes:
  0  No coordinated bypass (PASS)
  1  One or more coordinated bypasses found (FAIL)
  2  Usage / config error (alias map missing or unreadable)

# forge:path-literal-ok (docstring/prose — classic-default spelling in help text; Spec 575)
See: docs/specs/411-two-list-bypass-detector.md
EOF
}

while (( "$#" )); do
    case "$1" in
        --help|-h)        usage; exit 0 ;;
        --alias-map)      ALIAS_MAP_FILE="$2"; shift 2 ;;
        --alias-map=*)    ALIAS_MAP_FILE="${1#--alias-map=}"; shift ;;
        --json)           JSON_OUTPUT="1"; shift ;;
        *)                echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

ALIAS_MAP="${ALIAS_MAP_FILE:-$DEFAULT_ALIAS_MAP}"
[[ -f "$ALIAS_MAP" ]] || { echo "ERROR: alias map not found at $ALIAS_MAP" >&2; exit 2; }

# ---- helpers (kept byte-identical to validate-agents-md-drift.sh) ----

unquote() { sed -e "s/^[[:space:]]*'//" -e "s/'[[:space:]]*\$//"; }
trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# Slugify a free-text command token into a block-style action name. Identical transforms to
# validate-agents-md-drift.sh::slugify so the normalized names match exactly.
slugify() {
    local s="$1"
    s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
    s="${s//--hard/_hard}"
    s="${s//--force/_force}"
    if [[ "$s" =~ ^(.*)[[:space:]]--$ ]]; then
        s="${BASH_REMATCH[1]}_dashes"
    fi
    s="$(printf '%s' "$s" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    s="$(printf '%s' "$s" | sed -e 's/[[:space:]]\+/_/g' -e 's/-/_/g')"
    s="$(printf '%s' "$s" | sed -e 's/_\+/_/g')"
    s="$(printf '%s' "$s" | sed -e 's/^_//' -e 's/_$//')"
    printf '%s' "$s"
}

# ---- alias-map parsing (mirrors validate-agents-md-drift.sh::parse_alias_map) ----

parse_alias_map() {
    ALIAS_KEYS=()
    ALIAS_TARGETS=()
    IGNORE_PROSE=()
    IGNORE_BLOCK=()

    local section="" line stripped key value
    # `|| [[ -n "$line" ]]` processes a final line that lacks a trailing newline — without it the
    # last line is silently dropped, which would MISS a coordinated bypass whose ignore_block entry
    # is the unterminated final line (the exact false-negative this detector exists to prevent).
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "${line// }" ]] && continue
        [[ "${line#"${line%%[![:space:]]*}"}" == \#* ]] && continue
        stripped="$(printf '%s' "$line" | sed -E "s/  #.*$//")"

        if [[ "${stripped:0:1}" != " " ]] && [[ "$stripped" =~ ^([a-z_]+):[[:space:]]*$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$section" == "aliases" ]]; then
            if [[ "$stripped" =~ ^[[:space:]]+\"([^\"]*)\":[[:space:]]*(.*)$ ]] || \
               [[ "$stripped" =~ ^[[:space:]]+\'([^\']*)\':[[:space:]]*(.*)$ ]]; then
                key="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]}"
                value="$(printf '%s' "$value" | unquote | trim)"
                # Empty alias targets are a drift-escape vector; the drift detector rejects them
                # at exit 2. Here we simply skip them (the drift detector remains the authority on
                # alias-map well-formedness); a bypass requires a concrete ignore_block match.
                [[ -z "$value" ]] && continue
                ALIAS_KEYS+=("$key")
                ALIAS_TARGETS+=("$value")
            fi
        elif [[ "$section" == "ignore_prose" ]]; then
            if [[ "$stripped" =~ ^[[:space:]]+-[[:space:]]+\"([^\"]*)\"[[:space:]]*$ ]] || \
               [[ "$stripped" =~ ^[[:space:]]+-[[:space:]]+\'([^\']*)\'[[:space:]]*$ ]]; then
                IGNORE_PROSE+=("${BASH_REMATCH[1]}")
            fi
        elif [[ "$section" == "ignore_block" ]]; then
            if [[ "$stripped" =~ ^[[:space:]]+-[[:space:]]+\"([^\"]*)\"[[:space:]]*$ ]] || \
               [[ "$stripped" =~ ^[[:space:]]+-[[:space:]]+\'([^\']*)\'[[:space:]]*$ ]]; then
                IGNORE_BLOCK+=("${BASH_REMATCH[1]}")
            fi
        fi
    done < "$ALIAS_MAP"
    return 0
}

apply_alias() {
    local phrase="$1" i
    for i in "${!ALIAS_KEYS[@]}"; do
        if [[ "${ALIAS_KEYS[i]}" == "$phrase" ]]; then
            printf '%s' "${ALIAS_TARGETS[i]}"
            return 0
        fi
    done
    return 1
}

# Normalize a prose phrase to its block-action name: alias-first, then slugify (identical to
# validate-agents-md-drift.sh::extract_prose_actions).
normalize_prose() {
    local phrase="$1" normalized
    if normalized="$(apply_alias "$phrase")"; then
        printf '%s' "$normalized"
    else
        slugify "$phrase"
    fi
}

# ---- main ----

parse_alias_map

# Find coordinated bypasses: an ignore_prose entry whose normalized action name is also in
# ignore_block. Parallel arrays hold the surfaced fields for each detected case.
BYPASS_PROSE=()
BYPASS_NORM=()
BYPASS_BLOCK=()

for p in "${IGNORE_PROSE[@]+"${IGNORE_PROSE[@]}"}"; do
    norm="$(normalize_prose "$p")"
    [[ -z "$norm" ]] && continue
    for b in "${IGNORE_BLOCK[@]+"${IGNORE_BLOCK[@]}"}"; do
        if [[ "$norm" == "$b" ]]; then
            BYPASS_PROSE+=("$p")
            BYPASS_NORM+=("$norm")
            BYPASS_BLOCK+=("$b")
            break
        fi
    done
done

PROSE_IGNORE_COUNT=${#IGNORE_PROSE[@]}
BLOCK_IGNORE_COUNT=${#IGNORE_BLOCK[@]}
BYPASS_COUNT=${#BYPASS_PROSE[@]}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
    printf '%s' "$s"
}

if [[ -n "$JSON_OUTPUT" ]]; then
    printf '{'
    printf '"bypass_count":%d,' "$BYPASS_COUNT"
    printf '"prose_ignore_count":%d,' "$PROSE_IGNORE_COUNT"
    printf '"block_ignore_count":%d,' "$BLOCK_IGNORE_COUNT"
    printf '"bypasses":['
    for i in "${!BYPASS_PROSE[@]}"; do
        [[ $i -gt 0 ]] && printf ','
        printf '{"ignore_prose":"%s","normalized":"%s","ignore_block":"%s"}' \
            "$(json_escape "${BYPASS_PROSE[i]}")" \
            "$(json_escape "${BYPASS_NORM[i]}")" \
            "$(json_escape "${BYPASS_BLOCK[i]}")"
    done
    printf ']}\n'
else
    if [[ "$BYPASS_COUNT" -eq 0 ]]; then
        echo "GATE [two-list-bypass]: PASS - no coordinated ignore_prose+ignore_block bypass ($PROSE_IGNORE_COUNT prose-ignores, $BLOCK_IGNORE_COUNT block-ignores checked)"
    else
        echo "GATE [two-list-bypass]: FAIL - $BYPASS_COUNT coordinated bypass(es) detected (an action suppressed on BOTH sides is invisible to drift detection):" >&2
        for i in "${!BYPASS_PROSE[@]}"; do
            echo "  bypass: ignore_prose \"${BYPASS_PROSE[i]}\" -> \"${BYPASS_NORM[i]}\" also in ignore_block (\"${BYPASS_BLOCK[i]}\")" >&2
        done
    fi
fi

[[ "$BYPASS_COUNT" -eq 0 ]] && exit 0 || exit 1

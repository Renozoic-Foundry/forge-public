#!/usr/bin/env bash
# validate-agents-md-drift.sh — Detect drift between AGENTS.md authorization-required-commands
# PROSE bullets and the sentinel-delimited YAML BLOCK that powers the Spec 327 lint gate.
# Part of Spec 330.
#
# The two sides CAN drift independently (operator adds a new bullet without updating the block,
# or vice versa), producing a silent gap. This linter compares the action sets and FAILs when
# either side has an action the other doesn't.
#
# Usage: scripts/validate-agents-md-drift.sh [--mode=advisory|strict] [--input <file>] [--json] [--help]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_AGENTS_MD="${REPO_ROOT}/AGENTS.md"
DEFAULT_ALIAS_MAP="${REPO_ROOT}/scripts/agents-md-action-aliases.yaml"

INPUT_FILE=""
ALIAS_MAP_FILE=""
MODE_OVERRIDE=""
JSON_OUTPUT=""

usage() {
    cat <<'EOF'
validate-agents-md-drift.sh — Spec 330 prose↔YAML drift detector

Usage: scripts/validate-agents-md-drift.sh [--mode=advisory|strict] [--input <file>] [--alias-map <file>] [--json] [--evidence-dir <path>] [--help]

Compares AGENTS.md PROSE bullets in the "### Authorization-required commands" section against
the sentinel-delimited YAML BLOCK ("<!-- forge:auth-rules:start --> ... end -->"). FAILs when
either side has an action the other doesn't.

Options:
  --mode=advisory       Emit WARN, exit 0 (default — first-run baseline tolerance per Spec 327 pattern)
  --mode=strict         Emit FAIL, exit non-zero on any drift entry
  --input <file>        Path to an AGENTS.md fixture (defaults to AGENTS.md at the repo root).
                        Used by tests/fixtures/ negative-test cases (AC 3, AC 4).
  --alias-map <file>    Path to alias-map YAML (defaults to scripts/agents-md-action-aliases.yaml).
                        Override location: --alias-map <path>.
  --json                Emit a JSON drift report (object with prose_only, block_only, prose_count, block_count).
  --evidence-dir <path> Spec 333: write a JSON audit artifact to <path>/<linter>-<timestamp>.json
                        capturing input SHA, mode, result, and summary. Failure to write the artifact
                        emits a stderr warning but does NOT fail the gate.
  --help                Print this help.

Exit codes:
  0  No drift OR advisory mode
  1  Drift entries found in strict mode
  2  Configuration error (missing AGENTS.md, missing prose section, missing block, malformed alias map)

See: docs/specs/330-agents-md-prose-yaml-block-drift-detector.md
EOF
}

# ---- argument parsing ----
EVIDENCE_DIR=""
while (( "$#" )); do
    case "$1" in
        --help|-h)         usage; exit 0 ;;
        --mode=advisory)   MODE_OVERRIDE="advisory"; shift ;;
        --mode=strict)     MODE_OVERRIDE="strict"; shift ;;
        --input)           INPUT_FILE="$2"; shift 2 ;;
        --alias-map)       ALIAS_MAP_FILE="$2"; shift 2 ;;
        --json)            JSON_OUTPUT="1"; shift ;;
        --evidence-dir)    EVIDENCE_DIR="$2"; shift 2 ;;
        --evidence-dir=*)  EVIDENCE_DIR="${1#--evidence-dir=}"; shift ;;
        *)                 echo "Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

AGENTS_MD="${INPUT_FILE:-$DEFAULT_AGENTS_MD}"
ALIAS_MAP="${ALIAS_MAP_FILE:-$DEFAULT_ALIAS_MAP}"

[[ -f "$AGENTS_MD" ]] || { echo "ERROR: input file not found at $AGENTS_MD" >&2; exit 2; }

# ---- helpers ----

strip_cr() { sed 's/\r$//'; }

unquote() { sed -e "s/^[[:space:]]*'//" -e "s/'[[:space:]]*\$//"; }

# Trim leading and trailing whitespace from a value
trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# Slugify a free-text command token into a block-style action name.
# Examples:
#   "git push"          -> "git_push"
#   "git push --force"  -> "git_push_force"
#   "gh pr create"      -> "gh_pr_create"
#   "rm -rf"            -> "rm_rf"
#   "git checkout --"   -> "git_checkout_dashes"
#   "reset --hard"      -> "reset_hard"
#   "branch -D"         -> "branch_dash_d"
slugify() {
    local s="$1"
    # Lowercase
    s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
    # Specific transforms before generic slugify
    s="${s//--hard/_hard}"
    s="${s//--force/_force}"
    # "git checkout --" trailing-double-dash → "git_checkout_dashes"
    if [[ "$s" =~ ^(.*)[[:space:]]--$ ]]; then
        s="${BASH_REMATCH[1]}_dashes"
    fi
    # Trim
    s="$(printf '%s' "$s" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    # Replace spaces, dashes, dots with underscores
    s="$(printf '%s' "$s" | sed -e 's/[[:space:]]\+/_/g' -e 's/-/_/g')"
    # Collapse runs of underscores
    s="$(printf '%s' "$s" | sed -e 's/_\+/_/g')"
    # Strip trailing/leading underscores
    s="$(printf '%s' "$s" | sed -e 's/^_//' -e 's/_$//')"
    printf '%s' "$s"
}

# ---- alias-map parsing ----

# ALIAS_KEYS[i] -> ALIAS_TARGETS[i] (prose phrase → block action name)
# IGNORE_PROSE[i] (prose phrases to skip)
# IGNORE_BLOCK[i] (block actions to skip)
parse_alias_map() {
    ALIAS_KEYS=()
    ALIAS_TARGETS=()
    IGNORE_PROSE=()
    IGNORE_BLOCK=()
    [[ -f "$ALIAS_MAP" ]] || return 0

    local section="" linenum=0 line stripped key value
    local pending_key="" pending_linenum=0
    while IFS= read -r line; do
        linenum=$((linenum + 1))
        line="${line%$'\r'}"
        # Skip blank/comment
        [[ -z "${line// }" ]] && continue
        [[ "${line#"${line%%[![:space:]]*}"}" == \#* ]] && continue
        # Strip trailing inline comment
        stripped="$(printf '%s' "$line" | sed -E "s/  #.*$//")"

        # Top-level keys (no leading whitespace): aliases:, ignore_prose:, ignore_block:
        if [[ "${stripped:0:1}" != " " ]] && [[ "$stripped" =~ ^([a-z_]+):[[:space:]]*$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$section" == "aliases" ]]; then
            # Two forms supported:
            # 1. Inline:    "phrase": target
            # 2. Block-2-line:
            #         - prose: phrase
            #           target: action_name
            # We support form 1 (inline only) for simplicity. Form-1 line shape:
            #   "<phrase>": <action_or_blank>
            #   '<phrase>': <action_or_blank>
            if [[ "$stripped" =~ ^[[:space:]]+\"([^\"]*)\":[[:space:]]*(.*)$ ]] || \
               [[ "$stripped" =~ ^[[:space:]]+\'([^\']*)\':[[:space:]]*(.*)$ ]]; then
                key="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]}"
                # Strip quotes (if any) and trim trailing whitespace (e.g., from stripped inline comments)
                value="$(printf '%s' "$value" | unquote | trim)"
                # DA Finding 2 disposition: reject empty targets
                if [[ -z "$value" ]]; then
                    echo "ERROR: malformed alias-map entry at line $linenum — alias '$key' has empty/missing target. Empty targets are rejected to prevent silent drift escape (Spec 330 DA Finding 2 disposition)." >&2
                    exit 2
                fi
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
    local phrase="$1"
    local i
    for i in "${!ALIAS_KEYS[@]}"; do
        if [[ "${ALIAS_KEYS[i]}" == "$phrase" ]]; then
            printf '%s' "${ALIAS_TARGETS[i]}"
            return 0
        fi
    done
    return 1
}

is_ignored_prose() {
    local phrase="$1"
    local i
    for i in "${!IGNORE_PROSE[@]}"; do
        [[ "${IGNORE_PROSE[i]}" == "$phrase" ]] && return 0
    done
    return 1
}

is_ignored_block() {
    local action="$1"
    local i
    for i in "${!IGNORE_BLOCK[@]}"; do
        [[ "${IGNORE_BLOCK[i]}" == "$action" ]] && return 0
    done
    return 1
}

# ---- prose extraction ----

# Extract the prose section: lines between "### Authorization-required commands"
# and the next heading (^### or ^##).
extract_prose_section() {
    awk '
        /^### Authorization-required commands[[:space:]]*$/ { capturing=1; next }
        capturing && /^#{2,3}[[:space:]]/ { exit }
        capturing { print }
    ' "$AGENTS_MD" | strip_cr
}

# Extract action names from prose. Strategy:
# 1. Iterate over prose-section lines that begin with "- " (bullet markers).
# 2. Decide whether the bullet is a SIMPLE bullet (primary action = first backtick token)
#    or a LIST bullet (prose then ":" then a series of backtick tokens). Heuristic:
#      - Simple bullet:   "- `token` ..."   (backtick is the FIRST non-space char after "- ")
#      - List bullet:     "- prose: `a`, `b`, ..."   (bullet has ":" before any backtick)
# 3. For SIMPLE bullets, extract ONLY the first backtick token (parenthetical/inline backtick
#    references like `/implement` are context, not action declarations).
# 4. For LIST bullets, extract ALL backtick tokens (each is an enumerated action).
# 5. For each extracted token: ignore_prose lookup → alias lookup → slugify.
extract_prose_actions() {
    PROSE_ACTIONS=()
    PROSE_RAW_TOKENS=()
    local content
    content="$(extract_prose_section)"

    if [[ -z "${content// }" ]]; then
        echo "ERROR: 'authorization-required-commands' prose section not found in AGENTS.md (heading '### Authorization-required commands' missing or renamed)" >&2
        exit 2
    fi

    local line is_list raw_token normalized prefix
    while IFS= read -r line; do
        # Only bullet lines
        [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]] || continue

        # Determine bullet type. If a ":" appears before the first backtick, it's a list bullet.
        is_list=0
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+([^\`]*): ]]; then
            prefix="${BASH_REMATCH[1]}"
            # Confirm the prefix actually appears before any backtick on the line
            if [[ "$line" == *":"* ]] && [[ "${line%%\`*}" == *":"* ]]; then
                is_list=1
            fi
        fi

        local rest="$line"
        local extracted_first=0
        while [[ "$rest" =~ \`([^\`]+)\` ]]; do
            raw_token="${BASH_REMATCH[1]}"
            PROSE_RAW_TOKENS+=("$raw_token")

            # Simple bullet: only the first backtick token counts
            if [[ "$is_list" == "0" ]] && [[ "$extracted_first" == "1" ]]; then
                rest="${rest#*\`"${raw_token}"\`}"
                continue
            fi
            extracted_first=1

            # ignore_prose
            if is_ignored_prose "$raw_token"; then
                rest="${rest#*\`"${raw_token}"\`}"
                continue
            fi
            # alias lookup
            if normalized="$(apply_alias "$raw_token")"; then
                PROSE_ACTIONS+=("$normalized")
            else
                normalized="$(slugify "$raw_token")"
                [[ -n "$normalized" ]] && PROSE_ACTIONS+=("$normalized")
            fi
            rest="${rest#*\`"${raw_token}"\`}"
        done
    done <<< "$content"
    return 0
}

# ---- block extraction ----

# Extract the sentinel-delimited YAML block content (between the ```yaml fence markers).
extract_block_section() {
    awk '
        /<!-- forge:auth-rules:start -->/ {capturing=1; next}
        /<!-- forge:auth-rules:end -->/   {capturing=0}
        capturing {print}
    ' "$AGENTS_MD" | strip_cr | awk '
        /^```yaml/ {infence=1; next}
        /^```/     {infence=0}
        infence    {print}
    '
}

extract_block_actions() {
    BLOCK_ACTIONS=()
    local content
    content="$(extract_block_section)"

    if [[ -z "${content// }" ]]; then
        echo "ERROR: AGENTS.md structured block not found between sentinels '<!-- forge:auth-rules:start -->' / '<!-- forge:auth-rules:end -->'" >&2
        exit 2
    fi

    local line stripped
    local in_actions=0
    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ -z "${line// }" ]] && continue
        [[ "${line#"${line%%[![:space:]]*}"}" == \#* ]] && continue
        stripped="$(printf '%s' "$line" | sed -E "s/  #.*$//")"

        # Top-level "actions:" key
        if [[ "${stripped:0:1}" != " " ]] && [[ "$stripped" =~ ^actions:[[:space:]]*$ ]]; then
            in_actions=1
            continue
        fi
        if [[ "${stripped:0:1}" != " " ]] && [[ "$stripped" =~ ^[a-z_]+: ]]; then
            in_actions=0
            continue
        fi

        if [[ "$in_actions" == "1" ]]; then
            if [[ "$stripped" =~ ^[[:space:]]+-[[:space:]]+name:[[:space:]]+(.*)$ ]]; then
                local name
                name="$(printf '%s' "${BASH_REMATCH[1]}" | unquote)"
                # Apply ignore_block filter
                is_ignored_block "$name" || BLOCK_ACTIONS+=("$name")
            fi
        fi
    done <<< "$content"
    return 0
}

# ---- alias target validation (Spec 330 AC 9b) ----
#
# Reject alias-map entries whose target is not a declared block action (post-ignore_block filter).
# This catches structural inconsistencies like the `branch -D → git_branch_force_delete` entry
# that /consensus 330 surfaced — currently masked by `branch -D` being in ignore_prose, but
# present and confusing in the alias map. The malicious analogue is an operator who silences
# a block action via ignore_block AND aliases it; both layers of bypass become immediately
# visible at parse time.
validate_alias_targets() {
    local i target found b
    for i in "${!ALIAS_KEYS[@]}"; do
        target="${ALIAS_TARGETS[i]}"
        found=0
        for b in "${BLOCK_ACTIONS[@]}"; do
            if [[ "$target" == "$b" ]]; then
                found=1
                break
            fi
        done
        if [[ "$found" == "0" ]]; then
            echo "ERROR: alias-map entry '${ALIAS_KEYS[i]}' targets '$target' which is not a declared block action (Spec 330 AC 9b). Add the target to the AGENTS.md YAML block, fix the alias target, or remove the alias entry." >&2
            exit 2
        fi
    done
    return 0
}

# ---- set comparison ----

# Compute prose-only and block-only sets.
compute_drift() {
    PROSE_ONLY=()
    BLOCK_ONLY=()
    local p b found
    # Dedupe prose actions while computing prose-only
    local seen_prose=""
    for p in "${PROSE_ACTIONS[@]}"; do
        # Dedupe: skip if already-seen
        case " $seen_prose " in *" $p "*) continue ;; esac
        seen_prose+=" $p"
        found=0
        for b in "${BLOCK_ACTIONS[@]}"; do
            [[ "$p" == "$b" ]] && found=1 && break
        done
        [[ "$found" == "0" ]] && PROSE_ONLY+=("$p")
    done
    local seen_block=""
    for b in "${BLOCK_ACTIONS[@]}"; do
        case " $seen_block " in *" $b "*) continue ;; esac
        seen_block+=" $b"
        found=0
        for p in "${PROSE_ACTIONS[@]}"; do
            [[ "$p" == "$b" ]] && found=1 && break
        done
        [[ "$found" == "0" ]] && BLOCK_ONLY+=("$b")
    done
    return 0
}

count_unique() {
    local arr_name="$1"
    eval "local arr=(\"\${${arr_name}[@]}\")"
    local seen="" item count=0
    # shellcheck disable=SC2154  # arr assigned via eval above
    for item in "${arr[@]}"; do
        case " $seen " in *" $item "*) continue ;; esac
        seen+=" $item"
        count=$((count + 1))
    done
    printf '%d' "$count"
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Spec 333: Write a JSON audit artifact when --evidence-dir is set.
# Atomic write (write-to-tmp + mv). Millisecond timestamp + PID in filename.
# Inputs: $1=linter $2=input_file $3=mode $4=result $5=exit_code $6=stdout $7=summary_json
# Failure modes: warning to stderr, returns 0 (never fails the gate).
write_evidence_artifact() {
    [[ -z "$EVIDENCE_DIR" ]] && return 0
    local linter_name="$1" input_file="$2" mode="$3" result="$4" exit_code="$5"
    local stdout_buf="$6" summary_json="$7"

    if ! mkdir -p "$EVIDENCE_DIR" 2>/dev/null; then
        echo "WARN: validate-agents-md-drift: failed to create evidence dir '$EVIDENCE_DIR' — artifact not written" >&2
        return 0
    fi
    if [[ ! -w "$EVIDENCE_DIR" ]]; then
        echo "WARN: validate-agents-md-drift: evidence dir '$EVIDENCE_DIR' is not writable — artifact not written" >&2
        return 0
    fi

    local ts_iso ts_file input_sha git_commit spec_id final_path tmp_path
    ts_iso="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
    ts_file="$(date -u +%Y%m%dT%H%M%S 2>/dev/null)-$$"
    input_sha=""
    [[ -f "$input_file" ]] && input_sha="$(git -C "$REPO_ROOT" hash-object "$input_file" 2>/dev/null || true)"
    git_commit="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
    spec_id=""
    if [[ "$EVIDENCE_DIR" =~ SPEC-([0-9]+)- ]]; then
        spec_id="${BASH_REMATCH[1]}"
    fi
    final_path="${EVIDENCE_DIR%/}/${linter_name}-${ts_file}.json"
    tmp_path="${final_path}.tmp"

    if ! {
        printf '{\n'
        printf '  "linter": "%s",\n' "$linter_name"
        printf '  "spec": "%s",\n' "$spec_id"
        printf '  "ran_at": "%s",\n' "$ts_iso"
        printf '  "input_file": "%s",\n' "$(json_escape "$input_file")"
        printf '  "input_sha": "%s",\n' "$input_sha"
        printf '  "mode": "%s",\n' "$mode"
        printf '  "result": "%s",\n' "$result"
        printf '  "exit_code": %s,\n' "$exit_code"
        printf '  "summary": %s,\n' "$summary_json"
        printf '  "stdout": "%s",\n' "$(json_escape "$stdout_buf")"
        printf '  "stderr": "",\n'
        printf '  "git_commit": "%s"\n' "$git_commit"
        printf '}\n'
    } > "$tmp_path" 2>/dev/null; then
        echo "WARN: validate-agents-md-drift: failed to write evidence artifact to '$tmp_path'" >&2
        rm -f "$tmp_path" 2>/dev/null
        return 0
    fi

    if ! mv "$tmp_path" "$final_path" 2>/dev/null; then
        echo "WARN: validate-agents-md-drift: failed to rename evidence artifact to '$final_path'" >&2
        rm -f "$tmp_path" 2>/dev/null
        return 0
    fi
    return 0
}

# ---- main ----

parse_alias_map
extract_block_actions
validate_alias_targets   # Spec 330 AC 9b — reject dangling alias targets at parse time
extract_prose_actions
compute_drift

PROSE_COUNT="$(count_unique PROSE_ACTIONS)"
BLOCK_COUNT="$(count_unique BLOCK_ACTIONS)"
DRIFT_COUNT=$(( ${#PROSE_ONLY[@]} + ${#BLOCK_ONLY[@]} ))

EFFECTIVE_MODE="${MODE_OVERRIDE:-advisory}"

# ---- output ----

# Spec 333: capture GATE output into a buffer for the audit artifact.
GATE_BUF=""
RESULT_LABEL=""

if [[ -n "$JSON_OUTPUT" ]]; then
    JSON_BUF=$(
        printf '{'
        printf '"prose_count":%d,' "$PROSE_COUNT"
        printf '"block_count":%d,' "$BLOCK_COUNT"
        printf '"drift_count":%d,' "$DRIFT_COUNT"
        printf '"mode":"%s",' "$(json_escape "$EFFECTIVE_MODE")"
        printf '"prose_only":['
        first=1
        for p in "${PROSE_ONLY[@]}"; do
            [[ $first -eq 1 ]] && first=0 || printf ','
            printf '"%s"' "$(json_escape "$p")"
        done
        printf '],'
        printf '"block_only":['
        first=1
        for b in "${BLOCK_ONLY[@]}"; do
            [[ $first -eq 1 ]] && first=0 || printf ','
            printf '"%s"' "$(json_escape "$b")"
        done
        printf ']'
        printf '}\n'
    )
    printf '%s' "$JSON_BUF"
    GATE_BUF="$JSON_BUF"
    if [[ "$DRIFT_COUNT" -eq 0 ]]; then
        RESULT_LABEL="PASS"
    elif [[ "$EFFECTIVE_MODE" == "strict" ]]; then
        RESULT_LABEL="FAIL"
    else
        RESULT_LABEL="WARN"
    fi
else
    if [[ "$DRIFT_COUNT" -eq 0 ]]; then
        GATE_BUF="GATE [agents-md-drift]: PASS - $PROSE_COUNT actions in prose, $BLOCK_COUNT in block, 0 drift entries (mode=$EFFECTIVE_MODE)"
        RESULT_LABEL="PASS"
        echo "$GATE_BUF"
    else
        RESULT_LABEL="WARN"
        [[ "$EFFECTIVE_MODE" == "strict" ]] && RESULT_LABEL="FAIL"
        GATE_BUF="GATE [agents-md-drift]: $RESULT_LABEL - $PROSE_COUNT in prose, $BLOCK_COUNT in block, $DRIFT_COUNT drift entries (mode=$EFFECTIVE_MODE):"
        echo "$GATE_BUF"
        for p in "${PROSE_ONLY[@]}"; do
            line="  prose-only: $p"
            echo "$line"
            GATE_BUF="${GATE_BUF}"$'\n'"$line"
        done
        for b in "${BLOCK_ONLY[@]}"; do
            line="  block-only: $b"
            echo "$line"
            GATE_BUF="${GATE_BUF}"$'\n'"$line"
        done
    fi
fi

# ---- exit code + artifact ----

EXIT_CODE_FINAL=0
if [[ "$DRIFT_COUNT" -ne 0 && "$EFFECTIVE_MODE" == "strict" ]]; then
    EXIT_CODE_FINAL=1
fi

# Spec 333: write evidence artifact (skipped silently if EVIDENCE_DIR is empty)
PROSE_ONLY_JSON="["
first=1; for p in "${PROSE_ONLY[@]}"; do [[ $first -eq 1 ]] && first=0 || PROSE_ONLY_JSON="${PROSE_ONLY_JSON},"; PROSE_ONLY_JSON="${PROSE_ONLY_JSON}\"$(json_escape "$p")\""; done
PROSE_ONLY_JSON="${PROSE_ONLY_JSON}]"
BLOCK_ONLY_JSON="["
first=1; for b in "${BLOCK_ONLY[@]}"; do [[ $first -eq 1 ]] && first=0 || BLOCK_ONLY_JSON="${BLOCK_ONLY_JSON},"; BLOCK_ONLY_JSON="${BLOCK_ONLY_JSON}\"$(json_escape "$b")\""; done
BLOCK_ONLY_JSON="${BLOCK_ONLY_JSON}]"
SUMMARY_JSON_DRIFT="{\"prose_count\":${PROSE_COUNT},\"block_count\":${BLOCK_COUNT},\"drift_count\":${DRIFT_COUNT},\"prose_only\":${PROSE_ONLY_JSON},\"block_only\":${BLOCK_ONLY_JSON}}"
write_evidence_artifact "validate-agents-md-drift" "$AGENTS_MD" "$EFFECTIVE_MODE" "$RESULT_LABEL" "$EXIT_CODE_FINAL" "$GATE_BUF" "$SUMMARY_JSON_DRIFT"

exit $EXIT_CODE_FINAL

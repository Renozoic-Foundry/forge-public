#!/usr/bin/env bash
# validate-authorization-rules.sh — Lint command bodies vs AGENTS.md authorization rules.
# Part of Spec 327 — Standing lint gate for AGENTS.md authorization rules vs command bodies.
#
# Reads the sentinel-delimited YAML block in AGENTS.md (<!-- forge:auth-rules:start --> ... end -->)
# and scans every command body under the four canonical roots for authorization-required actions
# that lack a gating token within the configured proximity window.
#
# Usage: scripts/validate-authorization-rules.sh [--mode=advisory|strict] [--json] [--help]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS_MD="${REPO_ROOT}/AGENTS.md"
WHITELIST="${REPO_ROOT}/scripts/auth-rules-whitelist.yaml"
SCAN_ROOTS=(
    "${REPO_ROOT}/.claude/commands"
    "${REPO_ROOT}/.forge/commands"
    "${REPO_ROOT}/template/.claude/commands"
    "${REPO_ROOT}/template/.forge/commands"
)
MIN_ACTIONS=(git_push git_push_force git_reset_hard git_checkout_dashes gh_pr_create gh_pr_merge rm_rf)

# Spec 504: deterministic work-unit cap (a backstop, NOT the perf fix). One work unit is
# counted per (file × action × matching-line) processed in the scan body. If the running
# total exceeds this limit the gate trips FAIL-LOUD (WARN in advisory, FAIL + non-zero in
# strict) and NEVER exits 0 / emits PASS. This is a deterministic iteration count, NOT a
# wall-clock timeout, so the AC-3 fail-loud test is reproducible / non-flaky. The value is a
# named constant declared IDENTICALLY in the .ps1 variant (AC-5 cap-semantics equivalence) —
# do not change one without the other (the test asserts threshold equality across variants).
# FORGE_AUTH_LINT_WORK_CAP is a test-only override that lets AC-3 drive the cap deterministically.
SCAN_WORK_UNIT_CAP="${FORGE_AUTH_LINT_WORK_CAP:-1000000}"

MODE_OVERRIDE=""
JSON_OUTPUT=""
SCAN_PATHS_OVERRIDE=""

usage() {
    cat <<'EOF'
validate-authorization-rules.sh — Spec 327 lint gate

Usage: scripts/validate-authorization-rules.sh [--mode=advisory|strict] [--json] [--evidence-dir <path>] [--help]

Reads AGENTS.md sentinel-delimited block (<!-- forge:auth-rules:start --> ... <!-- forge:auth-rules:end -->)
and scans command bodies under .claude/commands/, .forge/commands/, template/.claude/commands/,
template/.forge/commands/ for authorization-required actions without preceding gating tokens.

Whitelist: scripts/auth-rules-whitelist.yaml (entries require file:, action:, reason:).

Options:
  --mode=advisory       Emit WARN, exit 0 (default at first ship per Spec 327 Path B)
  --mode=strict         Emit FAIL, exit non-zero on any violation
  --json                Emit JSON array of {file, line, action, gating_token_found, whitelist_entry}
  --scan-paths=A,B      Comma-separated paths to scan (overrides the 4 default roots; for tests/fixtures)
  --evidence-dir <path> Spec 333: write a JSON audit artifact to <path>/<linter>-<timestamp>.json
                        capturing input SHA, mode, result, and summary. Failure to write the artifact
                        emits a stderr warning but does NOT fail the gate. Both --evidence-dir <path>
                        and --evidence-dir=<path> forms are accepted.
  --help                Print this help

Exit codes:
  0  No violations OR advisory mode
  1  Violations found in strict mode
  2  Configuration error (missing/malformed AGENTS.md block, missing required action, malformed whitelist entry)

See: docs/specs/327-agents-md-authorization-rule-lint-gate.md
EOF
}

# ---- argument parsing ----
# Spec 333: extract --evidence-dir <path> (or --evidence-dir=<path>) before the main arg loop
# so the existing for-loop doesn't need to handle two-token args.
EVIDENCE_DIR=""
filtered_args=()
i=1
while [[ $i -le $# ]]; do
    arg="${!i}"
    case "$arg" in
        --evidence-dir=*) EVIDENCE_DIR="${arg#--evidence-dir=}" ;;
        --evidence-dir)
            i=$((i+1))
            EVIDENCE_DIR="${!i}"
            ;;
        *) filtered_args+=("$arg") ;;
    esac
    i=$((i+1))
done
set -- "${filtered_args[@]+"${filtered_args[@]}"}"

for arg in "$@"; do
    case "$arg" in
        --help|-h)        usage; exit 0 ;;
        --mode=advisory)  MODE_OVERRIDE="advisory" ;;
        --mode=strict)    MODE_OVERRIDE="strict" ;;
        --json)           JSON_OUTPUT="1" ;;
        --scan-paths=*)   SCAN_PATHS_OVERRIDE="${arg#--scan-paths=}" ;;
        *)                echo "Unknown argument: $arg" >&2; usage; exit 2 ;;
    esac
done

# ---- helpers ----

# Strip trailing CR (Windows line endings)
strip_cr() { sed 's/\r$//'; }

# Extract the sentinel-delimited YAML block content (between the ```yaml fence markers)
extract_block() {
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

# Spec 504 perf fix: pure-bash equivalents of the per-line `printf '%s' "$x" | sed`
# subshells that parse_block/parse_whitelist used for single-quote trimming and inline-comment
# stripping. On fork-expensive runtimes (Windows/Git-Bash) that subshell-per-field form spawned
# hundreds of processes during startup and was the dominant cost of the >90s hang (the scan body
# subprocess fan-out was only part of it). Behavior is preserved: same leading-space + single-quote
# trimming, same "  #..." inline-comment strip on the FIRST double-space-hash occurrence.

# Strip a leading single quote (with optional leading spaces) and a trailing single quote
# (with optional trailing spaces) — pure-bash, no subprocess. Result is returned via the global
# RET (NOT printed + captured via $(...), which would re-introduce a subshell fork per call).
RET=""
unquote_str() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"   # left-trim whitespace
    v="${v#\'}"                        # drop one leading single quote
    v="${v%"${v##*[![:space:]]}"}"   # right-trim trailing whitespace
    v="${v%\'}"                        # drop one trailing single quote
    RET="$v"
}

# Strip an inline YAML comment beginning at the first "  #" (two spaces + hash) — pure-bash.
# Equivalent to sed -E "s/  #.*$//" for our line shape. Keeps #'s inside quoted values intact
# because those are not preceded by a double-space in this corpus. Result returned via RET.
strip_inline_comment_str() {
    local s="$1"
    if [[ "$s" == *"  #"* ]]; then
        s="${s%%  #*}"
    fi
    RET="$s"
}

# Parse the structured block into shell-readable arrays:
#   MODE_DEFAULT, WINDOW_DEFAULT, GATING_DEFAULT (top-level scalars)
#   ACTION_NAMES[i], ACTION_PATTERNS[i], ACTION_GATING[i], ACTION_WINDOWS[i]
parse_block() {
    local block_content="$1"
    MODE_DEFAULT=""
    WINDOW_DEFAULT="10"
    GATING_DEFAULT='\(yes/no\)'
    ACTION_NAMES=()
    ACTION_PATTERNS=()
    ACTION_GATING=()
    ACTION_WINDOWS=()

    local in_actions=0 idx=-1
    local key value
    while IFS= read -r line; do
        line="${line%$'\r'}"
        # Skip blank/comment lines
        [[ -z "${line// }" ]] && continue
        [[ "${line#"${line%%[![:space:]]*}"}" == \#* ]] && continue

        # Strip inline YAML comments (but keep #'s inside single-quoted values intact)
        # We avoid parsing complex YAML; simple split on " #" works for our shape.
        # Spec 504: pure-bash (RET) — no `printf | sed` subshell per line.
        local stripped
        strip_inline_comment_str "$line"; stripped="$RET"

        # Top-level keys (no leading spaces) — match either "key: value" or bare "key:"
        if [[ "${stripped:0:1}" != " " ]] && [[ "$stripped" =~ ^([a-z_]+):([[:space:]]+(.*))?$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[3]:-}"
            unquote_str "$value"; value="$RET"
            case "$key" in
                mode)                     MODE_DEFAULT="$value"; in_actions=0 ;;
                proximity_window_default) WINDOW_DEFAULT="$value"; in_actions=0 ;;
                gating_token_default)     GATING_DEFAULT="$value"; in_actions=0 ;;
                actions)                  in_actions=1 ;;
                *) : ;;
            esac
            continue
        fi

        # Inside actions list
        if [[ "$in_actions" == "1" ]]; then
            # New action entry: "  - name: foo"
            if [[ "$stripped" =~ ^[[:space:]]+-[[:space:]]+name:[[:space:]]+(.*)$ ]]; then
                idx=$((idx + 1))
                unquote_str "${BASH_REMATCH[1]}"; ACTION_NAMES[idx]="$RET"
                ACTION_PATTERNS[idx]=""
                ACTION_GATING[idx]=""
                ACTION_WINDOWS[idx]=""
                continue
            fi
            # Action field: "    pattern: 'foo'"
            if [[ "$stripped" =~ ^[[:space:]]+([a-z_]+):[[:space:]]+(.*)$ ]] && [[ "$idx" -ge 0 ]]; then
                key="${BASH_REMATCH[1]}"
                unquote_str "${BASH_REMATCH[2]}"; value="$RET"
                case "$key" in
                    pattern)          ACTION_PATTERNS[idx]="$value" ;;
                    gating_token)     ACTION_GATING[idx]="$value" ;;
                    proximity_window) ACTION_WINDOWS[idx]="$value" ;;
                    *) : ;;
                esac
            fi
        fi
    done <<< "$block_content"
}

# Parse whitelist: WL_FILES[i], WL_ACTIONS[i], WL_REASONS[i].
# A malformed entry (missing any of file/action/reason) sets MALFORMED_WHITELIST=<line-of-defect>.
parse_whitelist() {
    WL_FILES=()
    WL_ACTIONS=()
    WL_REASONS=()
    MALFORMED_WHITELIST=""
    [[ -f "$WHITELIST" ]] || return 0

    local idx=-1 file action reason linenum=0 last_entry_start=0
    local key value
    while IFS= read -r line; do
        linenum=$((linenum + 1))
        line="${line%$'\r'}"
        # Strip comments and blanks
        [[ -z "${line// }" ]] && continue
        [[ "${line#"${line%%[![:space:]]*}"}" == \#* ]] && continue
        local stripped
        strip_inline_comment_str "$line"; stripped="$RET"

        # New entry: "- file: foo.md"
        if [[ "$stripped" =~ ^-[[:space:]]+file:[[:space:]]+(.*)$ ]]; then
            # Validate previous entry before starting new one
            if [[ "$idx" -ge 0 ]]; then
                if [[ -z "${WL_FILES[idx]:-}" || -z "${WL_ACTIONS[idx]:-}" || -z "${WL_REASONS[idx]:-}" ]]; then
                    MALFORMED_WHITELIST="entry starting at line $last_entry_start lacks file/action/reason"
                    return 0
                fi
            fi
            idx=$((idx + 1))
            last_entry_start=$linenum
            unquote_str "${BASH_REMATCH[1]}"; WL_FILES[idx]="$RET"
            WL_ACTIONS[idx]=""
            WL_REASONS[idx]=""
            # Reject wildcard file patterns (Spec 327 R4: no wildcards)
            case "${WL_FILES[idx]}" in
                *"*"*|*"?"*) MALFORMED_WHITELIST="entry at line $linenum uses wildcard file pattern (forbidden by Spec 327 R4)"; return 0 ;;
            esac
            continue
        fi
        # Subsequent fields: "  action: ..." or "  reason: ..." or alternate "- file:" already matched above
        if [[ "$stripped" =~ ^[[:space:]]+([a-z_]+):[[:space:]]+(.*)$ ]] && [[ "$idx" -ge 0 ]]; then
            key="${BASH_REMATCH[1]}"
            unquote_str "${BASH_REMATCH[2]}"; value="$RET"
            case "$key" in
                action) WL_ACTIONS[idx]="$value" ;;
                reason) WL_REASONS[idx]="$value" ;;
                file)   WL_FILES[idx]="$value" ;;  # field-only (rare; usually paired with -)
            esac
        fi
    done < "$WHITELIST"

    # Validate the final entry
    if [[ "$idx" -ge 0 ]]; then
        if [[ -z "${WL_FILES[idx]:-}" || -z "${WL_ACTIONS[idx]:-}" || -z "${WL_REASONS[idx]:-}" ]]; then
            MALFORMED_WHITELIST="entry starting at line $last_entry_start lacks file/action/reason"
        fi
    fi
}

# Check if (file, action) is in the whitelist.
# Spec 504 perf fix: returns the reason via the global WL_REASON_OUT (set before return)
# rather than printf-to-stdout-captured-via-$(...). The old command-substitution form
# spawned a subshell on EVERY match, which dominated runtime on fork-expensive runtimes.
WL_REASON_OUT=""
is_whitelisted() {
    local file_rel="$1" action_name="$2"
    local i
    WL_REASON_OUT=""
    for i in "${!WL_FILES[@]}"; do
        if [[ "${WL_FILES[i]}" == "$file_rel" && "${WL_ACTIONS[i]}" == "$action_name" ]]; then
            WL_REASON_OUT="${WL_REASONS[i]}"
            return 0
        fi
    done
    return 1
}

# Check whether a gating token appears within `window` lines BEFORE `match_line`.
# Spec 504 perf fix: operates IN-MEMORY on the global FILE_LINES array (0-indexed, already
# CR-stripped, populated once per file by the scan loop) instead of spawning `sed | grep`
# per match. FILE_LINES[k] holds source line k+1. Scans lines [start, match_line] inclusive.
# Returns 0 (gated) on the first line that matches gating_re, 1 (not gated) otherwise.
has_gating_token_before() {
    local match_line="$1" window="$2" gating_re="$3"
    local start=$(( match_line - window ))
    [[ $start -lt 1 ]] && start=1
    local k
    for (( k = start; k <= match_line; k++ )); do
        if [[ "${FILE_LINES[$((k-1))]:-}" =~ $gating_re ]]; then
            return 0
        fi
    done
    return 1
}

# Spec 333: Write a JSON audit artifact when --evidence-dir is set.
# Atomic write (write-to-tmp + mv) per DA disposition. Millisecond timestamp + PID
# in filename to avoid collisions on rapid successive runs.
# Inputs: $1=linter_name $2=input_file $3=mode $4=result $5=exit_code $6=stdout $7=summary_json
# Failure modes: warning to stderr, returns 0 (never fails the gate).
write_evidence_artifact() {
    [[ -z "$EVIDENCE_DIR" ]] && return 0
    local linter_name="$1" input_file="$2" mode="$3" result="$4" exit_code="$5"
    local stdout_buf="$6" summary_json="$7"

    if ! mkdir -p "$EVIDENCE_DIR" 2>/dev/null; then
        echo "WARN: validate-authorization-rules: failed to create evidence dir '$EVIDENCE_DIR' — artifact not written" >&2
        return 0
    fi
    if [[ ! -w "$EVIDENCE_DIR" ]]; then
        echo "WARN: validate-authorization-rules: evidence dir '$EVIDENCE_DIR' is not writable — artifact not written" >&2
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
        echo "WARN: validate-authorization-rules: failed to write evidence artifact to '$tmp_path'" >&2
        rm -f "$tmp_path" 2>/dev/null
        return 0
    fi

    if ! mv "$tmp_path" "$final_path" 2>/dev/null; then
        echo "WARN: validate-authorization-rules: failed to rename evidence artifact to '$final_path'" >&2
        rm -f "$tmp_path" 2>/dev/null
        return 0
    fi
    return 0
}

# JSON-escape a string (basic: backslash, double quote, newline)
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# ---- main ----

[[ -f "$AGENTS_MD" ]] || { echo "ERROR: AGENTS.md not found at $AGENTS_MD" >&2; exit 2; }

BLOCK_CONTENT="$(extract_block)"
if [[ -z "$BLOCK_CONTENT" ]]; then
    echo "ERROR: AGENTS.md structured block not found between sentinels '<!-- forge:auth-rules:start -->' / '<!-- forge:auth-rules:end -->'" >&2
    exit 2
fi

parse_block "$BLOCK_CONTENT"
if [[ ${#ACTION_NAMES[@]} -eq 0 ]]; then
    echo "ERROR: AGENTS.md structured block contains no actions (malformed YAML or empty actions list)" >&2
    exit 2
fi

# Verify minimum action set is present (whitelist-via-deletion prevention)
for required in "${MIN_ACTIONS[@]}"; do
    found=0
    for declared in "${ACTION_NAMES[@]}"; do
        [[ "$declared" == "$required" ]] && found=1 && break
    done
    if [[ "$found" == "0" ]]; then
        echo "ERROR: required action '$required' missing from AGENTS.md structured block" >&2
        exit 2
    fi
done

parse_whitelist
if [[ -n "${MALFORMED_WHITELIST:-}" ]]; then
    echo "ERROR: malformed whitelist entry — $MALFORMED_WHITELIST" >&2
    exit 2
fi

# Determine effective mode
EFFECTIVE_MODE="${MODE_OVERRIDE:-${MODE_DEFAULT:-advisory}}"
if [[ "$EFFECTIVE_MODE" != "advisory" && "$EFFECTIVE_MODE" != "strict" ]]; then
    echo "ERROR: invalid mode '$EFFECTIVE_MODE' (expected advisory or strict)" >&2
    exit 2
fi

# ---- scan ----

VIOLATION_FILES=()
VIOLATION_LINES=()
VIOLATION_ACTIONS=()
VIOLATION_GATING_FOUND=()
VIOLATION_WHITELIST=()
SCANNED_FILES=0
START_TIME=$(date +%s)

# Spec 504: deterministic work-unit counter + fail-loud cap state. WORK_UNITS increments once
# per (file × action × matching-line) processed; if it exceeds SCAN_WORK_UNIT_CAP the scan stops
# and CAP_TRIPPED is set so the output section emits a non-clean verdict (never PASS/exit-0).
WORK_UNITS=0
CAP_TRIPPED=0
# FILE_LINES is the per-file in-memory line buffer (CR-stripped), read ONCE per file. The scan
# matches and looks back for gating tokens against this array instead of re-spawning grep/sed.
FILE_LINES=()

# Spec 504 perf fix: cheap per-line literal pre-filter. The expensive part of an in-process scan
# is running every action's dynamic ERE against every one of ~37k corpus lines (≈260k regex
# compiles). But ~99% of lines contain none of the action keywords, so we first test a fast
# literal substring (`[[ == *tok* ]]`, no regex compile) and only fall through to the full
# per-action regex when a candidate token is present. PREFILTER_TOKENS is derived from the
# parsed action patterns (the leading literal word of each, e.g. git / gh / rm) so it stays
# correct if the AGENTS.md action set changes — no hardcoded keyword list. This is purely a
# skip-fast optimization; it never suppresses a real match (any line a pattern matches must
# contain that pattern's leading literal token).
PREFILTER_TOKENS=()
for i in "${!ACTION_PATTERNS[@]}"; do
    _pat="${ACTION_PATTERNS[i]}"
    [[ -z "$_pat" ]] && continue
    # Leading literal token = pattern up to the first space or ERE metacharacter.
    _tok="${_pat%%[ ([{\\^\$.*+?|]*}"
    [[ -z "$_tok" ]] && continue
    # De-dup
    _seen=0
    for _t in "${PREFILTER_TOKENS[@]:-}"; do
        [[ "$_t" == "$_tok" ]] && { _seen=1; break; }
    done
    [[ $_seen -eq 0 ]] && PREFILTER_TOKENS+=("$_tok")
done

# If --scan-paths was given, replace the default roots
if [[ -n "$SCAN_PATHS_OVERRIDE" ]]; then
    IFS=',' read -ra OVERRIDE_LIST <<< "$SCAN_PATHS_OVERRIDE"
    SCAN_ROOTS=()
    for p in "${OVERRIDE_LIST[@]}"; do
        # Resolve relative paths against REPO_ROOT
        case "$p" in
            /*) SCAN_ROOTS+=("$p") ;;
            *)  SCAN_ROOTS+=("${REPO_ROOT}/$p") ;;
        esac
    done
fi

for root in "${SCAN_ROOTS[@]}"; do
    [[ $CAP_TRIPPED -eq 1 ]] && break
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' file; do
        [[ $CAP_TRIPPED -eq 1 ]] && break
        SCANNED_FILES=$((SCANNED_FILES + 1))
        rel="${file#"$REPO_ROOT/"}"

        # Spec 504 perf fix: read the whole file ONCE into FILE_LINES (CR-stripped), then match
        # every line in-process. This eliminates the per-file `grep -nE` and per-match `sed | grep`
        # subprocess fan-out that dominated runtime on fork-expensive (Windows/Git-Bash) runtimes.
        FILE_LINES=()
        while IFS= read -r _ln || [[ -n "$_ln" ]]; do
            FILE_LINES+=("${_ln%$'\r'}")
        done < "$file"

        line_count=${#FILE_LINES[@]}
        for (( li = 0; li < line_count; li++ )); do
            line_text="${FILE_LINES[li]}"
            linenum=$((li + 1))

            # Spec 504 perf fix: cheap literal pre-filter — skip the per-action regex loop
            # entirely unless the line contains at least one action-keyword token.
            _candidate=0
            for _tok in "${PREFILTER_TOKENS[@]:-}"; do
                [[ -n "$_tok" && "$line_text" == *"$_tok"* ]] && { _candidate=1; break; }
            done
            [[ $_candidate -eq 0 ]] && continue

            for i in "${!ACTION_NAMES[@]}"; do
                action_name="${ACTION_NAMES[i]}"
                pattern="${ACTION_PATTERNS[i]}"
                [[ -z "$pattern" ]] && continue
                # In-process ERE match (same semantics as the prior grep -nE "$pattern").
                [[ "$line_text" =~ $pattern ]] || continue

                # Work-unit accounting + deterministic fail-loud cap (Spec 504 R2/R3).
                WORK_UNITS=$((WORK_UNITS + 1))
                if [[ $WORK_UNITS -gt $SCAN_WORK_UNIT_CAP ]]; then
                    CAP_TRIPPED=1
                    break 3
                fi

                gating_re="${ACTION_GATING[i]:-$GATING_DEFAULT}"
                window="${ACTION_WINDOWS[i]:-$WINDOW_DEFAULT}"
                if has_gating_token_before "$linenum" "$window" "$gating_re"; then
                    continue  # gated → not a violation
                fi
                # Whitelist check (Spec 504: in-process — no $(...) subshell per match).
                if is_whitelisted "$rel" "$action_name"; then
                    # Whitelisted — record but mark
                    VIOLATION_FILES+=("$rel")
                    VIOLATION_LINES+=("$linenum")
                    VIOLATION_ACTIONS+=("$action_name")
                    VIOLATION_GATING_FOUND+=("false")
                    VIOLATION_WHITELIST+=("$WL_REASON_OUT")
                    continue
                fi
                VIOLATION_FILES+=("$rel")
                VIOLATION_LINES+=("$linenum")
                VIOLATION_ACTIONS+=("$action_name")
                VIOLATION_GATING_FOUND+=("false")
                VIOLATION_WHITELIST+=("")
            done
        done
    done < <(find "$root" -type f \( -name "*.md" -o -name "*.jinja" \) -print0)
done

ELAPSED=$(( $(date +%s) - START_TIME ))

# Count actionable (non-whitelisted) violations
ACTIONABLE=0
for wl in "${VIOLATION_WHITELIST[@]}"; do
    [[ -z "$wl" ]] && ACTIONABLE=$((ACTIONABLE + 1))
done

# ---- output ----

# Spec 333: capture GATE output into a buffer so the artifact writer can record it.
GATE_BUF=""
RESULT_LABEL=""

# Spec 504 R2/R3: deterministic work-unit cap tripped → FAIL-LOUD. Emit a non-clean verdict
# (WARN in advisory, FAIL + non-zero in strict). NEVER PASS / exit 0. This short-circuits the
# normal PASS/WARN/FAIL block below so a cap-trip can never be reported as a clean scan.
if [[ $CAP_TRIPPED -eq 1 ]]; then
    if [[ "$EFFECTIVE_MODE" == "strict" ]]; then
        RESULT_LABEL="FAIL"
    else
        RESULT_LABEL="WARN"
    fi
    GATE_BUF="GATE [authorization-rule-lint]: $RESULT_LABEL - scan bound exceeded after $WORK_UNITS work units (cap=$SCAN_WORK_UNIT_CAP) over $SCANNED_FILES file(s) (mode=$EFFECTIVE_MODE). Scan halted before completing — verdict is NOT clean. Investigate a malformed/adversarial command body or raise FORGE_AUTH_LINT_WORK_CAP if the corpus legitimately grew."
    echo "$GATE_BUF" >&2
    EXIT_CODE_FINAL=0
    [[ "$EFFECTIVE_MODE" == "strict" ]] && EXIT_CODE_FINAL=1
    SUMMARY_JSON_AUTH="{\"actionable\":0,\"scanned_files\":${SCANNED_FILES},\"action_count\":${#ACTION_NAMES[@]},\"violations_total\":${#VIOLATION_FILES[@]},\"elapsed_seconds\":${ELAPSED},\"cap_tripped\":true,\"work_units\":${WORK_UNITS},\"work_unit_cap\":${SCAN_WORK_UNIT_CAP}}"
    write_evidence_artifact "validate-authorization-rules" "$AGENTS_MD" "$EFFECTIVE_MODE" "$RESULT_LABEL" "$EXIT_CODE_FINAL" "$GATE_BUF" "$SUMMARY_JSON_AUTH"
    exit $EXIT_CODE_FINAL
fi

if [[ -n "$JSON_OUTPUT" ]]; then
    JSON_BUF=$(
        printf '['
        first=1
        for i in "${!VIOLATION_FILES[@]}"; do
            [[ $first -eq 1 ]] && first=0 || printf ','
            wl_field="null"
            [[ -n "${VIOLATION_WHITELIST[i]}" ]] && wl_field="\"$(json_escape "${VIOLATION_WHITELIST[i]}")\""
            printf '\n  {"file":"%s","line":%s,"action":"%s","gating_token_found":%s,"whitelist_entry":%s}' \
                "$(json_escape "${VIOLATION_FILES[i]}")" \
                "${VIOLATION_LINES[i]}" \
                "$(json_escape "${VIOLATION_ACTIONS[i]}")" \
                "${VIOLATION_GATING_FOUND[i]}" \
                "$wl_field"
        done
        printf '\n]\n'
    )
    printf '%s' "$JSON_BUF"
    GATE_BUF="$JSON_BUF"
    if [[ $ACTIONABLE -eq 0 ]]; then
        RESULT_LABEL="PASS"
    elif [[ "$EFFECTIVE_MODE" == "strict" ]]; then
        RESULT_LABEL="FAIL"
    else
        RESULT_LABEL="WARN"
    fi
else
    if [[ $ACTIONABLE -eq 0 ]]; then
        GATE_BUF="GATE [authorization-rule-lint]: PASS - $SCANNED_FILES command files clean across ${#ACTION_NAMES[@]} actions (mode=$EFFECTIVE_MODE, scanned in ${ELAPSED}s)"
        RESULT_LABEL="PASS"
        echo "$GATE_BUF"
    else
        RESULT_LABEL="WARN"
        [[ "$EFFECTIVE_MODE" == "strict" ]] && RESULT_LABEL="FAIL"
        GATE_BUF="GATE [authorization-rule-lint]: $RESULT_LABEL - $ACTIONABLE violation(s) across $SCANNED_FILES files (mode=$EFFECTIVE_MODE, scanned in ${ELAPSED}s):"
        echo "$GATE_BUF"
        for i in "${!VIOLATION_FILES[@]}"; do
            tag=""
            [[ -n "${VIOLATION_WHITELIST[i]}" ]] && tag=" [whitelisted: ${VIOLATION_WHITELIST[i]}]"
            line="  ${VIOLATION_FILES[i]}:${VIOLATION_LINES[i]} | ${VIOLATION_ACTIONS[i]}$tag"
            echo "$line"
            GATE_BUF="${GATE_BUF}"$'\n'"$line"
        done
    fi
fi

# Spec 333: compute exit code first, then write artifact, then exit.
EXIT_CODE_FINAL=0
if [[ $ACTIONABLE -ne 0 && "$EFFECTIVE_MODE" == "strict" ]]; then
    EXIT_CODE_FINAL=1
fi

# Spec 333: write evidence artifact (skipped silently if EVIDENCE_DIR is empty).
# Spec 504: cap_tripped:false on the normal path — a completed scan, by construction.
SUMMARY_JSON_AUTH="{\"actionable\":${ACTIONABLE},\"scanned_files\":${SCANNED_FILES},\"action_count\":${#ACTION_NAMES[@]},\"violations_total\":${#VIOLATION_FILES[@]},\"elapsed_seconds\":${ELAPSED},\"cap_tripped\":false,\"work_units\":${WORK_UNITS},\"work_unit_cap\":${SCAN_WORK_UNIT_CAP}}"
write_evidence_artifact "validate-authorization-rules" "$AGENTS_MD" "$EFFECTIVE_MODE" "$RESULT_LABEL" "$EXIT_CODE_FINAL" "$GATE_BUF" "$SUMMARY_JSON_AUTH"

exit $EXIT_CODE_FINAL

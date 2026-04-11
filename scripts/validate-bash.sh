#!/usr/bin/env bash
# validate-bash.sh — Strip Jinja2 tags and run shellcheck on all FORGE template bash scripts.
# Part of Spec 008 — Shellcheck Validation for FORGE Bash Scripts.
#
# Usage: scripts/validate-bash.sh [--verbose] [--portability]
#
# Requires: shellcheck (apt, brew, scoop, or pip install shellcheck-py)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_DIR="${REPO_ROOT}/template/.forge"
VERBOSE=""
PORTABILITY=""
for arg in "$@"; do
    case "$arg" in
        --verbose)     VERBOSE="--verbose" ;;
        --portability) PORTABILITY="--portability" ;;
    esac
done

# Verify shellcheck is available — check PATH first, then fall back to common locations
SHELLCHECK=""
if command -v shellcheck &>/dev/null; then
    SHELLCHECK="shellcheck"
else
    # Build candidate list from environment-based paths (no hardcoded user dirs)
    candidates=()
    # pip install locations (Windows)
    if [[ -n "${APPDATA:-}" ]]; then
        for pydir in "$APPDATA"/Python/Python*/Scripts; do
            [[ -d "$pydir" ]] && candidates+=("$pydir/shellcheck.exe")
        done
    fi
    # pip install location (Linux/Mac)
    candidates+=("$HOME/.local/bin/shellcheck")
    # Scoop install location (Windows)
    [[ -n "${HOME:-}" ]] && candidates+=("$HOME/scoop/shims/shellcheck.exe")

    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate" ]]; then
            SHELLCHECK="$candidate"
            break
        fi
    done
    if [[ -z "$SHELLCHECK" ]]; then
        echo "ERROR: shellcheck not found. Install via: apt install shellcheck | brew install shellcheck | pip install shellcheck-py"
        exit 1
    fi
fi

# Collect all .sh files
mapfile -t scripts < <(find "$TEMPLATE_DIR" -name "*.sh" -type f | sort)

if [[ ${#scripts[@]} -eq 0 ]]; then
    echo "ERROR: No .sh files found in $TEMPLATE_DIR"
    exit 1
fi

echo "Found ${#scripts[@]} bash scripts in template .forge/"
echo "shellcheck version: $("$SHELLCHECK" --version | head -2 | tail -1)"
echo "---"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Parse .shellcheckrc for CLI flags (shellcheck may not find rc file for temp files on Windows)
SHELLCHECK_ARGS=()
if [[ -f "$REPO_ROOT/.shellcheckrc" ]]; then
    while IFS= read -r line; do
        # Skip comments and blank lines
        if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
        if [[ -z "${line// /}" ]]; then continue; fi
        key="${line%%=*}"
        value="${line#*=}"
        # Trim whitespace
        key="${key## }"; key="${key%% }"
        value="${value## }"; value="${value%% }"
        case "$key" in
            severity) SHELLCHECK_ARGS+=("--severity=$value") ;;
            disable)  SHELLCHECK_ARGS+=("--exclude=$value") ;;
            shell)    SHELLCHECK_ARGS+=("--shell=$value") ;;
        esac
    done < "$REPO_ROOT/.shellcheckrc"
fi

pass=0
fail=0
errors=""

for script in "${scripts[@]}"; do
    relative="${script#"$REPO_ROOT"/}"
    # Strip Jinja2 {% raw %} and {% endraw %} tags — they're not bash syntax
    cleaned="$tmpdir/$(basename "$script")"
    sed -e '/^[[:space:]]*{%[[:space:]]*raw[[:space:]]*%}/d' \
        -e '/^[[:space:]]*{%[[:space:]]*endraw[[:space:]]*%}/d' \
        "$script" > "$cleaned"

    sc_output="$("$SHELLCHECK" "${SHELLCHECK_ARGS[@]}" --source-path="$tmpdir" "$cleaned" 2>&1)" && sc_exit=0 || sc_exit=$?

    if [[ $sc_exit -eq 0 ]]; then
        if [[ "$VERBOSE" == "--verbose" ]]; then
            echo "PASS: $relative"
        fi
        (( pass++ )) || true
    else
        echo "FAIL: $relative"
        echo "$sc_output"
        (( fail++ )) || true
        errors+="  - $relative"$'\n'
    fi
done

echo "---"
echo "Results: $pass passed, $fail failed (${#scripts[@]} total)"

if [[ $fail -gt 0 ]]; then
    echo ""
    echo "Failed scripts:"
    echo "$errors"
    exit 1
fi

echo "All scripts pass shellcheck."

# --- Portability checks (--portability flag) ---
if [[ "$PORTABILITY" == "--portability" ]]; then
    echo ""
    echo "=== Portability checks ==="

    port_warnings=0
    port_details=""

    for script in "${scripts[@]}"; do
        relative="${script#"$REPO_ROOT"/}"

        # Check 1: Hardcoded /tmp paths (should use $TMPDIR or ${TMPDIR:-${TEMP:-/tmp}})
        # Only flag standalone /tmp/ at start of a path (not project-relative like ${DIR}/tmp/)
        # Exclude: comment lines, lines with TMPDIR/TEMP fallback, path-conversion code
        while IFS= read -r match; do
            [[ -z "$match" ]] && continue
            lineno="${match%%:*}"
            line_content="${match#*:}"
            # Skip lines that are part of /tmp path conversion logic (e.g., == /tmp/*, #/tmp/)
            [[ "$line_content" =~ /tmp/\* ]] && continue
            [[ "$line_content" =~ \#/tmp/ ]] && continue
            port_details+="  WARN: $relative:$lineno -- hardcoded /tmp path (use \$TMPDIR or \${TMPDIR:-\${TEMP:-/tmp}})"$'\n'
            (( port_warnings++ )) || true
        done < <(grep -nE '(^|[[:space:]="])/tmp/' "$script" \
            | grep -v '^[0-9]*:[[:space:]]*#' \
            | grep -v 'TMPDIR' \
            | grep -v 'TEMP' || true)

        # Check 2: Platform-specific absolute path assumptions (/usr/local/bin, /opt/, /etc/)
        # Exclude comment lines
        while IFS= read -r match; do
            [[ -z "$match" ]] && continue
            lineno="${match%%:*}"
            port_details+="  WARN: $relative:$lineno -- platform-specific path (may not exist on all systems)"$'\n'
            (( port_warnings++ )) || true
        done < <(grep -n -E '/(usr/local/bin|opt/|etc/)' "$script" \
            | grep -v '^[0-9]*:[[:space:]]*#' || true)

        # Check 3: Hardcoded user-specific absolute paths
        # Flags /home/<user>, /Users/<user>, C:\, c:/, D:\, d:/ paths
        # Excludes system paths (/tmp, /dev/null, /usr, /bin, /etc, /c/Program Files)
        while IFS= read -r match; do
            [[ -z "$match" ]] && continue
            lineno="${match%%:*}"
            line_content="${match#*:}"
            # Skip comment lines
            [[ "$line_content" =~ ^[[:space:]]*# ]] && continue
            port_details+="  WARN: $relative:$lineno -- hardcoded user-specific absolute path (use env vars or relative paths)"$'\n'
            (( port_warnings++ )) || true
        done < <(grep -nE '(/home/[a-zA-Z]|/Users/[a-zA-Z]|[Cc]:\\[A-Za-z]|[Cc]:/[A-Za-z]|[Dd]:\\[A-Za-z]|[Dd]:/[A-Za-z])' "$script" \
            | grep -v '^[0-9]*:[[:space:]]*#' \
            | grep -vE '/(tmp|dev/null|usr|bin|etc|c/Program)' || true)

        # Check 4: Unquoted command substitutions -- $(cmd) without surrounding quotes
        # Safe contexts (no word splitting): variable assignments, [[ ]] tests, $(( )) arithmetic
        # Only flags $(cmd) used as a bare command argument where word splitting applies
        while IFS= read -r match; do
            [[ -z "$match" ]] && continue
            lineno="${match%%:*}"
            line_content="${match#*:}"
            # Skip comment lines
            [[ "$line_content" =~ ^[[:space:]]*# ]] && continue
            # Skip arithmetic $(( )) -- not command substitution
            [[ "$line_content" =~ \$\(\( ]] && continue
            # Skip lines inside [[ ]] -- no word splitting in [[ ]]
            [[ "$line_content" =~ \[\[ ]] && continue
            # Skip variable assignments: VAR=$(cmd) is safe (no word splitting on RHS)
            # Matches: VAR=$(, local VAR=$(, export VAR=$(, readonly VAR=$(
            [[ "$line_content" =~ [a-zA-Z_][a-zA-Z0-9_]*=\$\( ]] && continue
            # Skip heredoc content (lines that look like key: $(cmd) patterns)
            [[ "$line_content" =~ ^[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]+\$\( ]] && continue
            # Check if $( is inside double quotes (safe)
            before_subst="${line_content%%\$(*}"
            stripped="${before_subst//[^\"]/}"
            if (( ${#stripped} % 2 == 0 )); then
                port_details+="  WARN: $relative:$lineno -- unquoted command substitution \$(cmd) (quote to prevent word splitting)"$'\n'
                (( port_warnings++ )) || true
            fi
        done < <(grep -nF '$(' "$script" || true)

    done

    echo "Found $port_warnings portability warning(s)."
    if [[ $port_warnings -gt 0 ]]; then
        echo ""
        echo "$port_details"
        exit 1
    fi
    echo "All scripts pass portability checks."
fi

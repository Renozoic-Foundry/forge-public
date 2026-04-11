#!/usr/bin/env bash
# validate-command-sync.sh — Verify command file parity and content sync.
# Phase 1 (Spec 132): .forge/commands/ vs .claude/commands/ file-existence parity within template/.
# Phase 2 (Spec 195): FORGE own-copies vs template copies content comparison.
# Phase 3 (Spec 195): Signal reference validation in command files.
#
# Usage: scripts/validate-command-sync.sh [--verbose] [--content] [--signals] [--all]
#   --verbose   Show per-file results
#   --content   Run Phase 2 (content comparison)
#   --signals   Run Phase 3 (signal reference validation)
#   --all       Run all phases (default if no phase flags given)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_DIR="${REPO_ROOT}/template"
FORGE_CLAUDE_DIR="${REPO_ROOT}/.claude/commands"
FORGE_FORGE_DIR="${REPO_ROOT}/.forge/commands"
TEMPLATE_CLAUDE_DIR="${TEMPLATE_DIR}/.claude/commands"
TEMPLATE_FORGE_DIR="${TEMPLATE_DIR}/.forge/commands"
SIGNALS_FILE="${REPO_ROOT}/docs/sessions/signals.md"
EXPECTED_DRIFT_FILE="${REPO_ROOT}/.forge/state/expected-command-drift.txt"

VERBOSE=""
RUN_CONTENT=""
RUN_SIGNALS=""
RUN_ALL=""
for arg in "$@"; do
    case "$arg" in
        --verbose) VERBOSE="1" ;;
        --content) RUN_CONTENT="1" ;;
        --signals) RUN_SIGNALS="1" ;;
        --all) RUN_ALL="1" ;;
    esac
done

# Default: run all phases if no specific phase flag given
if [[ -z "$RUN_CONTENT" && -z "$RUN_SIGNALS" ]]; then
    RUN_ALL="1"
fi
if [[ -n "$RUN_ALL" ]]; then
    RUN_CONTENT="1"
    RUN_SIGNALS="1"
fi

errors=0
warnings=0

# Load expected drift list (one basename per line, lines starting with # are comments)
declare -A expected_drift
if [[ -f "$EXPECTED_DRIFT_FILE" ]]; then
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        expected_drift["$line"]=1
    done < "$EXPECTED_DRIFT_FILE"
fi

# ============================================================
# Phase 1 — File-existence parity within template/ (Spec 132)
# ============================================================
echo "=== Phase 1: File-existence parity (template/.forge vs template/.claude) ==="

if [[ ! -d "$TEMPLATE_FORGE_DIR" ]]; then
    echo "ERROR: template/.forge/commands/ not found"
    exit 1
fi
if [[ ! -d "$TEMPLATE_CLAUDE_DIR" ]]; then
    echo "ERROR: template/.claude/commands/ not found"
    exit 1
fi

forge_files=$(cd "$TEMPLATE_FORGE_DIR" && find . -maxdepth 1 \( -name '*.md' -o -name '*.md.jinja' \) | sed 's|^\./||' | sort)
claude_files=$(cd "$TEMPLATE_CLAUDE_DIR" && find . -maxdepth 1 \( -name '*.md' -o -name '*.md.jinja' \) | sed 's|^\./||' | sort)

only_forge=$(comm -23 <(echo "$forge_files") <(echo "$claude_files")) || true
if [[ -n "$only_forge" ]]; then
    echo "  DRIFT: Files only in template/.forge/commands/:"
    echo "$only_forge" | while IFS= read -r f; do echo "    - $f"; done
    errors=$((errors + 1))
fi

only_claude=$(comm -13 <(echo "$forge_files") <(echo "$claude_files")) || true
if [[ -n "$only_claude" ]]; then
    echo "  DRIFT: Files only in template/.claude/commands/:"
    echo "$only_claude" | while IFS= read -r f; do echo "    - $f"; done
    errors=$((errors + 1))
fi

matched_count=$(comm -12 <(echo "$forge_files") <(echo "$claude_files") | wc -l)
echo "  Matched: ${matched_count} files in both template directories."

if [[ -z "$only_forge" && -z "$only_claude" ]]; then
    echo "  Phase 1: PASS"
else
    echo "  Phase 1: FAIL"
fi

# ============================================================
# Phase 2 — Content comparison: FORGE own-copies vs template (Spec 195)
# ============================================================
if [[ -n "$RUN_CONTENT" ]]; then
    echo ""
    echo "=== Phase 2: Content comparison (FORGE own-copies vs template) ==="

    content_errors=0
    content_expected=0
    content_clean=0

    compare_dirs() {
        local own_dir="$1"
        local tmpl_dir="$2"
        local label="$3"

        if [[ ! -d "$own_dir" || ! -d "$tmpl_dir" ]]; then
            echo "  SKIP: $label — directory missing"
            return
        fi

        for own_file in "$own_dir"/*.md; do
            [[ -f "$own_file" ]] || continue
            local base
            base=$(basename "$own_file")
            local tmpl_file="${tmpl_dir}/${base}"

            if [[ ! -f "$tmpl_file" ]]; then
                # File exists in FORGE but not template — may be FORGE-only
                if [[ -n "$VERBOSE" ]]; then
                    echo "  INFO: $label/$base — FORGE-only (no template counterpart)"
                fi
                continue
            fi

            # Compare with CRLF normalization
            local diff_output
            diff_output=$(diff --strip-trailing-cr "$own_file" "$tmpl_file" 2>/dev/null) || true

            if [[ -z "$diff_output" ]]; then
                content_clean=$((content_clean + 1))
                if [[ -n "$VERBOSE" ]]; then
                    echo "  OK: $label/$base"
                fi
            else
                local diff_lines
                diff_lines=$(echo "$diff_output" | grep -c "^[<>]" || true)

                if [[ -n "${expected_drift[$base]+_}" ]]; then
                    content_expected=$((content_expected + 1))
                    if [[ -n "$VERBOSE" ]]; then
                        echo "  EXPECTED: $label/$base ($diff_lines lines differ — listed in expected-command-drift.txt)"
                    fi
                else
                    content_errors=$((content_errors + 1))
                    echo "  DRIFT: $label/$base ($diff_lines lines differ)"
                    if [[ -n "$VERBOSE" ]]; then
                        echo "$diff_output" | head -20 | sed 's/^/    /'
                        local total_diff
                        total_diff=$(echo "$diff_output" | wc -l)
                        if [[ "$total_diff" -gt 20 ]]; then
                            echo "    ... ($((total_diff - 20)) more lines)"
                        fi
                    fi
                fi
            fi
        done
    }

    compare_dirs "$FORGE_CLAUDE_DIR" "$TEMPLATE_CLAUDE_DIR" ".claude/commands"
    compare_dirs "$FORGE_FORGE_DIR" "$TEMPLATE_FORGE_DIR" ".forge/commands"

    echo "  Clean: $content_clean | Expected drift: $content_expected | Unexpected drift: $content_errors"

    if [[ "$content_errors" -gt 0 ]]; then
        echo "  Phase 2: FAIL ($content_errors files with unexpected drift)"
        errors=$((errors + content_errors))
    else
        echo "  Phase 2: PASS"
    fi
fi

# ============================================================
# Phase 3 — Signal reference validation (Spec 195)
# ============================================================
if [[ -n "$RUN_SIGNALS" ]]; then
    echo ""
    echo "=== Phase 3: Signal reference validation ==="

    sig_errors=0
    sig_checked=0

    if [[ ! -f "$SIGNALS_FILE" ]]; then
        echo "  SKIP: signals.md not found at $SIGNALS_FILE"
    else
        # Collect all SIG references from command files
        # Handles both SIG-NNN-XX (alpha suffix) and SIG-NNN-NN (numeric suffix)
        declare -A sig_refs
        for dir in "$FORGE_CLAUDE_DIR" "$FORGE_FORGE_DIR" "$TEMPLATE_CLAUDE_DIR" "$TEMPLATE_FORGE_DIR"; do
            [[ -d "$dir" ]] || continue
            for cmd_file in "$dir"/*.md; do
                [[ -f "$cmd_file" ]] || continue
                while IFS= read -r sig; do
                    if [[ -n "$sig" ]]; then
                        # Store sig -> file mapping (last file wins, but we just need the ref)
                        rel_path="${cmd_file#"$REPO_ROOT"/}"
                        sig_refs["$sig"]="${sig_refs[$sig]:-}${sig_refs[$sig]:+, }$rel_path"
                    fi
                done < <(grep -oE 'SIG-[0-9]+-[A-Za-z0-9]+' "$cmd_file" 2>/dev/null || true)
            done
        done

        for sig in "${!sig_refs[@]}"; do
            sig_checked=$((sig_checked + 1))
            if ! grep -qF "$sig" "$SIGNALS_FILE" 2>/dev/null; then
                echo "  MISSING: $sig (referenced in: ${sig_refs[$sig]})"
                sig_errors=$((sig_errors + 1))
            elif [[ -n "$VERBOSE" ]]; then
                echo "  OK: $sig"
            fi
        done

        echo "  Checked: $sig_checked references | Missing: $sig_errors"

        if [[ "$sig_errors" -gt 0 ]]; then
            echo "  Phase 3: FAIL ($sig_errors signal references not found in signals.md)"
            errors=$((errors + sig_errors))
        else
            echo "  Phase 3: PASS"
        fi
    fi
fi

# ============================================================
# Summary
# ============================================================
echo ""
if [[ "$errors" -gt 0 ]]; then
    echo "FAIL: $errors issue(s) detected. Review output above."
    exit 1
fi

echo "PASS: All checks passed."
exit 0

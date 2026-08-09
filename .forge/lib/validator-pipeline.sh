#!/usr/bin/env bash
# Spec 608 — single-sourced fortified-validator pipeline steps.
#
# Extracted from close.md Step 2d (5.a2-a5, c2) so /implement's inline-validation
# step and /close's Step 2d call the SAME deterministic pre/post-check logic
# instead of each command file re-authoring its own copy (Spec 608 AC4).
#
# The actual validator subagent spawn + JSON-verdict parsing stays in each
# calling command body — only the orchestrator (main loop) can invoke the
# Task/Agent tool, so that part cannot be pushed into a plain script. This
# script covers everything deterministic: scanner pre-check, spec-copy
# redaction, runnable-AC extraction, bounded evidence-excerpt formatting, and
# the post-check invocation.
#
# Usage:
#   validator-pipeline.sh prepare <spec-file> <evidence-dir>
#   validator-pipeline.sh evidence-excerpt <evidence-dir> [spec-file]
#   validator-pipeline.sh postcheck <spec-file> <report-json> <scanner-json>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$FORGE_ROOT/.." && pwd)}"

# Spec 663 — evidence-KIND exclusions declared by an acceptance criterion.
#
# Spec 548's post-check verifies evidence EXISTS for a runnable-command AC; it
# never checks whether the evidence is the KIND the criterion asked for. When an
# AC explicitly forbids a source ("shellcheck clean ... do not rely on
# validate-bash.sh coverage"), the orchestrator omits that source from the
# criterion's injected block rather than placing it in front of the validator
# and trusting the validator to disregard it.
#
# Only the three explicit forms the corpus actually uses are detected:
#   "do not rely on X" | "not via X" | "excluding X"
# and X must be file/path-shaped (contains `.` or `/`). Both restrictions are
# deliberate (Spec 663 Out of scope): a criterion that excludes a source only by
# implication is out of reach and should say so plainly instead. This never
# adjudicates whether evidence is TRUTHFUL — only mechanically-checkable kind.
#
# Emits one `<ac-number><TAB><source>` line per detected exclusion.
ac_evidence_exclusions() {
  local spec="$1"
  awk '
    function emit(num, text,   lt, rest, tok, n, arr) {
      if (num == "" || text == "") return
      lt = tolower(text)
      while (match(lt, /(do not rely on|not via|excluding)[ \t]+(the[ \t]+|a[ \t]+|an[ \t]+)?`?[a-z0-9_.\/-]+/)) {
        rest = substr(lt, RSTART, RLENGTH)
        lt = substr(lt, RSTART + RLENGTH)
        n = split(rest, arr, /[ \t]+/)
        tok = arr[n]
        gsub(/`/, "", tok)
        sub(/[.\/]+$/, "", tok)
        if (tok ~ /[.\/]/) print num "\t" tok
      }
    }
    tolower($0) ~ /^## (acceptance criteria|definition of done)/ { p = 1; next }
    /^## / { if (p) { emit(num, text); num = ""; text = ""; p = 0 } next }
    p {
      if (match($0, /^[0-9]+\.[ \t]+/)) {
        emit(num, text)
        num = substr($0, 1, index($0, ".") - 1)
        text = substr($0, RSTART + RLENGTH)
      } else if (num != "") {
        line = $0
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line != "") text = text " " line
      }
    }
    END { emit(num, text) }
  ' "$spec"
}

cmd="${1:-}"

case "$cmd" in
  prepare)
    spec_file="${2:?usage: prepare <spec-file> <evidence-dir>}"
    evidence_dir="${3:?usage: prepare <spec-file> <evidence-dir>}"
    mkdir -p "$evidence_dir"

    # a2 — Stage-1 scanner pre-check (Spec 540): flagged behavioral/browser-verb ACs.
    "$PLUGIN_ROOT/.forge/lib/ac-pattern-scanner.sh" "$spec_file" > "$evidence_dir/flagged-acs.json"

    # Spec 618 — could-not-check: section_found:false means no recognized AC heading
    # exists and the scan read nothing; the empty flagged_acs above is then meaningless.
    # Operator-visible warning, never a silent pass (gate texts key on this state too).
    if grep -q '"section_found":false' "$evidence_dir/flagged-acs.json"; then
      echo "WARNING: AC-scanner could-not-check — $spec_file has no recognized acceptance-criteria heading (## Acceptance Criteria / ## Definition of done, any case); the Stage-1 browser-verb pre-check read no ACs." >&2
    fi

    # a3 — Spec-copy redaction (Spec 548): implementer-authored proof sections stripped.
    slug="$(basename "$spec_file" .md)"
    "$PLUGIN_ROOT/.forge/bin/forge-py" "$PLUGIN_ROOT/.forge/lib/spec_redact.py" \
      "$spec_file" -o "$evidence_dir/${slug}-redacted.md"

    # a3 (cont.) — runnable-command AC list (Spec 550 shared matcher).
    "$PLUGIN_ROOT/.forge/lib/ac-pattern-scanner.sh" "$spec_file" runnable \
      > "$evidence_dir/runnable-acs.json"

    echo "prepared: $evidence_dir/flagged-acs.json $evidence_dir/${slug}-redacted.md $evidence_dir/runnable-acs.json"
    ;;

  evidence-excerpt)
    evidence_dir="${2:?usage: evidence-excerpt <evidence-dir> [spec-file]}"
    excl_spec="${3:-}"
    # a5 — Evidence visibility injection (Spec 583): listing + bounded excerpt.
    # Bounding IS the control (Spec 581 CISO constraint) — never widen the pattern set.
    echo "--- ls -R $evidence_dir ---"
    ls -R "$evidence_dir"

    # Spec 663 — evidence-KIND enforcement. Without a spec-file argument the
    # output is byte-identical to the pre-663 behaviour.
    excl_map=""
    if [[ -n "$excl_spec" && -f "$excl_spec" ]]; then
      excl_lines="$(ac_evidence_exclusions "$excl_spec")"
      if [[ -n "$excl_lines" ]]; then
        echo "--- evidence-kind exclusions (Spec 663) ---"
        while IFS=$'\t' read -r excl_ac excl_src; do
          if [[ -z "$excl_ac" ]]; then continue; fi
          excl_map="${excl_map}${excl_ac}=${excl_src};"
          echo "AC${excl_ac} explicitly excludes evidence source ${excl_src}. Lines citing it have been WITHHELD from AC${excl_ac}'s excerpt below and must not be cited for AC${excl_ac}. Their absence is a deliberate orchestrator omission, NOT proof that no such evidence exists."
        done <<< "$excl_lines"
      fi
    fi

    echo "--- bounded excerpt (40 lines / 4KB cap) ---"
    grep -hE '^=== |exit code: [0-9-]+|^GATE \[|^(PASS|FAIL)[: ]' \
      "$evidence_dir"/*.log "$evidence_dir"/*.txt 2>/dev/null \
      | awk -v MAP="$excl_map" '
          function redact(s, needle,   out, p, ls, ln) {
            ln = tolower(needle); ls = tolower(s); out = ""
            while ((p = index(ls, ln)) > 0) {
              out = out substr(s, 1, p - 1) "[WITHHELD-663]"
              s = substr(s, p + length(needle)); ls = tolower(s)
            }
            return out s
          }
          BEGIN {
            n = split(MAP, pairs, ";")
            for (i = 1; i <= n; i++) {
              if (pairs[i] == "") continue
              eq = index(pairs[i], "=")
              exac[++k] = substr(pairs[i], 1, eq - 1)
              exsrc[k] = substr(pairs[i], eq + 1)
            }
          }
          {
            hdr = match($0, /^=== AC[0-9]+/)
            if (hdr) cur = substr($0, 7, RLENGTH - 6)
            if (cur != "") {
              for (i = 1; i <= k; i++) {
                if (exac[i] != cur) continue
                if (index(tolower($0), tolower(exsrc[i])) == 0) continue
                # The AC header carries the segment tag — redact the source in
                # place so segmentation survives; any other line is dropped.
                if (hdr) { $0 = redact($0, exsrc[i]); continue }
                # The marker deliberately does NOT repeat the source name —
                # naming it here would put the excluded source back into the
                # criterion block the omission just cleared. The exclusions
                # notice above the excerpt carries the name and the reason.
                printf "[WITHHELD AC%s (Spec 663): a line citing the evidence source this criterion excludes was removed — see the evidence-kind exclusions notice above]\n", cur
                next
              }
            }
            print
          }
        ' \
      | head -40 | cut -c1-200 || true
    ;;

  postcheck)
    spec_file="${2:?usage: postcheck <spec-file> <report-json> <scanner-json>}"
    report_json="${3:?usage: postcheck <spec-file> <report-json> <scanner-json>}"
    scanner_json="${4:?usage: postcheck <spec-file> <report-json> <scanner-json>}"
    "$PLUGIN_ROOT/.forge/bin/forge-py" "$PLUGIN_ROOT/.forge/lib/validator_evidence_postcheck.py" \
      --spec "$spec_file" --report "$report_json" --scanner-json "$scanner_json"
    ;;

  *)
    echo "usage: validator-pipeline.sh {prepare|evidence-excerpt|postcheck} ..." >&2
    exit 2
    ;;
esac

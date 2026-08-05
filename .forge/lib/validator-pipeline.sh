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
#   validator-pipeline.sh evidence-excerpt <evidence-dir>
#   validator-pipeline.sh postcheck <spec-file> <report-json> <scanner-json>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$FORGE_ROOT/.." && pwd)}"

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
    evidence_dir="${2:?usage: evidence-excerpt <evidence-dir>}"
    # a5 — Evidence visibility injection (Spec 583): listing + bounded excerpt.
    # Bounding IS the control (Spec 581 CISO constraint) — never widen the pattern set.
    echo "--- ls -R $evidence_dir ---"
    ls -R "$evidence_dir"
    echo "--- bounded excerpt (40 lines / 4KB cap) ---"
    grep -hE '^=== |exit code: [0-9-]+|^GATE \[|^(PASS|FAIL)[: ]' \
      "$evidence_dir"/*.log "$evidence_dir"/*.txt 2>/dev/null \
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

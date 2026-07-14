#!/usr/bin/env python3
"""Spec 548 — validator execution-evidence post-check.

Mechanical check on the validator's JSON report: any acceptance criterion the
shared AC-pattern scanner (mode=runnable — Spec 550 matcher infrastructure, the
ONLY command-detection source; this script contains NO detection heuristic of
its own) flags as naming a runnable command must carry execution evidence
(exit code / output excerpt) in its criterion result. A PASS without it is
downgraded: this script exits 1 and names the offending AC, which the /close
gate reports as `GATE [validator]: FAIL`.

Honesty note (Spec 548 AC4): this verifies evidence PRESENCE, not truthfulness.
It is a lint-level speed bump against validator drift, not a hard trust
boundary. Evidence-to-tool-call trace binding is the named follow-up.

Usage:
  forge-py validator_evidence_postcheck.py --spec <spec.md> \
      --report <validator-report.json> --scanner-json <scanner-output.json>

  --scanner-json is the verbatim stdout of:
      ac-pattern-scanner.sh <spec.md> runnable
  (pass "-" to read it from stdin)

Output: JSON verdict on stdout:
  {"postcheck":"PASS"|"FAIL","failures":[{"ac_number":N,"reason":"..."}]}
Exit 0 = PASS, 1 = FAIL, 2 = usage/input error.
"""

import argparse
import json
import re
import sys

# Tolerated execution-evidence variants (Spec 548 AC5 — false-FAIL bound).
# Illustrative-but-documented list; extend here when a truthful phrasing
# trips a false FAIL (one-shot retry contract keeps the cost visible).
EVIDENCE_PATTERNS = [
    r"exit (code|status)[:= ]*-?\d+",
    r"→\s*\d+",                      # "→ 0"
    r"\b\d+\s+(PASS|pass(ed|es)?)\b",     # "12 PASS, 0 FAIL" / "37 passed"
    r"\bResult:\s*\d+\s*PASS",
    r"\b\d+/\d+\b",                       # "124/124"
    r"\b(all|\d+) tests? pass(ed)?\b",
    r"\b\d+ passed, \d+ failed\b",
    r"found 0 vulnerabilities",
]

# Evidence-blind violation (SIG-532-04 / SIG-535-02): a criterion note citing
# the implementer's Evidence section as proof is never execution evidence.
EVIDENCE_BLIND_RE = re.compile(r"(per|from|see|cit\w*|spec'?s?)\s+(the\s+)?spec\s+evidence\s+section|\bevidence\s+section\b", re.I)


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s or "").strip().lower()


def find_entry(report_entries, ac_number, ac_text):
    """Match a flagged AC to its criteria_results entry by text overlap."""
    key = norm(ac_text)[:40]
    for e in report_entries:
        crit = norm(e.get("criterion", ""))
        if key and (key in crit or crit[:40] in norm(ac_text)):
            return e
        # fallback: explicit AC-number reference in the criterion text
        if re.search(rf"\bAC\s*{ac_number}\b", e.get("criterion", ""), re.I):
            return e
    return None


def has_execution_evidence(entry, report):
    # Spec 556 (DA critical): per-criterion evidence ONLY. The report-level
    # `test_output` field is shared across every criterion, so including it here
    # let one evidence block satisfy every flagged runnable AC even if only one
    # command ran. Bind each runnable AC's PASS to its OWN evidence.
    # `report` param retained for call-site stability but no longer read.
    blob = " ".join(
        str(x) for x in (entry.get("notes", ""), entry.get("test_output", ""))
    )
    return any(re.search(p, blob, re.I) for p in EVIDENCE_PATTERNS)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--report", required=True)
    ap.add_argument("--scanner-json", required=True)
    args = ap.parse_args(argv)

    try:
        with open(args.report, encoding="utf-8", errors="replace") as f:
            report = json.load(f)
        if args.scanner_json == "-":
            scanner = json.load(sys.stdin)
        else:
            with open(args.scanner_json, encoding="utf-8", errors="replace") as f:
                scanner = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"validator_evidence_postcheck: input error: {e}", file=sys.stderr)
        return 2

    flagged = scanner.get("flagged_acs", [])
    entries = report.get("criteria_results", [])
    failures = []

    for ac in flagged:
        n, text = ac.get("ac_number"), ac.get("text", "")
        entry = find_entry(entries, n, text)
        if entry is None:
            failures.append({
                "ac_number": n,
                "reason": "runnable-command AC has no matching criterion result in the validator report",
            })
            continue
        if str(entry.get("result", "")).upper() != "PASS":
            continue  # validator already failing it; post-check guards PASS-without-proof
        notes_blob = f"{entry.get('notes', '')} {entry.get('method', '')}"
        if EVIDENCE_BLIND_RE.search(notes_blob):
            failures.append({
                "ac_number": n,
                "reason": "evidence-blind violation: criterion PASS cites the implementer Evidence section as proof",
            })
            continue
        if not has_execution_evidence(entry, report):
            failures.append({
                "ac_number": n,
                "reason": "missing execution evidence: PASS on a runnable-command AC without exit code / output excerpt (tolerated variants documented in EVIDENCE_PATTERNS)",
            })

    verdict = {"postcheck": "FAIL" if failures else "PASS", "failures": failures}
    print(json.dumps(verdict))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

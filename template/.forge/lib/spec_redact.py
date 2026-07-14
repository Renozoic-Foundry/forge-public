#!/usr/bin/env python3
"""Spec 548 — validator spec-copy redaction.

Strips implementer-authored proof sections from a spec file so the validator
subagent cannot anchor on them (evidence-blind rule, mechanically enforced):
  - ## Evidence            (and all its subsections, e.g. ### Live-smoke evidence)
  - ## Disposition Record
  - ## Devil's Advocate Findings

Everything else passes through byte-for-byte. A single HTML comment marks each
removal site so the validator knows the section existed but was withheld.

Usage: forge-py spec_redact.py <spec-file>           (redacted copy on stdout)
       forge-py spec_redact.py <spec-file> -o <out>  (write to file)

Exit 0 on success; exit 2 on unreadable input.
"""

import sys

REDACT_HEADINGS = (
    "## Evidence",
    "## Disposition Record",
    "## Devil's Advocate Findings",
)

MARKER = "<!-- spec-redact: implementer-authored proof section removed for independent validation (Spec 548) -->"


def redact(text: str) -> str:
    out = []
    skipping = False
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\n").rstrip("\r")
        if stripped.startswith("## "):
            if any(stripped == h or stripped.startswith(h + " ") for h in REDACT_HEADINGS):
                skipping = True
                out.append(MARKER + "\n")
                continue
            skipping = False
        if not skipping:
            out.append(line)
    return "".join(out)


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    src = argv[0]
    out_path = None
    if len(argv) >= 3 and argv[1] == "-o":
        out_path = argv[2]
    try:
        with open(src, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as e:
        print(f"spec_redact: cannot read {src}: {e}", file=sys.stderr)
        return 2
    result = redact(text)
    if out_path:
        with open(out_path, "w", encoding="utf-8", newline="") as f:
            f.write(result)
    else:
        sys.stdout.write(result)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

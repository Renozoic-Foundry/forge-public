#!/usr/bin/env python3
"""FORGE red-main CI advisory helper (Spec 549).

Emits exactly ONE advisory line when the most recent main-branch run of any
GitHub workflow concluded ``failure``; emits NOTHING when every workflow's
latest run is green. Consumed by ``/now`` (a silent-by-default count-style
surface, same contract family as the aging-drafts / release-eligible lines).

Fail-silent contract (Spec 549 DA finding): /now is the highest-frequency
command and must not take an external-dependency risk — ANY error (gh CLI
missing, unauthenticated, network down, malformed JSON) exits 0 with no
output. Silence therefore means "green or unknown", never an error surface.

Usage:
    forge-py .forge/lib/ci_status.py                 # live: runs gh run list
    forge-py .forge/lib/ci_status.py --from-file F   # fixture: parse F instead

Live source:
    gh run list --branch main --limit 20 --json workflowName,conclusion

Logic: runs arrive newest-first; the first entry per workflowName with a
non-empty conclusion is that workflow's latest completed run (in-progress runs
have conclusion "" and are skipped). Any latest-completed conclusion of
``failure`` puts that workflow on the advisory line.
"""

import json
import subprocess
import sys

ADVISORY_PREFIX = "⚠ main CI red:"


def latest_conclusions(runs):
    """Map workflowName -> latest completed conclusion (newest-first input)."""
    latest = {}
    for run in runs:
        name = run.get("workflowName")
        conclusion = run.get("conclusion")
        if not name or not conclusion:
            continue  # unnamed or still in progress
        if name not in latest:
            latest[name] = conclusion
    return latest


def advisory_line(runs):
    """Return the one-line advisory, or '' when all latest runs are green."""
    red = sorted(
        name
        for name, conclusion in latest_conclusions(runs).items()
        if conclusion == "failure"
    )
    if not red:
        return ""
    return (
        f"{ADVISORY_PREFIX} {', '.join(red)} — latest main-branch run failed "
        f"(gh run list --branch main). Spec 549 advisory; closes merged past "
        f"red main are invisible without it."
    )


def main(argv):
    try:
        if len(argv) >= 2 and argv[0] == "--from-file":
            with open(argv[1], encoding="utf-8") as fh:
                runs = json.load(fh)
        else:
            out = subprocess.run(
                [
                    "gh", "run", "list", "--branch", "main", "--limit", "20",
                    "--json", "workflowName,conclusion",
                ],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if out.returncode != 0:
                return 0  # fail-silent: gh error/unauthenticated
            runs = json.loads(out.stdout)
        line = advisory_line(runs)
        if line:
            print(line)
    except Exception:
        return 0  # fail-silent: gh missing, network, bad JSON, unreadable file
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

"""FORGE repro-provenance git-sha resolution helper (Spec 620, Req 11).

Tiny, deliberately separate from repro_provenance.py so the comparator module
stays subprocess-free (AC 3). This helper does exactly two things:

1. Hex-shape guard (argument-injection): a candidate sha must match
   ^[0-9a-f]{7,64}$ BEFORE being passed to git. Non-matching values are
   rejected without ever reaching a git invocation.
2. Commit-type resolution: `git cat-file -e <sha>^{commit}` — commit-type
   peeling, not mere object existence (DA delta pass).

Usage (via forge-py):
    repro_gitsha.py resolve <sha> [<sha>…]
        Prints each sha that resolves to a commit in this repository, one per
        line. Exit 0 always (the caller consumes the resolved set).

No parsing logic lives here — Req 5's one-comparator rule is untouched.
"""

from __future__ import annotations

import re
import subprocess
import sys

_SHA_SHAPE = re.compile(r"^[0-9a-f]{7,64}$")


def resolves_to_commit(sha: str) -> bool:
    if not _SHA_SHAPE.match(sha):
        return False  # injection guard: never reaches git
    try:
        proc = subprocess.run(
            ["git", "cat-file", "-e", f"{sha}^{{commit}}"],
            capture_output=True,
            timeout=30,
        )
        return proc.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def main(argv: list[str]) -> int:
    if not argv or argv[0] != "resolve" or len(argv) < 2:
        print("usage: repro_gitsha.py resolve <sha> [<sha>…]", file=sys.stderr)
        return 2
    for sha in argv[1:]:
        if resolves_to_commit(sha):
            print(sha)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

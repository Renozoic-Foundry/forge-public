#!/usr/bin/env python3
"""FORGE render-completeness invariant (Spec 494).

Shared loud-fail guard for derived-view renderers. Every source item that
SHOULD render must render; on mismatch the renderer exits nonzero and names the
dropped identifiers on stderr — it never emits a short artifact silently.

Root cause this closes: the silent-drop class (SIG-493-02, EA-309-P1) where a
parser/renderer produces a value that renders nothing and errors nothing. Spec
493 fixed the backlog parser for one drop shape; Spec 494 makes loud-fail the
universal renderer posture so the class cannot silently return — the safety
substrate for chained/parallel delivery (Spec 497), where no human eyes each
rendered artifact between specs.
"""

from __future__ import annotations

import sys
from collections.abc import Iterable

# Distinct nonzero exit so callers/CI can tell an incompleteness FAIL apart
# from an argparse/IO error (exit 2/1).
EXIT_INCOMPLETE = 3


def assert_complete(
    renderer_name: str,
    expected: int,
    emitted: int,
    dropped: Iterable[object] | None = None,
) -> None:
    """Assert a renderer emitted one output item per source item.

    renderer_name: human label used in the FAIL message.
    expected:      count of source items that SHOULD render.
    emitted:       count of output items actually produced.
    dropped:       optional identifiers (spec IDs / filenames / event keys) that
                   were expected but not emitted; named in the failure message.

    On match: returns None and writes nothing — the happy path is a silent
    no-op so byte-identical output (Spec 494 AC2) is preserved.

    On mismatch: writes a `GATE [render-completeness]: FAIL` line to stderr
    naming the dropped identifiers and raises SystemExit(EXIT_INCOMPLETE).
    """
    if emitted == expected:
        return
    ids = ", ".join(str(d) for d in (dropped or [])) or "(unidentified)"
    sys.stderr.write(
        f"GATE [render-completeness]: FAIL — {renderer_name} rendered "
        f"{emitted} of {expected} source item(s); {expected - emitted} dropped: "
        f"{ids}\n"
    )
    raise SystemExit(EXIT_INCOMPLETE)

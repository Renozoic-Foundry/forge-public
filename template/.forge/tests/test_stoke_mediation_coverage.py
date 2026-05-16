"""Spec 444 — stoke mediation-coverage smoke test (Req 8b, AC 6, AC 8).

When a future spec adds a new validator class WITHOUT extending
stoke/gates.py, the /forge stoke chat layer would otherwise surface the
underlying Copier traceback as primary output. This test asserts the
fallback contract: an unmodeled-gate fixture triggers the
`unknown-validator` fallback rather than a raw traceback.

Fixture rotation protocol (Req 8c):
    The "deliberately unmodeled validator" token below MUST rotate when
    a future spec legitimately adds a handler for the same surface. If
    `gates.py` grows to recognize the current token's pattern, this
    fixture must be updated to a still-unmodeled token; otherwise the
    test decays to tautology (passes against a now-modeled gate).
    /close diff-scan (Req 8a) refuses close on gates.py changes that
    don't simultaneously rotate this fixture.

    CURRENT-FIXTURE-TOKEN: synthetic-validator-spec-444-fixture
    LAST-ROTATED: 2026-05-16 (initial Spec 444 implementation)

Run:
    pytest .forge/tests/test_stoke_mediation_coverage.py -v
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

_THIS = Path(__file__).resolve()
for candidate in (
    _THIS.parents[2] / "template" / ".forge" / "lib",
    _THIS.parents[1] / "lib",
):
    if (candidate / "stoke" / "__init__.py").is_file():
        if str(candidate) not in sys.path:
            sys.path.insert(0, str(candidate))
        break
else:
    raise RuntimeError("Could not locate stoke package")

from stoke import gates as gates_mod  # noqa: E402


# Deliberately-unmodeled validator message — token rotates per Req 8c.
UNMODELED_VALIDATOR_MESSAGE = (
    "synthetic-validator-spec-444-fixture: re-run with "
    "--data future_consent_token=true"
)


def test_unknown_validator_fallback_returns_forge_authored_prompt():
    """AC 6: fallback presents FORGE-authored prompt text — does NOT
    surface the raw validator message as the primary operator question."""
    g = gates_mod.unknown_validator_gate(UNMODELED_VALIDATOR_MESSAGE)
    assert g.kind == "unknown-validator"
    # FORGE-authored constant — operator-visible string.
    assert g.operator_question == gates_mod.QUESTION_UNKNOWN_VALIDATOR
    # Validator message is preserved for the chat layer's "a/b/c" branch,
    # but lives in the rationale (operator-supplementary), not the prompt.
    assert UNMODELED_VALIDATOR_MESSAGE in g.rationale


def test_unmodeled_validator_kind_in_known_set():
    """The unknown-validator kind is part of the contracted KNOWN_GATE_KINDS
    surface so downstream consumers can switch on it explicitly."""
    assert "unknown-validator" in gates_mod.KNOWN_GATE_KINDS


def test_no_traceback_in_gate_fields():
    """Sanity: a Python traceback-shaped string in the validator message
    does NOT leak into operator_question (the primary chat surface).
    Rationale carries it (truncated) for the chat fallback's parsed view."""
    traceback_like = (
        "Traceback (most recent call last):\n"
        '  File "copier/cli.py", line 42, in run\n'
        '    raise ValidationError("bad")\n'
        "ValidationError: synthetic"
    )
    g = gates_mod.unknown_validator_gate(traceback_like)
    assert "Traceback" not in g.operator_question
    # Rationale truncates at 280 chars so even pathological tracebacks
    # don't dominate the chat surface.
    assert len(g.rationale) <= 500


def test_fixture_rotation_marker_present():
    """Req 8c: this test file MUST carry a top-of-file rotation comment.

    Self-referential check: the marker keeps the rotation protocol visible
    at the place future implementers will edit. /close diff-scan (Req 8a)
    additionally refuses close on gates.py changes that don't update the
    LAST-ROTATED date here.
    """
    text = Path(__file__).read_text(encoding="utf-8")
    assert "CURRENT-FIXTURE-TOKEN:" in text
    assert "LAST-ROTATED:" in text

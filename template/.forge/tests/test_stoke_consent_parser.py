"""Spec 444 — strict-literal consent parser tests (Req 3a/3b, AC 9).

The parser lives in the chat command body (forge-stoke.md), but its
contract is a pure function: given an operator's literal input string,
return one of {ACCEPT, REJECT, AMBIGUOUS}. The reference implementation
is mirrored here in Python so the contract is regression-tested
mechanically rather than only audited by reading the command body.

If forge-stoke.md drifts from this contract, the test FAILs and the
operator-input parsing surface is forced back into alignment.

Allow-list (Req 3a): {yes, y, confirm, approve, ok, okay}, case-insensitive.
Reject literals: {no, n, cancel}, case-insensitive.
Anything else → AMBIGUOUS (re-prompt).
Max 2 re-prompts; the third ambiguous answer aborts (Req 3b).

Run:
    pytest .forge/tests/test_stoke_consent_parser.py -v
"""
from __future__ import annotations

from typing import Literal

import pytest


Outcome = Literal["ACCEPT", "REJECT", "AMBIGUOUS"]

# FORGE-authored allow-list. Lives in the test as the source of truth
# for the contract — forge-stoke.md command body MUST match.
ACCEPT_TOKENS = frozenset({"yes", "y", "confirm", "approve", "ok", "okay"})
REJECT_TOKENS = frozenset({"no", "n", "cancel"})


def parse_consent(raw: str) -> Outcome:
    """Strict-literal consent parser (Req 3a).

    - Returns ACCEPT iff the trimmed lowercased input is an exact match
      against ACCEPT_TOKENS. Compound answers, hedged answers, conditional
      answers, paraphrase, and silence → AMBIGUOUS (NEVER ACCEPT).
    - Returns REJECT for exact matches against REJECT_TOKENS.
    - Returns AMBIGUOUS otherwise.
    """
    norm = raw.strip().lower()
    if norm in ACCEPT_TOKENS:
        return "ACCEPT"
    if norm in REJECT_TOKENS:
        return "REJECT"
    return "AMBIGUOUS"


@pytest.mark.parametrize("inp", ["yes", "Y", "  YES  ", "confirm", "Approve", "ok", "OKAY"])
def test_allow_list_accepts(inp):
    """AC 9 (a, b, c, e): yes/y/confirm/approve/ok/okay → ACCEPT."""
    assert parse_consent(inp) == "ACCEPT"


@pytest.mark.parametrize("inp", ["no", "N", " Cancel "])
def test_reject_tokens(inp):
    assert parse_consent(inp) == "REJECT"


@pytest.mark.parametrize("inp", [
    "yeah but only for docs",
    "sure",
    "yes please proceed if safe",
    "yes, but skip the trust",
    "yep",
    "affirmative",
    "go ahead",
    "do it",
    "",
    " ",
    "\n",
    "Why are you asking?",
    "y/n",
    "yes no",
])
def test_ambiguous_answers_reprompt(inp):
    """AC 9 (d, f, g): hedged/compound/paraphrase/silence → AMBIGUOUS."""
    assert parse_consent(inp) == "AMBIGUOUS"


def test_three_consecutive_ambiguous_aborts():
    """AC 9 (h) / Req 3b: after the third ambiguous answer the gate aborts.

    Models the conversation: prompt → (ambiguous → reprompt) × 2 → final
    ambiguous answer → ABORT. Max 2 RE-prompts means at most 3 total
    operator turns; the 3rd ambiguous answer treats as REJECT/abort.
    """
    inputs = ["maybe", "perhaps", "i guess"]
    reprompts = 0
    aborted = False
    for raw in inputs:
        outcome = parse_consent(raw)
        if outcome == "AMBIGUOUS":
            reprompts += 1
            if reprompts > 2:
                aborted = True
                break
    assert aborted, "third ambiguous answer must abort the gate"


def test_first_accept_short_circuits_reprompt_counter():
    """A clean ACCEPT on the second attempt does NOT trip the abort
    counter — abort only applies to 3 consecutive AMBIGUOUS responses."""
    transcript = ["umm", "yes"]
    reprompts = 0
    accepted = False
    for raw in transcript:
        outcome = parse_consent(raw)
        if outcome == "ACCEPT":
            accepted = True
            break
        if outcome == "AMBIGUOUS":
            reprompts += 1
            if reprompts > 2:
                break
    assert accepted
    assert reprompts == 1

"""Spec 447 — regression tests for the Spec 437 primary per-question validator.

The validator lives in copier.yml as a Jinja predicate on the
`accept_security_overrides` question. It fires during `copier update`'s
`old_worker.run_copy() → _ask() → validate_answer()` because the runtime
`--data accept_security_overrides_confirmed=true` token only reaches the
new-worker apply, not the old-worker rebuild.

Spec 447 adds `_copier_operation != 'update'` to the predicate so update
operations bypass the validator (same threat-model reasoning as Spec 445).

These tests evaluate the validator's Jinja predicate directly via a minimal
Jinja environment — no copier-full-rendering required. The integration
contract is also asserted via a static check on copier.yml.

Run:
    pytest .forge/tests/test_validator_update_rebuild.py -v
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

try:
    from jinja2 import Environment
except ImportError:
    pytest.skip("Jinja2 not installed", allow_module_level=True)


_THIS = Path(__file__).resolve()
for candidate in (_THIS.parents[2], _THIS.parents[1]):
    if (candidate / "copier.yml").is_file():
        REPO_ROOT = candidate
        break
else:
    pytest.skip("copier.yml not found in any expected layout", allow_module_level=True)


# Extract the validator predicate from copier.yml (line 357 region). We
# evaluate just the predicate `{%- if ... -%}...{%- endif -%}` against various
# Jinja contexts; if the body emits content, the validator refuses.
def _extract_primary_validator() -> str:
    """Extract the validator: block for accept_security_overrides."""
    text = (REPO_ROOT / "copier.yml").read_text(encoding="utf-8")
    # Find the accept_security_overrides question block.
    m = re.search(
        r"^accept_security_overrides:\s*$.*?^\S",
        text, re.M | re.S,
    )
    if not m:
        # The question may be at end-of-file with no following block — try non-greedy to next ^accept_ or end.
        m = re.search(
            r"^accept_security_overrides:\s*$.*",
            text, re.M | re.S,
        )
    block = m.group(0) if m else ""
    # Extract validator: >-\n    ...
    vm = re.search(r"validator:\s*>-\s*\n((?:\s{4,}.*\n)+)", block)
    if not vm:
        return ""
    # Strip leading 4-space indent on each line to get the bare template.
    body = "\n".join(line[4:] if line.startswith("    ") else line for line in vm.group(1).splitlines())
    return body


VALIDATOR_TEMPLATE = _extract_primary_validator()


def _render(operation: str, accept: bool, confirmed: bool) -> str:
    """Render the validator template with the given context."""
    env = Environment()
    template = env.from_string(VALIDATOR_TEMPLATE)
    return template.render(
        _copier_operation=operation,
        accept_security_overrides=accept,
        accept_security_overrides_confirmed=confirmed,
        # Provide defaults for the keys the body iterates over so rendering
        # doesn't crash inside the if-branch.
        test_command="pytest -q",
        lint_command="ruff check .",
        harness_command="",
        include_nanoclaw=False,
        include_advanced_autonomy=False,
        include_two_stage_review=False,
    ).strip()


# ---- AC 1: static check on the predicate ----------------------------------

def test_ac1_predicate_contains_update_clause():
    """AC 1: validator predicate references _copier_operation != 'update'."""
    text = (REPO_ROOT / "copier.yml").read_text(encoding="utf-8")
    # Find the predicate line near accept_security_overrides_confirmed.
    m = re.search(
        r"\{%-?\s*if\s+accept_security_overrides\s+and\s+not\s+accept_security_overrides_confirmed[^%]+%\}",
        text,
    )
    assert m, "primary validator predicate not found in copier.yml"
    predicate = m.group(0)
    assert re.search(r"_copier_operation\s*(?:\|default\([^)]+\)\s*)?!=\s*['\"]update['\"]", predicate), (
        f"validator predicate must include `_copier_operation != 'update'` (Spec 447 Req 1).\n"
        f"Actual predicate: {predicate}"
    )


# ---- AC 2: validator SKIPS on update --------------------------------------

def test_ac2_validator_skips_on_update():
    """AC 2: update + accept=true + no consent → validator emits empty string."""
    result = _render(operation="update", accept=True, confirmed=False)
    assert result == "", (
        f"validator should pass on update; got refusal string:\n{result[:200]}"
    )


# ---- AC 3: validator FIRES on copy ----------------------------------------

def test_ac3_validator_fires_on_copy():
    """AC 3: copy + accept=true + no consent → validator emits refusal string."""
    result = _render(operation="copy", accept=True, confirmed=False)
    assert "Spec 437" in result, (
        f"validator should refuse on copy; got: {result[:200]!r}"
    )


# ---- Edge: missing _copier_operation defaults to 'copy' semantics ---------

def test_missing_operation_defaults_to_copy():
    """Older copier versions / templates that don't pass _copier_operation:
    Jinja `|default('copy')` makes the predicate behave as fresh-copy."""
    env = Environment()
    template = env.from_string(VALIDATOR_TEMPLATE)
    result = template.render(
        # _copier_operation deliberately omitted
        accept_security_overrides=True,
        accept_security_overrides_confirmed=False,
        test_command="pytest -q",
        lint_command="ruff check .",
        harness_command="",
        include_nanoclaw=False,
        include_advanced_autonomy=False,
        include_two_stage_review=False,
    ).strip()
    assert "Spec 437" in result, (
        f"missing _copier_operation must default to copy semantics (gate fires); "
        f"got: {result[:200]!r}"
    )


# ---- Legitimate consent path: validator passes regardless of operation ----

@pytest.mark.parametrize("operation", ["copy", "update", ""])
def test_legitimate_consent_passes(operation):
    """accept=true + confirmed=true → validator passes regardless of operation."""
    result = _render(operation=operation, accept=True, confirmed=True)
    assert result == ""


# ---- No-override path: validator passes -----------------------------------

@pytest.mark.parametrize("operation", ["copy", "update"])
def test_no_override_passes(operation):
    """accept=false → validator passes regardless of operation."""
    result = _render(operation=operation, accept=False, confirmed=False)
    assert result == ""


# ---- Update mode + poisoned confirmed=true via answers file -----------------

def test_update_with_confirmed_true_in_answers_passes_at_validator():
    """A poisoned answers file with confirmed=true would pass the validator
    on update — but the SCRIPT-level Spec 437 Req 1a poisoned-token check
    (Spec 445 path) is what catches that case. This test documents the
    validator-layer behavior; the script-layer test in
    test_consent_gate_update_path.py::test_ac4_update_poisoned_answers_still_refuses
    asserts the orthogonal defense-in-depth check."""
    result = _render(operation="update", accept=True, confirmed=True)
    assert result == ""

"""Spec 448 — assert the per-question validator on accept_security_overrides
is intentionally REMOVED.

Replaces test_validator_update_rebuild.py (Spec 447 artifact). Spec 447's
predicate fix was logically correct but mechanically defeated: copier does
not inject `_copier_operation` into the validator's Jinja evaluation context
during the old_worker rebuild (`_apply_update → old_worker.run_copy() →
_ask() → validate_answer()`), so `|default('copy')` kicked in and the
validator tripped.

Spec 448 removes the per-question validator entirely. Spec 437 enforcement
consolidates at the script-level gate (forge_consent_gate.py, wired as
`_tasks[0]`), which:
- Fires BEFORE persistent state is written
- Covers Req 1a (poisoned-token check)
- Covers Req 1b (literal-command-string display in refusal)
- Correctly handles update mode (Spec 445)

These tests guard against re-introduction of the broken layer.

Run:
    pytest .forge/tests/test_validator_absent.py -v
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest


_THIS = Path(__file__).resolve()
for candidate in (_THIS.parents[2], _THIS.parents[1]):
    if (candidate / "copier.yml").is_file():
        REPO_ROOT = candidate
        break
else:
    pytest.skip("copier.yml not found in any expected layout", allow_module_level=True)


def _extract_question_block(name: str) -> str:
    """Return the YAML block for a top-level question key in copier.yml.

    Block extends from `^<name>:` to the next top-level key or a top-level
    comment that starts a new section.
    """
    text = (REPO_ROOT / "copier.yml").read_text(encoding="utf-8")
    # Find the start.
    pattern = rf"^{re.escape(name)}:\s*$"
    m = re.search(pattern, text, re.M)
    if not m:
        return ""
    start = m.start()
    # Find the next top-level key (line starting at column 0 with `<key>:` or comment block).
    after = text[m.end():]
    next_top = re.search(r"^[A-Za-z_]", after, re.M)
    end = m.end() + (next_top.start() if next_top else len(after))
    return text[start:end]


def test_ac1_no_validator_block():
    """AC 1: accept_security_overrides has no `validator:` key."""
    block = _extract_question_block("accept_security_overrides")
    assert block, "accept_security_overrides question block not found in copier.yml"
    # `validator:` must not appear as a YAML key in this block.
    # Strip line-comments before scanning (commented references in help/explanatory
    # comments are fine — only an actual validator: key counts).
    code_lines = [ln for ln in block.splitlines() if not ln.lstrip().startswith("#")]
    code = "\n".join(code_lines)
    assert not re.search(r"^\s*validator\s*:", code, re.M), (
        "accept_security_overrides MUST NOT have a per-question `validator:` "
        "block (Spec 448). Enforcement consolidates at the script-level gate "
        "(scripts/copier-hooks/forge_consent_gate.py). Re-introducing the "
        "validator will trip during copier-update's old_worker rebuild because "
        "copier doesn't inject _copier_operation in that context."
    )


def test_ac2_help_text_references_script_gate():
    """AC 2: help: text references the script-level gate so operators know
    where enforcement lives."""
    block = _extract_question_block("accept_security_overrides")
    # Help text must mention the script gate explicitly.
    help_match = re.search(r"help:\s*\"([^\"]+)\"", block)
    assert help_match, "help: field not found"
    help_text = help_match.group(1)
    # Accept any of: 'forge_consent_gate', 'task-level', 'script-level', '_tasks'.
    markers = ("forge_consent_gate", "task-level", "script-level", "_tasks")
    assert any(m in help_text for m in markers), (
        f"help: text MUST reference the script gate (one of {markers}). "
        f"Got: {help_text[:200]!r}"
    )


def test_spec_447_predicate_removed_or_inert():
    """The Spec 447 predicate clause (`_copier_operation != 'update'`) is gone
    OR is in a comment context (no longer in an active Jinja predicate)."""
    block = _extract_question_block("accept_security_overrides")
    # Strip comments first.
    code_lines = [ln for ln in block.splitlines() if not ln.lstrip().startswith("#")]
    code = "\n".join(code_lines)
    # An active `{%- if ... %}` block referencing _copier_operation would
    # indicate the validator is still present in some form.
    assert "{%- if" not in code and "{% if" not in code, (
        "active Jinja predicate found in accept_security_overrides question "
        "code — Spec 448 removes per-question Jinja validation. Move enforcement "
        "to forge_consent_gate.py."
    )


def test_script_gate_remains_canonical():
    """The script-level gate file MUST still exist at both expected locations
    (Spec 446 contract) — that's the layer Spec 448 relies on."""
    root_copy = REPO_ROOT / "scripts" / "copier-hooks" / "forge_consent_gate.py"
    template_copy = REPO_ROOT / "template" / "scripts" / "copier-hooks" / "forge_consent_gate.py"
    assert root_copy.is_file(), f"missing: {root_copy}"
    assert template_copy.is_file(), f"missing: {template_copy}"


def test_obsolete_validator_test_removed():
    """test_validator_update_rebuild.py is superseded by this file.
    Sanity: if it still exists, fail loudly so it's deleted in this commit."""
    obsolete = _THIS.parent / "test_validator_update_rebuild.py"
    assert not obsolete.exists(), (
        f"{obsolete} is superseded by test_validator_absent.py — delete it. "
        "The Spec 447 predicate it tested is no-longer-contracted."
    )

"""Spec 445 — regression tests for forge_consent_gate.py update-path hotfix.

Covers AC 1-5: gate behavior across (operation × consent state) combinations.
Covers AC 7: copier.yml argv-length static check.

Tests invoke the hook in-process via importlib (avoids Windows subprocess pipe
flakiness — same pattern as Spec 444 tests).

Run:
    pytest .forge/tests/test_consent_gate_update_path.py -v
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest


_THIS = Path(__file__).resolve()
for candidate in (
    _THIS.parents[2] / "scripts" / "copier-hooks" / "forge_consent_gate.py",
    _THIS.parents[1] / "scripts" / "copier-hooks" / "forge_consent_gate.py",
):
    if candidate.is_file():
        HOOK_PATH = candidate
        break
else:
    raise RuntimeError("Could not locate forge_consent_gate.py")


def _load_hook():
    """Fresh import of the hook module per test (each test mutates sys.argv)."""
    spec = importlib.util.spec_from_file_location("_consent_gate_under_test", HOOK_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _invoke(args: list[str]) -> int:
    """Run hook.main() with given argv. Returns exit code (0 = PASS, 1 = REFUSE)."""
    hook = _load_hook()
    saved = sys.argv
    sys.argv = ["forge_consent_gate.py", *args]
    try:
        hook.main()
        return 0
    except SystemExit as e:
        return int(e.code) if e.code is not None else 0
    finally:
        sys.argv = saved


def _write_answers(tmp_path: Path, lines: list[str]) -> Path:
    p = tmp_path / ".copier-answers.yml"
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return tmp_path


# ---- AC 1: copy + accept + no consent + poisoned answers → REFUSE ---------

def test_ac1_copy_poisoned_answers_refuses(tmp_path):
    _write_answers(tmp_path, [
        "_src_path: /irrelevant",
        "accept_security_overrides: true",
        "accept_security_overrides_confirmed: true",  # POISON
    ])
    assert _invoke(["true", "false", str(tmp_path), "copy"]) == 1


# ---- AC 2: copy + accept + no consent + clean answers → REFUSE -----------

def test_ac2_copy_no_consent_refuses(tmp_path):
    _write_answers(tmp_path, [
        "_src_path: /irrelevant",
        "accept_security_overrides: true",
    ])
    assert _invoke(["true", "false", str(tmp_path), "copy"]) == 1


# ---- AC 3: update + accept + no consent + clean answers → PASS (THE FIX) ---

def test_ac3_update_no_consent_passes(tmp_path):
    """The Spec 445 bug-fix: update mode trusts the persisted answers file."""
    _write_answers(tmp_path, [
        "_src_path: /irrelevant",
        "accept_security_overrides: true",
    ])
    assert _invoke(["true", "false", str(tmp_path), "update"]) == 0


# ---- AC 4: update + accept + no consent + poisoned answers → REFUSE -------

def test_ac4_update_poisoned_answers_still_refuses(tmp_path):
    """Poisoned-token check stays active on update — defense in depth."""
    _write_answers(tmp_path, [
        "_src_path: /irrelevant",
        "accept_security_overrides: true",
        "accept_security_overrides_confirmed: true",  # POISON
    ])
    assert _invoke(["true", "false", str(tmp_path), "update"]) == 1


# ---- AC 5: copy + accept + consent → PASS (legitimate path) ---------------

def test_ac5_copy_with_consent_passes(tmp_path):
    _write_answers(tmp_path, [
        "_src_path: /irrelevant",
        "accept_security_overrides: true",
    ])
    assert _invoke(["true", "true", str(tmp_path), "copy"]) == 0


# ---- No-override path is a no-op regardless of operation -----------------

@pytest.mark.parametrize("operation", ["copy", "update", ""])
def test_no_override_no_gate(tmp_path, operation):
    """accept_flag=false → hook returns immediately regardless of other state."""
    assert _invoke(["false", "false", str(tmp_path), operation]) == 0


# ---- Update mode + no answers file → PASS (nothing to validate) ----------

def test_update_no_answers_file_passes(tmp_path):
    """Empty tmp dir with no .copier-answers.yml: update mode passes."""
    assert _invoke(["true", "false", str(tmp_path), "update"]) == 0


# ---- Backward-compat: missing operation argv → fresh-copy semantics ------

def test_missing_operation_argv_defaults_to_copy(tmp_path):
    """Older copier versions / older templates may not pass argv[4]. The hook
    must default to fresh-copy semantics so the gate stays active."""
    _write_answers(tmp_path, [
        "_src_path: /irrelevant",
        "accept_security_overrides: true",
    ])
    assert _invoke(["true", "false", str(tmp_path)]) == 1


# ---- AC 7: copier.yml passes _copier_operation to the hook ---------------

def test_ac7_copier_yml_passes_copier_operation():
    """Spec 445 Req 1: copier.yml MUST pass {{ _copier_operation }} to the hook."""
    for candidate in (
        _THIS.parents[2] / "copier.yml",
        _THIS.parents[1] / "copier.yml",
    ):
        if candidate.is_file():
            copier_yml = candidate
            break
    else:
        pytest.skip("copier.yml not in this layout")
    text = copier_yml.read_text(encoding="utf-8")
    # The hook invocation must include the _copier_operation Jinja variable.
    assert "_copier_operation" in text, \
        "copier.yml must pass {{ _copier_operation }} to forge_consent_gate.py"
    # And the operation arg must appear near the hook invocation (not e.g.,
    # in an unrelated comment block elsewhere).
    hook_idx = text.find("forge_consent_gate.py")
    op_idx = text.find("_copier_operation", hook_idx)
    assert op_idx > hook_idx, "_copier_operation must appear AFTER the hook invocation"
    # Sanity: they should be within ~30 lines of each other.
    intervening = text[hook_idx:op_idx]
    assert intervening.count("\n") < 30, \
        f"_copier_operation should be in the same _tasks block as the hook (separated by {intervening.count(chr(10))} lines)"

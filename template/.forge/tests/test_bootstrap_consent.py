"""Spec 437 — Bootstrap-path consent surface tests (AC 1-7).

Test strategy
-------------
The implementation is a hybrid:
- PRIMARY: per-question `validator:` on `accept_security_overrides` in copier.yml
- SECONDARY: `scripts/copier-hooks/forge_consent_gate.py` wired into `_tasks:` first

Structural tests verify both gates exist in copier.yml at the expected positions
(fast, no copier subprocess required, catches regression-by-removal).

Render tests subprocess `copier copy` against synthetic fixtures F1-F5 to verify
empirical end-to-end behavior. They are marked `slow` and `requires_copier`; CI
should run them on every change to copier.yml or the consent gate hook.

Fixtures F1-F5 correspond to AC 1, 2, 3, 5, 6, 7 + Req 1a/1b/Req 7.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
COPIER_YML = REPO_ROOT / "copier.yml"
CONSENT_GATE = REPO_ROOT / "scripts" / "copier-hooks" / "forge_consent_gate.py"


# ---------------------------------------------------------------------------
# Structural — primary gate (validator on accept_security_overrides)
# ---------------------------------------------------------------------------

def test_primary_validator_present_on_accept_security_overrides():
    """The per-question `validator:` block must exist on accept_security_overrides
    and reference accept_security_overrides_confirmed."""
    text = COPIER_YML.read_text(encoding="utf-8")
    match = re.search(
        r"^accept_security_overrides:\s*\n"
        r"((?:[ \t]+[^\n]*\n)+)",
        text,
        flags=re.MULTILINE,
    )
    assert match, "accept_security_overrides block not found"
    body = match.group(1)
    assert "validator:" in body, (
        "REGRESSION: Spec 437 primary gate removed — no validator: on "
        "accept_security_overrides. Restore the validator that refuses render "
        "when accept_security_overrides_confirmed is not also true."
    )
    assert "accept_security_overrides_confirmed" in body, (
        "Spec 437 validator no longer references accept_security_overrides_confirmed."
    )
    assert "Spec 437" in body, (
        "Spec 437 marker missing from accept_security_overrides validator — "
        "future readers must be able to trace the gate to its spec."
    )


def test_primary_validator_displays_literal_command_strings():
    """Req 1b: refusal message must reference each security-gated key by name
    so the literal command values are rendered into the error output."""
    text = COPIER_YML.read_text(encoding="utf-8")
    # Find the Spec 437 validator block specifically (not the older Spec 090
    # per-question validators on test_command etc.).
    start = text.find("\naccept_security_overrides:\n")
    assert start != -1, "accept_security_overrides block not found"
    # Block extends to the next top-level question (line beginning with non-whitespace + colon).
    rest = text[start + 1 :]
    end_match = re.search(r"\n[A-Za-z_][A-Za-z0-9_]*:\s*\n", rest)
    body = rest[: end_match.start()] if end_match else rest
    for key in (
        "test_command",
        "lint_command",
        "harness_command",
        "include_nanoclaw",
        "include_advanced_autonomy",
        "include_two_stage_review",
    ):
        assert key in body, (
            f"Req 1b: validator does not reference `{key}`. The refusal message "
            f"must enumerate each non-default security-gated key so its value is "
            f"rendered into the error output."
        )


def test_consent_token_question_is_secret_and_bool():
    """The accept_security_overrides_confirmed question MUST be `secret: true`
    and `type: bool`. Without secret:true, legitimate CLI consent values would
    persist to .copier-answers.yml and indistinguishably mix with poisoned
    file-supplied tokens."""
    text = COPIER_YML.read_text(encoding="utf-8")
    match = re.search(
        r"^accept_security_overrides_confirmed:\s*\n"
        r"((?:[ \t]+[^\n]*\n)+)",
        text,
        flags=re.MULTILINE,
    )
    assert match, "accept_security_overrides_confirmed block not found"
    body = match.group(1)
    assert re.search(r"^\s*type:\s*bool\b", body, re.MULTILINE), (
        "REGRESSION: accept_security_overrides_confirmed is no longer type: bool"
    )
    assert re.search(r"^\s*secret:\s*true\b", body, re.MULTILINE), (
        "REGRESSION: accept_security_overrides_confirmed must be secret: true so "
        "legitimate CLI consent values are never persisted to .copier-answers.yml "
        "(Spec 437 Req 1a)."
    )


# ---------------------------------------------------------------------------
# Structural — secondary gate (Python _tasks hook)
# ---------------------------------------------------------------------------

def test_consent_gate_hook_exists():
    """The forge_consent_gate.py script must exist at the expected path."""
    assert CONSENT_GATE.is_file(), (
        f"Spec 437 secondary gate missing: expected {CONSENT_GATE}. "
        f"Restore the hook or update copier.yml _tasks: to point elsewhere."
    )


def test_consent_gate_hook_wired_first_in_tasks():
    """The hook must be the FIRST entry in _tasks: (so poisoned-answers-file
    renders abort before scrub_answers.py / migrate-to-derived-view.py mutate
    persistent state)."""
    text = COPIER_YML.read_text(encoding="utf-8")
    tasks_match = re.search(
        r"^_tasks:\s*\n((?:[ \t]+.+\n)+)",
        text,
        flags=re.MULTILINE,
    )
    assert tasks_match, "_tasks: block not found in copier.yml"
    tasks_body = tasks_match.group(1)
    # The consent gate's invocation should be referenced before scrub_answers.py.
    consent_idx = tasks_body.find("forge_consent_gate.py")
    scrub_idx = tasks_body.find("scrub_answers.py")
    assert consent_idx != -1, (
        "REGRESSION: forge_consent_gate.py not wired into _tasks:. "
        "Spec 437 secondary gate is bypassed."
    )
    assert scrub_idx == -1 or consent_idx < scrub_idx, (
        f"Spec 437: forge_consent_gate.py must run BEFORE scrub_answers.py "
        f"in _tasks: (got consent_idx={consent_idx}, scrub_idx={scrub_idx}). "
        "Otherwise scrub mutates .copier-answers.yml before the poison check "
        "reads it."
    )


def test_consent_gate_hook_passes_required_arguments():
    """The _tasks: invocation must pass the flag value, consent value, dest path,
    and the literal-display key/value pairs."""
    text = COPIER_YML.read_text(encoding="utf-8")
    # Extract the command block surrounding the forge_consent_gate.py reference.
    # The command block is a YAML list under `command:`; it ends at the next
    # top-level YAML key (`- command:` for the next _tasks entry, or `_<key>:`
    # / a bare identifier with `:` at column 0).
    # The first reference is a comment; the second is the actual command-list entry.
    anchor = text.find('scripts/copier-hooks/forge_consent_gate.py"')
    assert anchor != -1, (
        "Quoted command-list reference to forge_consent_gate.py not found in copier.yml"
    )
    next_cmd = text.find("\n  - command:", anchor)
    if next_cmd == -1:
        next_cmd = len(text)
    body = text[anchor:next_cmd]
    # Required argv: accept_security_overrides, accept_security_overrides_confirmed, dst_path
    assert "accept_security_overrides|default(false)" in body, (
        "consent gate invocation is missing the rendered accept_security_overrides arg"
    )
    assert "accept_security_overrides_confirmed|default(false)" in body, (
        "consent gate invocation is missing the rendered "
        "accept_security_overrides_confirmed arg"
    )
    assert "_copier_conf.dst_path" in body, (
        "consent gate invocation is missing the dst_path arg (needed to read "
        "the destination's .copier-answers.yml)"
    )
    # Req 1b literal-command-string display args.
    for key in ("test_command", "lint_command", "harness_command", "include_nanoclaw"):
        assert key in body, (
            f"consent gate invocation does not pass `{key}` for Req 1b literal display"
        )


# ---------------------------------------------------------------------------
# Hook unit tests (exercise forge_consent_gate.py directly)
# ---------------------------------------------------------------------------

def _run_hook(*args, cwd=None, operation="copy"):
    """Invoke forge_consent_gate.py with the given argv and return CompletedProcess.

    Spec 445: the hook's positional contract added `operation` at argv[4]
    (copy|update). Existing Spec 437 tests exercise fresh-copy semantics,
    so this helper injects "copy" by default between argv[3] (dst_path) and
    the override-key args. Pass `operation="update"` to test the Spec 445
    update-mode skip path.

    `stdin=subprocess.DEVNULL` is required on Windows when pytest's stdin handle
    has been invalidated by a prior test's subprocess interaction — without it,
    `subprocess.run` raises "[WinError 6] The handle is invalid" when capturing.
    """
    # First 3 positional args (accept_flag, consent_value, dst_path) come first;
    # operation is argv[4]; remaining args are override keys.
    if len(args) >= 3:
        argv = [*args[:3], operation, *args[3:]]
    else:
        argv = list(args)  # malformed call — let the hook surface the error
    return subprocess.run(
        [sys.executable, str(CONSENT_GATE), *argv],
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
    )


def test_hook_no_override_passes(tmp_path):
    """F1 baseline: when accept_security_overrides is false, the hook exits 0
    regardless of the answers file."""
    # Even with a confirmation token in the answers file, no flag → no gate.
    (tmp_path / ".copier-answers.yml").write_text(
        "accept_security_overrides_confirmed: true\n", encoding="utf-8"
    )
    result = _run_hook("False", "False", str(tmp_path))
    assert result.returncode == 0, (
        f"hook should pass when flag=false; got stderr:\n{result.stderr}"
    )


def test_hook_consent_supplied_passes(tmp_path):
    """F3: --data consent supplied; answers file does NOT contain the token
    (because secret:true blocks persistence). Hook exits 0."""
    # Empty answers file — no poison token persisted.
    (tmp_path / ".copier-answers.yml").write_text(
        "accept_security_overrides: true\n", encoding="utf-8"
    )
    result = _run_hook(
        "True", "True", str(tmp_path), "test_command=pytest -v custom"
    )
    assert result.returncode == 0, (
        f"hook should pass when consent is true and no poison; got stderr:\n{result.stderr}"
    )


def test_hook_poisoned_token_refuses(tmp_path):
    """AC 5 / Req 1a regression: hook detects accept_security_overrides_confirmed
    persisted in .copier-answers.yml and aborts the render with a clear message."""
    (tmp_path / ".copier-answers.yml").write_text(
        "accept_security_overrides: true\n"
        "accept_security_overrides_confirmed: true\n"
        "test_command: rm -rf /\n",
        encoding="utf-8",
    )
    result = _run_hook(
        "True", "True", str(tmp_path), "test_command=rm -rf /"
    )
    assert result.returncode == 1, (
        f"hook should refuse the poisoned-token render; got rc={result.returncode}, "
        f"stderr:\n{result.stderr}"
    )
    assert "Spec 437" in result.stderr
    assert "Req 1a" in result.stderr
    assert "accept_security_overrides_confirmed" in result.stderr
    # AC 6 (literal-display) — the test_command value must appear verbatim.
    assert "rm -rf /" in result.stderr, (
        "AC 6 literal-command-display: the refusal message must contain the "
        "literal command value supplied for test_command."
    )


def test_hook_consent_absent_refuses(tmp_path):
    """Defense-in-depth: if the primary validator is somehow bypassed (e.g., a
    future template change moves the validator), the hook still refuses when
    consent=false and flag=true."""
    (tmp_path / ".copier-answers.yml").write_text(
        "accept_security_overrides: true\n", encoding="utf-8"
    )
    result = _run_hook(
        "True", "False", str(tmp_path), "test_command=rm -rf /"
    )
    assert result.returncode == 1
    assert "no runtime consent was supplied" in result.stderr
    assert "rm -rf /" in result.stderr  # Req 1b literal display


def test_hook_no_answers_file_with_consent_passes(tmp_path):
    """Fresh-bootstrap path: destination is empty, --data consent supplied.
    Hook exits 0 (no poison possible without an answers file)."""
    result = _run_hook("True", "True", str(tmp_path), "test_command=pytest -v")
    assert result.returncode == 0, (
        f"hook should pass on fresh bootstrap with --data consent; "
        f"stderr:\n{result.stderr}"
    )


def test_hook_filters_blank_override_args(tmp_path):
    """Jinja `{% if cond %}key=value{% endif %}` produces empty-string argv
    entries when cond is false. The hook must filter these out so the refusal
    message stays readable."""
    (tmp_path / ".copier-answers.yml").write_text(
        "accept_security_overrides: true\n"
        "accept_security_overrides_confirmed: true\n",
        encoding="utf-8",
    )
    # Mix of populated and blank overrides.
    result = _run_hook(
        "True", "True", str(tmp_path),
        "test_command=rm -rf /", "", "", "", "", "",
    )
    assert result.returncode == 1
    assert "test_command=rm -rf /" in result.stderr
    # No blank-line spam in the refusal message body.
    blank_indented_lines = [
        line for line in result.stderr.splitlines()
        if line.strip() == "" and line.startswith("    ")
    ]
    assert not blank_indented_lines, (
        "refusal message should not contain blank indented lines from filtered overrides"
    )


# ---------------------------------------------------------------------------
# Coverage with Spec 434 audit list (Req 6 alignment)
# ---------------------------------------------------------------------------

def test_secondary_hook_covers_full_security_gated_key_set():
    """The _tasks: invocation must pass every security-gated key tracked by
    Spec 434's AC 7 audit list (kept in sync with ADR-028)."""
    text = COPIER_YML.read_text(encoding="utf-8")
    consent_section_start = text.find("forge_consent_gate.py")
    assert consent_section_start != -1
    # Look in the surrounding command block.
    section = text[consent_section_start - 200 : consent_section_start + 2500]
    expected_keys = (
        "test_command",
        "lint_command",
        "harness_command",
        "include_nanoclaw",
        "include_advanced_autonomy",
        "include_two_stage_review",
    )
    for key in expected_keys:
        assert key in section, (
            f"Spec 437 consent-gate invocation does not include security-gated "
            f"key `{key}` (Req 6 / ADR-028 alignment). If a new key was added "
            f"in ADR-028, the _tasks: invocation must be extended to pass it."
        )

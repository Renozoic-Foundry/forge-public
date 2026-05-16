"""Spec 434 — `accept_security_overrides` answer-persistence + fresh-clone-detection tests.

AC 1–5 + AC 7. AC 6 (gotchas doc) is verified by a separate file-existence check.

Test strategy
-------------
The Copier render-level ACs (1, 2, 3, 4) require either invoking copier as a
subprocess against the repo's own copier.yml (slow, network-free but heavyweight)
or directly verifying the structural invariant in copier.yml that proves the fix
is in place. We use the structural approach — the v3.3 self-referential `when:`
pattern is the contract; the empirical-Copier-9.14.0 provenance is captured in
copier.yml:310–318 + docs/process-kit/copier-gotchas.md. Adding a copier-as-subprocess
test would re-verify Copier's behavior, not the fix.

AC 5 (stoke fresh-clone warning) is unit-testable directly against the
_detect_fresh_clone_consent_state helper without invoking copier at all.

AC 7 (static audit) is the meta-test that future edits to copier.yml don't
re-introduce bare `when: false` on security-gated keys.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
import subprocess
import tempfile

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
COPIER_YML = REPO_ROOT / "copier.yml"

sys.path.insert(0, str(REPO_ROOT / ".forge" / "lib"))
import stoke  # noqa: E402


# ---------------------------------------------------------------------------
# AC 1 + AC 7 (structural): accept_security_overrides uses v3.3 self-referential when:
# ---------------------------------------------------------------------------

def test_ac1_accept_security_overrides_uses_v33_pattern():
    """AC 1 + structural fix verification: the consent flag uses the v3.3 pattern,
    not bare `when: false`. This is the Spec 434 fix."""
    text = COPIER_YML.read_text(encoding="utf-8")
    # Locate the accept_security_overrides block and inspect its `when:` line.
    match = re.search(
        r"^accept_security_overrides:\s*\n"
        r"(?:[ \t]+[^\n]*\n)*?"
        r"[ \t]+when:\s*(.+?)$",
        text,
        flags=re.MULTILINE,
    )
    assert match, "accept_security_overrides block not found in copier.yml"
    when_value = match.group(1).strip()
    assert when_value != "false", (
        "REGRESSION: accept_security_overrides has bare `when: false` — Spec 434 fix "
        "reverted. This causes Copier 9.14.0 to strip the key from .copier-answers.yml "
        "on persist. Apply the v3.3 self-referential pattern."
    )
    # The self-referential pattern: when: "{{ accept_security_overrides|default(false) }}"
    assert "accept_security_overrides" in when_value and "default(false)" in when_value, (
        f"accept_security_overrides `when:` value does not match the v3.3 self-referential "
        f"pattern. Got: {when_value!r}. Expected something like "
        f'`"{{ accept_security_overrides|default(false) }}"`.'
    )


# ---------------------------------------------------------------------------
# AC 2: regression guard — without the flag, today's behavior is preserved
# (validators still gate). Verified structurally: the validators on test_command,
# lint_command, harness_command still read `accept_security_overrides`.
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("gated_key", ["test_command", "lint_command", "harness_command"])
def test_ac2_validators_still_gate_on_accept_security_overrides(gated_key):
    """AC 2 / AC 3: the per-question validators continue to read the flag.
    No code change should bypass them."""
    text = COPIER_YML.read_text(encoding="utf-8")
    # Find the gated_key block; its validator: predicate must reference the flag.
    block = re.search(
        rf"^{gated_key}:\s*\n((?:[ \t]+[^\n]*\n)+)",
        text,
        flags=re.MULTILINE,
    )
    assert block, f"{gated_key} block not found in copier.yml"
    body = block.group(1)
    assert "accept_security_overrides" in body, (
        f"{gated_key} validator no longer references accept_security_overrides — "
        f"the gate is bypassed. REGRESSION."
    )


# ---------------------------------------------------------------------------
# AC 7 (static audit): no security-gated key has bare `when: false`
# ---------------------------------------------------------------------------

# Security-gated keys per Spec 090 + Spec 434 Req 1. If a future edit adds a new
# security-gated flag, append to this list AND the gotchas doc.
SECURITY_GATED_KEYS = (
    "accept_security_overrides",
    "test_command",
    "lint_command",
    "harness_command",
    "include_nanoclaw",
    "include_advanced_autonomy",
    "include_two_stage_review",
)


def _parse_when_for_key(text: str, key: str) -> str | None:
    """Return the `when:` value for `key`, or None if not found / no when: line."""
    match = re.search(
        rf"^{key}:\s*\n"
        r"((?:[ \t]+[^\n]*\n)+)",
        text,
        flags=re.MULTILINE,
    )
    if not match:
        return None
    body = match.group(1)
    when_match = re.search(r"^[ \t]+when:\s*(.+?)$", body, flags=re.MULTILINE)
    if not when_match:
        return None
    return when_match.group(1).strip()


@pytest.mark.parametrize("key", SECURITY_GATED_KEYS)
def test_ac7_security_gated_keys_no_bare_when_false(key):
    """AC 7: static audit. No security-gated key may carry bare `when: false` —
    that triggers the Copier 9.14.0 answer-persistence strip bug.

    Dynamic when: predicates (templated booleans that runtime-evaluate to false)
    are explicitly out-of-scope of this static check — see
    docs/process-kit/copier-gotchas.md."""
    text = COPIER_YML.read_text(encoding="utf-8")
    when_value = _parse_when_for_key(text, key)
    if when_value is None:
        return  # no `when:` clause → not affected by the strip bug
    assert when_value != "false", (
        f"Security-gated key `{key}` has bare `when: false` — this triggers "
        f"Copier 9.14.0 answer-persistence strip (Spec 434). Use the v3.3 self-referential "
        f"pattern: `when: \"{{{{ {key}|default(false) }}}}\"`. See docs/process-kit/copier-gotchas.md."
    )


# ---------------------------------------------------------------------------
# AC 5: stoke fresh-clone-detection warning
# ---------------------------------------------------------------------------

def _make_answers(**overrides) -> dict:
    """Build a synthetic answers dict for the helper."""
    base = {
        "_commit": "abc123",
        "test_command": "pytest -q",
        "lint_command": "ruff check .",
    }
    base.update(overrides)
    return base


def test_ac5_flag_off_no_warning(tmp_path):
    """No warning when accept_security_overrides is not set / false."""
    answers = _make_answers(accept_security_overrides="false", test_command="./mvnw test")
    (tmp_path / ".copier-answers.yml").write_text("dummy", encoding="utf-8")
    result = stoke._detect_fresh_clone_consent_state(tmp_path, answers)
    assert result is None


def test_ac5_flag_on_but_no_overrides_no_warning(tmp_path):
    """No warning when flag is set but all security-gated keys are at defaults."""
    answers = _make_answers(accept_security_overrides="true")  # defaults only
    (tmp_path / ".copier-answers.yml").write_text("dummy", encoding="utf-8")
    result = stoke._detect_fresh_clone_consent_state(tmp_path, answers)
    assert result is None


def test_ac5_fresh_clone_with_flag_and_override_warns(tmp_path):
    """Warning fires: flag on + non-default test_command + no git history."""
    answers = _make_answers(accept_security_overrides="true", test_command="./mvnw test")
    (tmp_path / ".copier-answers.yml").write_text("dummy", encoding="utf-8")
    # tmp_path has no .git directory → fresh_clone path
    result = stoke._detect_fresh_clone_consent_state(tmp_path, answers)
    assert result == ["test_command"], (
        f"Expected warning naming test_command; got {result!r}"
    )


def test_ac5_multi_key_warning(tmp_path):
    """Multi-key warning: both test_command and lint_command non-default."""
    answers = _make_answers(
        accept_security_overrides="true",
        test_command="./mvnw test",
        lint_command="./mvnw verify",
    )
    (tmp_path / ".copier-answers.yml").write_text("dummy", encoding="utf-8")
    result = stoke._detect_fresh_clone_consent_state(tmp_path, answers)
    assert result is not None
    assert set(result) == {"test_command", "lint_command"}


def test_ac5_committed_unchanged_treated_as_fresh_clone(tmp_path):
    """When .copier-answers.yml is committed and unchanged in working tree, the
    operator has not made an in-session edit — treat as fresh-clone state and warn."""
    # Init a real git repo so the ls-files + diff path runs.
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=tmp_path, check=True)
    answers_file = tmp_path / ".copier-answers.yml"
    answers_file.write_text(
        "accept_security_overrides: true\ntest_command: ./mvnw test\n", encoding="utf-8"
    )
    subprocess.run(["git", "add", ".copier-answers.yml"], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=tmp_path, check=True)
    # Now the file is committed-and-unchanged → fresh-clone path.
    answers = _make_answers(accept_security_overrides="true", test_command="./mvnw test")
    result = stoke._detect_fresh_clone_consent_state(tmp_path, answers)
    assert result == ["test_command"], (
        "committed-unchanged answers file should trigger the warning (operator hasn't "
        "actively edited it in this session)"
    )


def test_ac5_in_session_edit_no_warning(tmp_path):
    """When .copier-answers.yml has working-tree changes vs HEAD, the operator
    IS actively editing it — assume conscious consent, no warning."""
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=tmp_path, check=True)
    answers_file = tmp_path / ".copier-answers.yml"
    answers_file.write_text("accept_security_overrides: false\n", encoding="utf-8")
    subprocess.run(["git", "add", ".copier-answers.yml"], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=tmp_path, check=True)
    # Now operator edits the file in the working tree.
    answers_file.write_text(
        "accept_security_overrides: true\ntest_command: ./mvnw test\n", encoding="utf-8"
    )
    answers = _make_answers(accept_security_overrides="true", test_command="./mvnw test")
    result = stoke._detect_fresh_clone_consent_state(tmp_path, answers)
    assert result is None, (
        "in-session working-tree edit indicates conscious consent — no warning expected"
    )


# ---------------------------------------------------------------------------
# AC 6: gotchas doc exists
# ---------------------------------------------------------------------------

def test_ac6_gotchas_doc_exists():
    """AC 6: docs/process-kit/copier-gotchas.md exists and documents both the
    when:false strip behavior and the bootstrap-path gap."""
    doc = REPO_ROOT / "docs" / "process-kit" / "copier-gotchas.md"
    assert doc.is_file(), f"{doc} missing"
    text = doc.read_text(encoding="utf-8")
    assert "when: false" in text, "gotchas doc missing the when:false behavior section"
    assert "self-referential" in text, "gotchas doc missing the v3.3 pattern reference"
    assert "Bootstrap-path consent" in text or "bootstrap-path" in text.lower(), (
        "gotchas doc missing the bootstrap-path consent gap discussion"
    )

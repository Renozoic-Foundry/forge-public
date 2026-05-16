"""Spec 444 — tests for stoke/gates.py.

Covers:
  AC 1   — preflight-gates JSON enumeration against a synthetic fixture.
  Req 1  — Gate schema (kind/label/rationale/operator_question/
           copier_data_keys_to_set_on_yes).
  R-Sec-2 — operator_question text comes from FORGE-controlled constants
            (not template-controlled strings).
  AC 9a  — adversarial YAML fixtures: anchors (&anchor), aliases (*alias),
            folded scalars (>) inside validator: declarations.

Run:
    pytest .forge/tests/test_stoke_gates.py -v
"""
from __future__ import annotations

import json
import subprocess
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


# Minimal copier.yml with _tasks + security-gated keys + Spec 437 surface.
_FIXTURE_COPIER_YML = """\
_tasks:
  - command: ["python", "-c", "print('hi')"]

test_command:
  type: str
  default: "pytest -q"
  help: "Test command"
  validator: >-
    {%- if test_command != 'pytest -q' and not accept_security_overrides -%}
    test_command accepts arbitrary shell. Set accept_security_overrides=true.
    {%- endif -%}

lint_command:
  type: str
  default: "ruff check ."
  help: "Lint command"

accept_security_overrides:
  type: bool
  default: false
  help: "Spec 090 consent."
"""

_FIXTURE_ANSWERS_DEFAULT = """\
_src_path: /path/to/template
test_command: "pytest -q"
"""

_FIXTURE_ANSWERS_OVERRIDE = """\
_src_path: /path/to/template
test_command: "./mvnw test"
"""


def _make_fixture(tmp_path: Path, answers: str) -> tuple[Path, Path]:
    consumer = tmp_path / "consumer"
    template = tmp_path / "template"
    consumer.mkdir()
    template.mkdir()
    (consumer / ".copier-answers.yml").write_text(answers, encoding="utf-8")
    (template / "copier.yml").write_text(_FIXTURE_COPIER_YML, encoding="utf-8")
    return consumer, template


def test_detect_gates_emits_three_gates_on_security_override(tmp_path):
    """AC 1: helper returns JSON array containing spec-090 + spec-437 gates."""
    consumer, template = _make_fixture(tmp_path, _FIXTURE_ANSWERS_OVERRIDE)
    gates = gates_mod.detect_gates(consumer, str(template))
    kinds = [g.kind for g in gates]
    assert "copier-tasks-trust" in kinds
    assert "spec-090-security-override" in kinds
    assert "spec-437-runtime-consent" in kinds


def test_detect_gates_skips_spec_090_when_no_customization(tmp_path):
    consumer, template = _make_fixture(tmp_path, _FIXTURE_ANSWERS_DEFAULT)
    gates = gates_mod.detect_gates(consumer, str(template))
    kinds = [g.kind for g in gates]
    assert "spec-090-security-override" not in kinds
    assert "spec-437-runtime-consent" not in kinds


def test_gate_schema_complete(tmp_path):
    """Req 1: every Gate has the five required fields."""
    consumer, template = _make_fixture(tmp_path, _FIXTURE_ANSWERS_OVERRIDE)
    gates = gates_mod.detect_gates(consumer, str(template))
    assert gates, "expected at least one gate"
    for g in gates:
        d = g.to_dict()
        assert set(d) == {
            "kind", "label", "rationale",
            "operator_question", "copier_data_keys_to_set_on_yes",
        }


def test_operator_questions_are_forge_controlled(tmp_path):
    """R-Sec-2 / AC 1: operator_question text matches a FORGE-authored
    constant, NOT something derived from the template."""
    consumer, template = _make_fixture(tmp_path, _FIXTURE_ANSWERS_OVERRIDE)
    gates = gates_mod.detect_gates(consumer, str(template))
    by_kind = {g.kind: g for g in gates}
    assert by_kind["copier-tasks-trust"].operator_question == gates_mod.QUESTION_COPIER_TASKS_TRUST
    assert by_kind["spec-090-security-override"].operator_question == gates_mod.QUESTION_SPEC_090_SECURITY
    assert by_kind["spec-437-runtime-consent"].operator_question == gates_mod.QUESTION_SPEC_437_RUNTIME


def test_yes_to_security_supplies_both_data_keys(tmp_path):
    """AC 3: yes-to-security yields BOTH accept_security_overrides=true
    AND accept_security_overrides_confirmed=true on the constructed CLI."""
    consumer, template = _make_fixture(tmp_path, _FIXTURE_ANSWERS_OVERRIDE)
    gates = gates_mod.detect_gates(consumer, str(template))
    keys: list[str] = []
    for g in gates:
        keys.extend(g.copier_data_keys_to_set_on_yes)
    assert "accept_security_overrides=true" in keys
    assert "accept_security_overrides_confirmed=true" in keys


def test_unknown_validator_gate_constructed_with_forge_text():
    """Fallback gate carries FORGE-controlled question text; template
    message is only in the rationale (not the prompt)."""
    g = gates_mod.unknown_validator_gate("malicious '; rm -rf / instructions")
    assert g.kind == "unknown-validator"
    assert g.operator_question == gates_mod.QUESTION_UNKNOWN_VALIDATOR
    # The template message is in rationale, NOT operator_question.
    assert "rm -rf" in g.rationale
    assert "rm -rf" not in g.operator_question


def test_known_gate_kinds_constant():
    """KNOWN_GATE_KINDS lists all four kinds from Req 2."""
    assert gates_mod.KNOWN_GATE_KINDS == {
        "copier-tasks-trust",
        "spec-090-security-override",
        "spec-437-runtime-consent",
        "unknown-validator",
    }


# ---- AC 9a — Adversarial YAML fixtures (DA R2) ------------------------------

_FIXTURE_YAML_ANCHORS = """\
_tasks:
  - command: &task_cmd ["python", "-c", "print('hi')"]

test_command:
  type: str
  default: &default_test "pytest -q"
  help: "Test command (with YAML anchor on default)"
  validator: >-
    {%- if test_command != 'pytest -q' and not accept_security_overrides -%}
    Folded-scalar validator message spans
    multiple lines without explicit newlines.
    Set accept_security_overrides=true to proceed.
    {%- endif -%}

lint_command:
  type: str
  default: *default_test
  help: "Lint command (aliased to default_test)"

accept_security_overrides:
  type: bool
  default: false
"""


def test_adversarial_yaml_anchors_and_folded_scalars(tmp_path):
    """AC 9a: detect_gates handles copier.yml with YAML anchors (&anchor),
    aliases (*alias), and folded scalars (>) inside validator: blocks
    without crashing. Regex robustness sanity check."""
    consumer = tmp_path / "consumer"
    template = tmp_path / "template"
    consumer.mkdir()
    template.mkdir()
    (consumer / ".copier-answers.yml").write_text(
        _FIXTURE_ANSWERS_OVERRIDE, encoding="utf-8"
    )
    (template / "copier.yml").write_text(_FIXTURE_YAML_ANCHORS, encoding="utf-8")
    # MUST NOT raise; MUST still detect at least the spec-090 gate.
    gates = gates_mod.detect_gates(consumer, str(template))
    kinds = [g.kind for g in gates]
    assert "spec-090-security-override" in kinds


# ---- preflight-gates CLI smoke ---------------------------------------------


def test_preflight_gates_cli_emits_json(tmp_path, capsys):
    """Smoke test the preflight-gates entry point in-process (avoids Windows
    subprocess pipe issues; functionally equivalent to invoking via
    `forge-py .forge/lib/stoke.py preflight-gates`)."""
    consumer, template = _make_fixture(tmp_path, _FIXTURE_ANSWERS_OVERRIDE)
    from stoke.__main__ import main as pkg_main
    rc = pkg_main([
        "preflight-gates",
        "--project-root", str(consumer),
        "--src-path", str(template),
    ])
    assert rc == 0
    out = capsys.readouterr().out
    data = json.loads(out)
    assert isinstance(data, list)
    kinds = [g["kind"] for g in data]
    assert "spec-090-security-override" in kinds

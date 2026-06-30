"""Spec 444 — Unified gate-detection module for /forge stoke.

Single source of truth for "what gates will fire on the next copier update."
Replaces the earlier-draft preflight.py (R-Arch-1) and absorbs Spec 428's
`_tasks` listing helper into the same module so /forge stoke command bodies
have one consistent surface.

Public API:
    detect_gates(consumer_root, template_src_path) -> list[Gate]
    list_tasks(template_src_path) -> list[str]   # Spec 428 compat wrapper
    KNOWN_GATE_KINDS                              # set[str] for AC 6

Gate schema (per Req 1):
    kind            — template-data-derived discriminator (string)
    label           — short FORGE-authored label
    rationale       — FORGE-authored one-line rationale
    operator_question — FORGE-authored yes/no prompt text
    copier_data_keys_to_set_on_yes — list of "KEY=VALUE" strings

Operator-visible text MUST come from constants defined here (R-Sec-2 —
closes CISO concern about template-controlled question text social-engineering
the operator). Template-derived content is restricted to the `kind`
discriminator and the rationale's enumerated key list.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, asdict
from pathlib import Path


# FORGE-controlled operator-visible text (R-Sec-2).
# These constants are the trust root for what the operator sees in chat.
# DO NOT pull this text from copier.yml, .copier-answers.yml, or any
# template-controlled source.
QUESTION_COPIER_TASKS_TRUST = (
    "The template wants to run setup tasks during the update. "
    "Trust the template to run these tasks? (yes/no)"
)
RATIONALE_COPIER_TASKS_TRUST = (
    "Copier requires --trust to execute _tasks: entries. "
    "Default is no-trust; trust is explicitly authorized per invocation."
)

QUESTION_SPEC_090_SECURITY = (
    "Your project customizes one or more security-relevant settings. "
    "FORGE requires explicit confirmation before applying updates that "
    "preserve those customizations. Proceed with the security overrides? (yes/no)"
)
RATIONALE_SPEC_090_SECURITY = (
    "Spec 090 + Spec 437: security-gated keys (test_command, lint_command, "
    "harness_command, include_nanoclaw, include_advanced_autonomy, "
    "include_two_stage_review) have non-default values in this project's "
    "answers file. Confirming sets both accept_security_overrides=true "
    "(Spec 090) and accept_security_overrides_confirmed=true (Spec 437 "
    "runtime token) in the constructed copier invocation."
)

QUESTION_SPEC_437_RUNTIME = (
    "Apply the runtime security-override consent token? (yes/no)"
)
RATIONALE_SPEC_437_RUNTIME = (
    "Spec 437 requires accept_security_overrides_confirmed=true as a "
    "runtime --data flag whenever accept_security_overrides=true is in "
    "effect. Folded into the Spec 090 question in chat presentation."
)

QUESTION_UNKNOWN_VALIDATOR = (
    "Copier rejected the update with a validator error this version of "
    "FORGE does not yet recognize. Show the parsed message and choose? (yes/no)"
)
RATIONALE_UNKNOWN_VALIDATOR = (
    "Fallback gate for validator errors not modeled by detect_gates(). "
    "Triggers the error-fallback flow in /forge stoke."
)


KNOWN_GATE_KINDS: set[str] = {
    "copier-tasks-trust",
    "spec-090-security-override",
    "spec-437-runtime-consent",
    "unknown-validator",
}


# Hard-coded set of security-gated keys (Spec 090 + Spec 437 surface).
# These are the keys whose `validator:` declarations in copier.yml reference
# accept_security_overrides. Keeping them here as a FORGE-controlled list
# avoids re-parsing template-controlled validator predicates at runtime.
SECURITY_GATED_KEYS: tuple[str, ...] = (
    "test_command",
    "lint_command",
    "harness_command",
    "include_nanoclaw",
    "include_advanced_autonomy",
    "include_two_stage_review",
)


@dataclass(frozen=True)
class Gate:
    """One gate that will fire on the next `copier update`."""
    kind: str
    label: str
    rationale: str
    operator_question: str
    copier_data_keys_to_set_on_yes: tuple[str, ...]

    def to_dict(self) -> dict:
        d = asdict(self)
        d["copier_data_keys_to_set_on_yes"] = list(self.copier_data_keys_to_set_on_yes)
        return d


# ---- copier.yml parsing helpers ---------------------------------------------

_TASKS_HEADER_RE = re.compile(r"^_tasks\s*:\s*$")
_TOP_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:")
_DEFAULT_RE = re.compile(r"^\s+default\s*:\s*(.*)$")


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _copier_yml(template_src_path: str) -> Path:
    p = Path(template_src_path) / "copier.yml"
    if not p.is_file():
        raise FileNotFoundError(f"copier.yml not found at {p}")
    return p


def _has_tasks(copier_yml_text: str) -> bool:
    """True iff copier.yml contains a non-empty `_tasks:` block."""
    lines = copier_yml_text.splitlines()
    in_tasks = False
    for raw in lines:
        if not in_tasks:
            if _TASKS_HEADER_RE.match(raw):
                in_tasks = True
            continue
        # In _tasks block.
        if raw.startswith(("  -", "  ", "\t")):
            stripped = raw.strip()
            if stripped and not stripped.startswith("#"):
                return True
            continue
        # Hit next top-level key.
        if raw and not raw.startswith((" ", "\t")):
            return False
    return False


def _parse_defaults(copier_yml_text: str) -> dict[str, str]:
    """Best-effort: map top-level question key → string form of default value.

    Used to compare against consumer's .copier-answers.yml. Booleans become
    "true"/"false"; bare strings are stripped of surrounding quotes.
    """
    out: dict[str, str] = {}
    current_key: str | None = None
    for raw in copier_yml_text.splitlines():
        stripped_no_indent = raw.rstrip()
        if not stripped_no_indent or stripped_no_indent.lstrip().startswith("#"):
            continue
        # Top-level key
        if not raw.startswith((" ", "\t")) and ":" in raw:
            m = _TOP_KEY_RE.match(raw)
            if m:
                key = m.group(1)
                if key.startswith("_"):
                    current_key = None
                else:
                    current_key = key
            continue
        if current_key is None:
            continue
        m = _DEFAULT_RE.match(raw)
        if m:
            val = m.group(1).strip().strip('"').strip("'")
            out[current_key] = val
            current_key = None  # one default per key
    return out


def _read_answers(consumer_root: Path) -> dict[str, str]:
    """Minimal .copier-answers.yml parser — string-form values only."""
    p = consumer_root / ".copier-answers.yml"
    if not p.is_file():
        return {}
    out: dict[str, str] = {}
    for raw in p.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if line.startswith(" ") or line.startswith("\t"):
            continue
        if ":" in line:
            k, _, v = line.partition(":")
            k = k.strip()
            v = v.strip().strip('"').strip("'")
            if k and v != "":
                out[k] = v
    return out


def _norm(v: str) -> str:
    return v.strip().lower()


# ---- public API -------------------------------------------------------------


def list_tasks(template_src_path: str) -> list[str]:
    """Spec 428 compat wrapper. Returns one human-readable task name per
    `_tasks:` entry, or [] when absent.

    Thin wrapper around the existing `_read_copier_tasks` helper in stoke.py
    (kept as a single source of truth — this module delegates rather than
    duplicates the parser).
    """
    # Import lazily to avoid circular imports during package load.
    import sys
    pkg_parent = Path(__file__).resolve().parent.parent
    if str(pkg_parent) not in sys.path:
        sys.path.insert(0, str(pkg_parent))
    try:
        import stoke as _legacy  # type: ignore[import-not-found]
        return _legacy._read_copier_tasks(_copier_yml(template_src_path))
    except (ImportError, AttributeError):
        # Fallback: enumerate tasks ourselves (less rich names than the
        # legacy parser, but functional).
        text = _read_text(_copier_yml(template_src_path))
        names: list[str] = []
        in_tasks = False
        for raw in text.splitlines():
            if not in_tasks:
                if _TASKS_HEADER_RE.match(raw):
                    in_tasks = True
                continue
            if raw and not raw.startswith((" ", "\t")):
                break
            stripped = raw.strip()
            if stripped.startswith("- "):
                names.append(stripped[2:].strip().strip('"').strip("'"))
        return names


def detect_gates(consumer_root: Path, template_src_path: str) -> list[Gate]:
    """Enumerate gates that will fire on the next `copier update` in
    `consumer_root` against `template_src_path`.

    Returns a list of Gate objects in fixed order:
        1. copier-tasks-trust (if applicable)
        2. spec-090-security-override (if applicable)
        3. spec-437-runtime-consent (if applicable)

    The chat layer is responsible for collapsing 2+3 into a single operator
    question per AC 2. The detector emits them separately so the helper
    output (Req 1, AC 1) carries enough structure for downstream consumers.
    """
    consumer_root = Path(consumer_root)
    yml = _copier_yml(template_src_path)
    text = _read_text(yml)
    gates: list[Gate] = []

    # Gate 1: copier-tasks-trust
    if _has_tasks(text):
        gates.append(Gate(
            kind="copier-tasks-trust",
            label="--trust required for _tasks:",
            rationale=RATIONALE_COPIER_TASKS_TRUST,
            operator_question=QUESTION_COPIER_TASKS_TRUST,
            copier_data_keys_to_set_on_yes=(),  # --trust is a flag, not --data
        ))

    # Gate 2: spec-090-security-override
    defaults = _parse_defaults(text)
    answers = _read_answers(consumer_root)
    customized: list[str] = []
    for key in SECURITY_GATED_KEYS:
        if key not in answers:
            continue
        default_val = defaults.get(key, "")
        if _norm(answers[key]) != _norm(default_val):
            customized.append(key)

    if customized:
        rationale = (
            RATIONALE_SPEC_090_SECURITY
            + f" Customized keys: {', '.join(customized)}."
        )
        gates.append(Gate(
            kind="spec-090-security-override",
            label="Spec 090 security override",
            rationale=rationale,
            operator_question=QUESTION_SPEC_090_SECURITY,
            copier_data_keys_to_set_on_yes=(
                "accept_security_overrides=true",
            ),
        ))

        # Gate 3: spec-437-runtime-consent — folds into gate 2 in chat
        # (AC 2: operator sees one question), but emitted separately in
        # helper output so downstream consumers can see the structure.
        gates.append(Gate(
            kind="spec-437-runtime-consent",
            label="Spec 437 runtime consent token",
            rationale=RATIONALE_SPEC_437_RUNTIME,
            operator_question=QUESTION_SPEC_437_RUNTIME,
            copier_data_keys_to_set_on_yes=(
                "accept_security_overrides_confirmed=true",
            ),
        ))
    elif _norm(answers.get("accept_security_overrides", "false")) == "true":
        # Edge case: consumer already has accept_security_overrides=true
        # but no specific security-gated key is non-default vs the
        # template default. Still need spec-437 runtime token.
        gates.append(Gate(
            kind="spec-437-runtime-consent",
            label="Spec 437 runtime consent token",
            rationale=RATIONALE_SPEC_437_RUNTIME,
            operator_question=QUESTION_SPEC_437_RUNTIME,
            copier_data_keys_to_set_on_yes=(
                "accept_security_overrides_confirmed=true",
            ),
        ))

    return gates


def unknown_validator_gate(parsed_message: str) -> Gate:
    """Construct a fallback Gate for an unrecognized validator error.

    Called by the chat layer when `copier update` exits non-zero with a
    validator error not modeled by detect_gates(). The parsed message is
    placed in the rationale; operator-visible question text is the FORGE
    constant.
    """
    rationale = (
        RATIONALE_UNKNOWN_VALIDATOR
        + f" Parsed validator message: {parsed_message[:280]}"
    )
    return Gate(
        kind="unknown-validator",
        label="Unrecognized validator",
        rationale=rationale,
        operator_question=QUESTION_UNKNOWN_VALIDATOR,
        copier_data_keys_to_set_on_yes=(),
    )

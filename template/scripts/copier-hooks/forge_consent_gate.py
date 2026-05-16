#!/usr/bin/env python3
"""Spec 437 — Copier bootstrap-path consent gate (secondary).

Runs as the FIRST entry in `_tasks:` (before scrub_answers.py and migrate-to-derived-view.py)
on every `copier copy` and `copier update` invocation. Closes Req 1a (poisoned-token
regression) that the per-question validator on `accept_security_overrides` cannot
detect alone.

Mechanism: reads the destination's `.copier-answers.yml` at task time. Copier does
NOT overwrite an operator-authored `.copier-answers.yml`, so any poisoned consent
token persisted there is still on disk at task time. Legitimate consent supplied
via `--data accept_security_overrides_confirmed=true` does NOT write into that file
(the question is `secret: true`), so its absence from disk + truthy at task time
proves CLI-source provenance.

Arguments (positional, Jinja-rendered by Copier in copier.yml):
    sys.argv[1] = accept_security_overrides (rendered "True"/"False")
    sys.argv[2] = accept_security_overrides_confirmed (rendered "True"/"False")
    sys.argv[3] = destination directory (`{{ _copier_conf.dst_path }}`)
    sys.argv[4] = copier operation (`{{ _copier_operation }}` — "copy" or "update")
                  Spec 445: gate skips on "update" because runtime tokens only reach
                  copier's new-worker, not the old-worker rebuild. Update mode trusts
                  the persisted answers file (consent was given at original write
                  time; PR-review catches malicious in-tree modifications).
    sys.argv[5..] = "key=value" pairs for each non-default security-gated override
                   (for Req 1b literal-command-string display in the refusal message)

Exit codes:
    0 — no gate trip (no override, or legitimate consent path)
    1 — gate tripped: refusing render (consent absent OR poisoned token detected)
    2 — internal error (missing required argv, etc.)

See:
    docs/specs/437-copier-bootstrap-path-consent-surface.md
    docs/decisions/ADR-028-copier-when-answer-persistence-security-gated-flags.md
    docs/process-kit/copier-gotchas.md § Spec 437 consent gate
"""
from __future__ import annotations

import pathlib
import sys


CONSENT_KEY = "accept_security_overrides_confirmed"
FLAG_KEY = "accept_security_overrides"


def _emit(msg: str) -> None:
    sys.stderr.write(msg)
    sys.stderr.write("\n")


def _refuse(reason_lines: list[str]) -> None:
    _emit("")
    _emit("=" * 72)
    _emit("Spec 437 SECURITY GATE — refusing copier render")
    _emit("=" * 72)
    for line in reason_lines:
        _emit(line)
    _emit("=" * 72)
    sys.exit(1)


def _parse_bool(val: str) -> bool:
    return val.strip().lower() in ("true", "1", "yes")


def _answers_file_contains_consent_token(dest: pathlib.Path) -> bool:
    """True if the destination's `.copier-answers.yml` carries the consent token.

    Read line-by-line rather than YAML-parse so a malformed file still trips the
    gate. A line whose first non-comment token is the consent key indicates a
    persisted (and therefore answers-file-sourced) consent value.
    """
    answers_path = dest / ".copier-answers.yml"
    if not answers_path.exists():
        return False
    try:
        text = answers_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        head = stripped.split(":", 1)[0].strip()
        if head == CONSENT_KEY:
            return True
    return False


def main() -> None:
    if len(sys.argv) < 4:
        _emit(
            "forge_consent_gate.py: internal error — expected at least 3 args "
            "(accept_security_overrides, accept_security_overrides_confirmed, dest_path)"
        )
        sys.exit(2)

    accept_flag = _parse_bool(sys.argv[1])
    consent_value = _parse_bool(sys.argv[2])
    dest = pathlib.Path(sys.argv[3]).resolve()
    # Spec 445: argv[4] is the copier operation ("copy" | "update"). Older
    # templates / older copier versions that don't pass it default to empty
    # string → backward-compat fresh-copy semantics.
    operation = sys.argv[4].strip().lower() if len(sys.argv) >= 5 else ""
    overrides = sys.argv[5:] if len(sys.argv) >= 5 else sys.argv[4:]

    if not accept_flag:
        return  # backward-compat: no override → no gate (Req 4)

    # Empty-string args from the Jinja `{% if ... %}...{% endif %}` shape become
    # positional argv entries; filter them out so the refusal message is clean.
    override_lines = [f"    {kv}" for kv in overrides if kv.strip()]
    if not override_lines:
        override_lines = ["    (none -- only the flag itself)"]

    # Req 1a (primary) -- answers-file-supplied consent token is REJECTED.
    # This check is ACTIVE on BOTH copy AND update (Spec 445 Req 2): a poisoned
    # answers file is still a threat at update time even though the in-tree
    # diff is PR-reviewable, because the gate is defense-in-depth.
    if _answers_file_contains_consent_token(dest):
        reason = [
            f"Detected `{CONSENT_KEY}` persisted in",
            f"  {dest / '.copier-answers.yml'}",
            "",
            "This key MUST come from the CLI at render time, not from a file.",
            "Spec 437 Req 1a: the answers-file-supplied consent token is rejected",
            "by design, because an attacker with write access to .copier-answers.yml",
            f"could otherwise pre-position `{CONSENT_KEY}: true` and",
            "bypass the gate. The question is marked `secret: true` so legitimate",
            "CLI consent values are never persisted to the answers file.",
            "",
            "Remediation:",
            f"  1. Remove the `{CONSENT_KEY}` line from .copier-answers.yml.",
            "  2. Re-run with:",
            f"       copier copy ... --data {CONSENT_KEY}=true",
            "     (or `copier update --data ...` for the update path)",
            "",
            "Security-gated overrides currently in scope:",
        ]
        reason.extend(override_lines)
        _refuse(reason)

    # Spec 445: secondary "consent absent" check skipped during `copier update`.
    # Rationale: during update, copier renders TWICE — once for the old-worker
    # rebuild (reconstructs previous state from .copier-answers.yml alone for
    # diff computation), then once for the new-worker apply. Runtime tokens
    # passed via `--data accept_security_overrides_confirmed=true` ONLY reach
    # the new-worker apply, not the old-worker rebuild. Tripping the secondary
    # check during old-worker rebuild aborts the update before any diff is
    # computed — a category error: we're not asking for fresh consent, we're
    # reconstructing previously-consented state. PR-review covers the threat
    # of in-tree answers-file tampering at update time. Spec 437 Req 1a
    # poisoned-token check (above) stays active on update — that's the
    # load-bearing defense against fresh malicious modifications.
    if operation == "update":
        return  # PASS — update mode trusts the persisted answers file

    # Secondary -- consent absent AND flag set. The per-question validator should
    # already have caught this at answer-resolution time, but this is defense-in-
    # depth in case a future template change moves the validator scope.
    if not consent_value:
        reason = [
            f"`{FLAG_KEY}=true` is set but no runtime consent was supplied.",
            "",
            "Security-gated overrides that would be applied:",
        ]
        reason.extend(override_lines)
        reason.extend(
            [
                "",
                "Re-run with:",
                f"  copier copy ... --data {CONSENT_KEY}=true",
            ]
        )
        _refuse(reason)


if __name__ == "__main__":
    main()

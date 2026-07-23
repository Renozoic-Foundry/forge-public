#!/usr/bin/env python3
# forge:path-literal-ok (file: docstring prose pointing to the Spec 591 evidence doc — classic-default process-kit spelling, mirrors upgrade_merge.py)
"""Spec 559 — generic non-persisted-token consent-gate library.
Spec 591 — wired LIVE (`.forge/lib/stoke.py::_live_gate_six_keys`,
called from `cmd_apply` ahead of both the classic and merge-native apply
backends). See docs/specs/591-plugin-primary-functional-cutover.md ## Evidence
for the call-site audit table.

A generic, key-agnostic consent primitive functionally equivalent to
`scripts/copier-hooks/forge_consent_gate.py`'s poisoned-answers-file defense
(Spec 090/437/445/447/448 threat model), proven against the six consent-gated
keys (`test_command`, `lint_command`, `harness_command`, `include_nanoclaw`,
`include_advanced_autonomy`, `include_two_stage_review`) via fixtures/tests,
and now (Spec 591) also live-invoked from `/forge stoke`'s `apply` subcommand.

**Spec 559 built this library but did not wire it live.** Spec 591 wires it
in as the live gate at the `/forge stoke apply` call site.
`forge_consent_gate.py` and copier's `secret: true` render path remain in
place as the render-time BACKSTOP (Spec 591 scope) — Spec 558 is the
separate, later, MAJOR-gated spec that deletes that backstop once this live
path has soaked.

Threat model (mirrors forge_consent_gate.py Req 1a): a persisted, file-sourced
consent token is REFUSED (an attacker with write access to a state file could
otherwise pre-position `key: true` and bypass the gate); a CLI-only-supplied
token (absent from the state file) is ACCEPTED as legitimate operator intent
at invocation time.

Stdlib only (ADR-359).

Usage:
    forge-py .forge/lib/runtime_consent_gate.py check \
        --key <named-key> --state-file PATH [--cli-value true|false]

Exit codes: 0 = consent accepted; 1 = consent refused (persisted token found,
or no CLI consent supplied).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

NAMED_KEYS = (
    "test_command",
    "lint_command",
    "harness_command",
    "include_nanoclaw",
    "include_advanced_autonomy",
    "include_two_stage_review",
)


def _parse_bool(val: str) -> bool:
    return val.strip().lower() in ("true", "1", "yes")


def _state_file_has_key(state_file: Path, key: str) -> bool:
    """True if `key` appears as a top-level `key: value` line in state_file.

    Line-by-line read (not YAML-parsed) so a malformed file still trips the
    gate -- same defense posture as forge_consent_gate.py's
    `_answers_file_contains_consent_token`.
    """
    if not state_file.is_file():
        return False
    try:
        text = state_file.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        head = stripped.split(":", 1)[0].strip()
        if head == key:
            return True
    return False


def check_consent(key: str, state_file: Path, cli_value: bool) -> tuple[bool, str]:
    """Returns (accepted, reason).

    - persisted token for `key` in `state_file` -> REFUSED, regardless of cli_value.
    - `key` absent from `state_file` AND cli_value truthy -> ACCEPTED.
    - otherwise -> REFUSED (no consent).
    """
    if _state_file_has_key(state_file, key):
        return False, (
            f"REFUSED: '{key}' found persisted in {state_file} -- consent must "
            "come from the CLI at invocation time, not a file (poisoned-token defense, "
            "mirrors forge_consent_gate.py Req 1a)."
        )
    if cli_value:
        return True, f"ACCEPTED: '{key}' supplied via CLI, not persisted."
    return False, f"REFUSED: '{key}' not supplied via CLI and not persisted (no consent)."


def cmd_check(args: argparse.Namespace) -> int:
    accepted, reason = check_consent(args.key, Path(args.state_file), _parse_bool(args.cli_value))
    print(reason)
    return 0 if accepted else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="Spec 559 generic runtime consent gate (live-wired from stoke.py per Spec 591)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("check", help="check consent for one named key")
    c.add_argument("--key", required=True, choices=NAMED_KEYS)
    c.add_argument("--state-file", required=True)
    c.add_argument("--cli-value", default="false")
    c.set_defaults(func=cmd_check)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

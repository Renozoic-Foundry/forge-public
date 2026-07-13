#!/usr/bin/env python3
"""FORGE autopilot-envelope validator core (Spec 531 / ADR-531 as amended 2026-07-07).

Validates the minimal `forge.autopilot` envelope declared in AGENTS.md:

    forge.autopilot:
      scheduled: { enabled: false }
      terminal_state: implemented

Checks (always-strict — no advisory mode):
  * `scheduled.enabled: true` requires a matching consent entry in
    docs/sessions/config-change-audit.md — matching means the entry names
    `forge.autopilot.scheduled` AND carries `Outcome: applied`.
    HONESTY (tier-qualified, CISO 2026-07-07): this audit-entry check is a
    SPEED BUMP against accidental self-modification, NOT a security boundary —
    the audit file is agent-writable. The enforcement primitive for close/push
    stays the harness authorization-required list and the push guard.
  * `terminal_state` must be `implemented`.
  * No unknown keys under `forge.autopilot`; values must be well-typed.
  * An unparseable block FAILS CLOSED.

Exit codes: 0 = valid (or block absent — consumer-safe silence);
2 = parse failure (fail closed); 3 = consent missing/non-matching;
4 = unknown key / invalid value.

Usage: forge-py .forge/lib/autopilot_envelope.py [--agents-md AGENTS.md]
                                                 [--audit docs/sessions/config-change-audit.md]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

if sys.version_info < (3, 10):
    sys.stderr.write("error: Python 3.10+ required\n")
    sys.exit(2)

try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    sys.stderr.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except (AttributeError, OSError):
    pass

SPEED_BUMP = (
    "note: the consent check is a speed bump against accidental self-modification, "
    "not a security boundary (the audit file is agent-writable; the harness "
    "authorization-required list and push guard remain the enforcement primitives)"
)

ALLOWED_TOP_KEYS = {"scheduled", "terminal_state"}
ALLOWED_SCHEDULED_KEYS = {"enabled"}


def extract_block(agents_text: str) -> str | None:
    """Isolate the yaml fence that CONTAINS a top-level `forge.autopilot:` key.

    AGENTS.md carries multiple ```yaml fences; only the one whose content has
    `forge.autopilot:` at column 0 is ours. Returns the fence body, or None
    when no fence declares the envelope (absent-block = consumer-safe).
    """
    for m in re.finditer(r"```yaml\n(.*?)```", agents_text, re.DOTALL):
        body = m.group(1)
        if re.search(r"^forge\.autopilot:", body, re.MULTILINE):
            return body
    return None


def audit_has_consent(audit_path: Path) -> bool:
    """True when the audit log contains an entry naming forge.autopilot.scheduled
    with Outcome: applied. Presence-and-shape only — authenticity is out of scope
    (see SPEED_BUMP)."""
    try:
        text = audit_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    # Entry granularity: split on markdown headings; a matching entry must carry
    # both markers within the same entry, not merely somewhere in the file.
    entries = re.split(r"^#{2,3} ", text, flags=re.MULTILINE)
    for entry in entries:
        if "forge.autopilot.scheduled" in entry and re.search(
            r"Outcome:\s*applied", entry, re.IGNORECASE
        ):
            return True
    return False


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Validate the forge.autopilot envelope")
    p.add_argument("--agents-md", default="AGENTS.md")
    p.add_argument("--audit", default="docs/sessions/config-change-audit.md")
    args = p.parse_args(argv)

    agents_path = Path(args.agents_md)
    if not agents_path.is_file():
        # No AGENTS.md at all — nothing to validate (consumer-safe silence).
        return 0
    text = agents_path.read_text(encoding="utf-8", errors="replace")

    block = extract_block(text)
    if block is None:
        return 0  # absent block — silent, consumer-safe (Spec 531 R2)

    try:
        import yaml  # PyYAML — same dependency strategic-scope.py uses
    except ImportError:
        print("check-autopilot-envelope: FAIL — PyYAML unavailable; cannot validate "
              "the declared envelope (fail closed)", file=sys.stderr)
        return 2

    try:
        data = yaml.safe_load(block)
    except yaml.YAMLError as e:
        print(f"check-autopilot-envelope: FAIL — forge.autopilot block is unparseable "
              f"YAML (fail closed): {e}", file=sys.stderr)
        return 2

    env = (data or {}).get("forge.autopilot")
    if env is None or not isinstance(env, dict):
        print("check-autopilot-envelope: FAIL — forge.autopilot key present but not a "
              "mapping (fail closed)", file=sys.stderr)
        return 2

    unknown = set(env.keys()) - ALLOWED_TOP_KEYS
    if unknown:
        print(f"check-autopilot-envelope: FAIL — unknown key(s) under forge.autopilot: "
              f"{' '.join(sorted(unknown))} (adding fields requires a spec, not a "
              f"config edit — see authority-constitution-guide.md)", file=sys.stderr)
        return 4

    terminal = env.get("terminal_state")
    if terminal != "implemented":
        print(f"check-autopilot-envelope: FAIL — terminal_state must be 'implemented' "
              f"(got: {terminal!r}). /autopilot never advances past implemented; close "
              f"is operator-only (EA-025/026/027).", file=sys.stderr)
        return 4

    sched = env.get("scheduled")
    if not isinstance(sched, dict) or set(sched.keys()) - ALLOWED_SCHEDULED_KEYS:
        print("check-autopilot-envelope: FAIL — scheduled must be a mapping with only "
              "'enabled'", file=sys.stderr)
        return 4
    enabled = sched.get("enabled")
    if not isinstance(enabled, bool):
        print(f"check-autopilot-envelope: FAIL — scheduled.enabled must be a boolean "
              f"(got: {enabled!r})", file=sys.stderr)
        return 4

    if enabled:
        if not audit_has_consent(Path(args.audit)):
            print("check-autopilot-envelope: FAIL — scheduled.enabled is true but "
                  "docs/sessions/config-change-audit.md has no entry naming "
                  "forge.autopilot.scheduled with Outcome: applied. Run /config-change "
                  f"first (3-step runbook: authority-constitution-guide.md). {SPEED_BUMP}",
                  file=sys.stderr)
            return 3
        print(f"check-autopilot-envelope: OK — scheduled enabled with a matching "
              f"config-change audit entry. {SPEED_BUMP}")
        return 0

    print("check-autopilot-envelope: OK — envelope default-safe (scheduled off, "
          "terminal_state=implemented)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

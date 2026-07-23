#!/usr/bin/env python3
"""Spec 559 — one-shot copier-era -> merge-native state migration.

Translates copier-era on-disk state (`.copier-answers.yml`'s `_commit` and
`_acknowledged_legacy_artifacts`) into the merge-native mechanism's state
format, idempotently. This is the one-time bridge a project crosses when it
first runs `/forge stoke --merge-native`.

Idempotent (Req 5): first run against a copier-era project reports "migrated"
and writes the marker file; a second run against the same project reports
"already migrated" and makes zero additional file changes.

Stdlib only (ADR-359).

Usage:
    forge-py .forge/lib/upgrade_migrate_once.py migrate \
        [--project-root DIR] [--answers PATH] [--marker PATH]

Exit codes: 0 = migrated OR already-migrated (both are success); 2 = IO error.
"""
from __future__ import annotations

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

DEFAULT_MARKER = ".forge/state/upgrade-migrated.json"
DEFAULT_ANSWERS = ".copier-answers.yml"


def _parse_commit(text: str) -> str | None:
    m = re.search(r"^_commit:\s*(.+?)\s*$", text, re.M)
    if not m:
        return None
    return m.group(1).strip().strip("\"'") or None


def _parse_ack_list(text: str) -> list[str]:
    """Parse `_acknowledged_legacy_artifacts` in either flow or block YAML style."""
    m = re.search(r"^_acknowledged_legacy_artifacts:\s*\[(.*?)\]\s*$", text, re.M)
    if m:
        return [x.strip().strip("\"'") for x in m.group(1).split(",") if x.strip()]
    m = re.search(r"^_acknowledged_legacy_artifacts:\s*$\n((?:^[ \t]*-[ \t]*.+$\n?)*)", text, re.M)
    if m:
        items = []
        for line in m.group(1).splitlines():
            lm = re.match(r"^[ \t]*-[ \t]*(.+?)\s*$", line)
            if lm:
                items.append(lm.group(1).strip().strip("\"'"))
        return items
    return []


def cmd_migrate(args: argparse.Namespace) -> int:
    project_root = Path(args.project_root)
    marker_path = project_root / args.marker
    answers_path = project_root / args.answers

    if marker_path.is_file():
        print("already migrated")
        return 0

    commit = None
    ack: list[str] = []
    if answers_path.is_file():
        try:
            text = answers_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""
        commit = _parse_commit(text)
        ack = _parse_ack_list(text)

    marker_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "migrated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source_commit": commit,
        "acknowledged_legacy_artifacts": ack,
    }
    marker_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print("migrated")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Spec 559 one-shot copier-era -> merge-native migration")
    sub = ap.add_subparsers(dest="cmd", required=True)

    m = sub.add_parser("migrate", help="run the one-shot migration (idempotent)")
    m.add_argument("--project-root", default=".")
    m.add_argument("--answers", default=DEFAULT_ANSWERS)
    m.add_argument("--marker", default=DEFAULT_MARKER)
    m.set_defaults(func=cmd_migrate)

    args = ap.parse_args()
    try:
        return args.func(args)
    except OSError as exc:
        print(f"upgrade_migrate_once: IO error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

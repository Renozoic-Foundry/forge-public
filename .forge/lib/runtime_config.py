#!/usr/bin/env python3
"""FORGE non-security runtime-config resolver (Spec 557 — ADR-502 Phase-2 slice 1).

Resolves project-identity vars (NON-security only: name, slug, description,
author, owner) at runtime, replacing their render-time Copier baking.

Resolution order (Spec 557 Req 7):
  1. AGENTS.md `forge.project:` YAML block (the Spec 557 runtime block)
  2. `.copier-answers.yml` (classic-mode fallback — backward-compat, AC4;
     answers keys: project_name, project_slug, project_description, author,
     default_owner)
  3. Documented built-in defaults: name/slug derived from the project dir name,
     empty strings elsewhere (neither-source-present case, AC6b).

A malformed source falls through to the next one — never a crash.

SECURITY BOUNDARY (consensus R1 reframe, operator-ratified 2026-07-14): the six
consent-gated keys (test_command, lint_command, harness_command, include_nanoclaw,
include_advanced_autonomy, include_two_stage_review) are deliberately NOT
resolvable here. They stay render-gated via forge_consent_gate.py (secret:true).
Requests for them exit 4.

Usage:
    forge-py .forge/lib/runtime_config.py get <key> [--dir DIR]
    forge-py .forge/lib/runtime_config.py all [--dir DIR]

Exit codes: 0 ok; 3 unknown key; 4 consent-gated key refused.
Stdlib only (ADR-359).
"""
import argparse
import json
import re
import sys
from pathlib import Path

KEYS = ("name", "slug", "description", "author", "owner")
ANSWERS_MAP = {
    "name": "project_name",
    "slug": "project_slug",
    "description": "project_description",
    "author": "author",
    "owner": "default_owner",
}
CONSENT_GATED = (
    "test_command",
    "lint_command",
    "harness_command",
    "include_nanoclaw",
    "include_advanced_autonomy",
    "include_two_stage_review",
)


def _parse_project_block(agents_md: Path):
    """Extract the forge.project: block from AGENTS.md. None on absence/malformed."""
    try:
        text = agents_md.read_text(encoding="utf-8")
    except OSError:
        return None
    m = re.search(r"^forge\.project:\s*$((?:\n[ \t]+\S[^\n]*)+)", text, re.M)
    if not m:
        return None
    out = {}
    for line in m.group(1).splitlines():
        km = re.match(r"^[ \t]+([a-z_]+):[ \t]*(.*)$", line)
        if km:
            out[km.group(1)] = km.group(2).strip().strip("\"'")
    return out or None


def _parse_answers(answers: Path):
    """Minimal .copier-answers.yml key: value parse. None on absence/malformed."""
    try:
        text = answers.read_text(encoding="utf-8")
    except OSError:
        return None
    out = {}
    for line in text.splitlines():
        km = re.match(r"^([A-Za-z_]+):[ \t]*(.*)$", line)
        if km:
            out[km.group(1)] = km.group(2).strip().strip("\"'")
    return out or None


def _defaults(project_dir: Path):
    name = project_dir.resolve().name
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "project"
    return {"name": name, "slug": slug, "description": "", "author": "", "owner": ""}


def resolve_all(project_dir: Path) -> dict:
    result = _defaults(project_dir)
    answers = _parse_answers(project_dir / ".copier-answers.yml")
    if answers:
        for key, akey in ANSWERS_MAP.items():
            if akey in answers and answers[akey]:
                result[key] = answers[akey]
    block = _parse_project_block(project_dir / "AGENTS.md")
    if block:
        for key in KEYS:
            if key in block and block[key]:
                result[key] = block[key]
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description="FORGE non-security runtime-config resolver")
    ap.add_argument("action", choices=["get", "all"])
    ap.add_argument("key", nargs="?")
    ap.add_argument("--dir", default=".")
    args = ap.parse_args()

    if args.action == "get":
        if args.key in CONSENT_GATED:
            print(
                f"runtime_config: '{args.key}' is consent-gated (render-time only via "
                "forge_consent_gate.py, secret:true) — not resolvable at runtime (Spec 557 slice 1).",
                file=sys.stderr,
            )
            return 4
        if args.key not in KEYS:
            print(f"runtime_config: unknown key '{args.key}' (known: {', '.join(KEYS)})", file=sys.stderr)
            return 3
        print(resolve_all(Path(args.dir))[args.key])
        return 0

    print(json.dumps(resolve_all(Path(args.dir)), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

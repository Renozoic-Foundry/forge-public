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
    forge-py .forge/lib/runtime_config.py path <key> [--dir DIR]

The `path` action (Spec 564) resolves forge.paths.{specs,sessions,decisions,research,
process_kit,backlog} from the nested `forge: paths:` subsection of the AGENTS.md
`## Runtime Configuration` fenced YAML — a NEW nested-block parser, distinct from the
flat `forge.project:` parser above (DA 2026-07-16). This file is the SINGLE python-side
definition point for process-state path defaults (Req 2); bash twin: config.sh
forge_path(). Validation (CISO consensus findings): rejects backslashes, absolute /
drive-letter / UNC paths, `..` segments, and symlink escapes from the repo root.

Exit codes: 0 ok; 3 unknown key; 4 consent-gated key refused; 5 invalid path value.
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

# ---- Process-state path indirection (Spec 564) ----
PATH_DEFAULTS = {
    "specs": "docs/specs",
    "sessions": "docs/sessions",
    "decisions": "docs/decisions",
    "research": "docs/research",
    "process_kit": "docs/process-kit",
    "backlog": "docs/backlog.md",
}


def _parse_runtime_paths(agents_md: Path):
    """Extract forge: -> paths: keys from the ## Runtime Configuration fenced YAML.

    Returns {key: value} or {} on absence/malformed (defaults then apply). This is a
    deliberate minimal line-walker matching config.sh's forge_config_load semantics
    (section / one-level subsection / leaf), not a general YAML parser.
    """
    try:
        text = agents_md.read_text(encoding="utf-8")
    except OSError:
        return {}
    m = re.search(r"^## Runtime Configuration\b.*?```yaml\n(.*?)\n```", text, re.M | re.S)
    if not m:
        return {}
    out = {}
    section = subsection = None
    for line in m.group(1).splitlines():
        if re.match(r"^\s*#", line) or not line.strip():
            continue
        top = re.match(r"^([a-z_]+):\s*(.*?)\s*$", line)
        two = re.match(r"^  ([a-z_]+):\s*$", line)
        leaf = re.match(r"^\s+([a-z_]+):\s*(.*?)\s*$", line)
        if top:
            section, subsection = top.group(1), None
            continue
        if two:
            subsection = two.group(1)
            continue
        if leaf and section == "forge" and subsection == "paths":
            value = leaf.group(2).split("#", 1)[0].strip().strip("\"'")
            if value:
                out[leaf.group(1)] = value
    return out


def _validate_path_value(key: str, value: str, project_dir: Path):
    """Return an error string (naming the key) for an invalid forge.paths value, else None."""
    err = f"runtime_config: invalid forge.paths.{key} value '{value}':"
    if not value:
        return f"{err} empty value"
    if "\\" in value:
        return f"{err} backslash in path — values are repo-relative forward-slash paths"
    if value.startswith("/"):
        return f"{err} absolute or UNC path rejected (must be repo-relative)"
    if re.match(r"^[A-Za-z]:", value):
        return f"{err} drive-letter path rejected (must be repo-relative)"
    if ".." in value.split("/"):
        return f"{err} '..' segment rejected"
    try:
        root = project_dir.resolve()
        canon = (root / value).resolve()
    except OSError as exc:
        return f"{err} unresolvable ({exc})"
    if root != canon and root not in canon.parents:
        return f"{err} resolves outside the repo root (symlink escape) — '{canon}' not under '{root}'"
    return None


def resolve_path(project_dir: Path, key: str):
    """Resolve one forge.paths key. Returns (value, None) or (None, error-string)."""
    if key not in PATH_DEFAULTS:
        return None, (
            f"runtime_config: unknown path key '{key}' "
            f"(known: {', '.join(PATH_DEFAULTS)})"
        )
    configured = _parse_runtime_paths(project_dir / "AGENTS.md")
    value = configured.get(key) or PATH_DEFAULTS[key]
    error = _validate_path_value(key, value, project_dir)
    if error:
        return None, error
    return value, None


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
    ap.add_argument("action", choices=["get", "all", "path"])
    ap.add_argument("key", nargs="?")
    ap.add_argument("--dir", default=".")
    args = ap.parse_args()

    if args.action == "path":
        value, error = resolve_path(Path(args.dir), args.key or "")
        if error:
            print(error, file=sys.stderr)
            return 3 if error.startswith("runtime_config: unknown path key") else 5
        print(value)
        return 0

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

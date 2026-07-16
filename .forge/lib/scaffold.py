#!/usr/bin/env python3
"""FORGE greenfield scaffolder (Spec 557 — ADR-502 Phase-2 slice 1).

Writes a new project's project-data skeleton directly — zero Copier dependency.
The plugin delivers every executable surface; this writes only the project data
a fresh FORGE project needs: docs/specs/, docs/sessions/, docs/backlog.md, and
thin starter AGENTS.md / CLAUDE.md carrying the `forge.project:` runtime block
(schema per Spec 557 Req 7, read by runtime_config.py).

Overwrite guardrail (Spec 557 Req 1 / AC2): aborts without writing ANYTHING if
the target already contains AGENTS.md, docs/specs/, or .copier-answers.yml.

Usage:
    forge-py .forge/lib/scaffold.py TARGET_DIR [--name N] [--slug S]
        [--description D] [--author A] [--owner O]

Exit codes: 0 scaffolded; 2 guardrail abort (pre-existing project files);
            3 bad arguments / unwritable target.
Stdlib only (ADR-359).
"""
import argparse
import re
import sys
from pathlib import Path

GUARD_PATHS = ("AGENTS.md", "docs/specs", ".copier-answers.yml")

AGENTS_MD = """# Framework: FORGE
# AGENTS.md — primary-source agent operating doctrine

## Project Context

```yaml
# forge.project — non-security project identity (Spec 557 runtime block; read by
# .forge/lib/runtime_config.py — resolution: this block -> .copier-answers.yml -> defaults)
forge.project:
  name: {name}
  slug: {slug}
  description: {description}
  author: {author}
  owner: {owner}
```

```yaml
forge.strategic_scope: |
  SKIP-FOR-NOW
```

## Setup

This project consumes FORGE as a plugin — executable surfaces (commands, skills,
agents, hooks) come from the installed FORGE plugin, not from files in this repo.
Run /onboarding for first-session configuration; /forge:now to see project state.

## Two hard rules — no exceptions

1. Every change has a matching spec.
2. Every session ends with a session log.

## Spec lifecycle

`draft -> in-progress -> implemented -> closed | deprecated`
See the plugin's process-kit for gates, lanes, and evidence requirements.
"""

CLAUDE_MD = """# Framework: FORGE
@AGENTS.md
"""

SPECS_README = """# Specs Index

## Conventions

- Naming: `NNN-short-title.md`.
- Status values: `draft`, `in-progress`, `implemented`, `closed`, `deprecated`.

## Specs

(none yet — create the first with /forge:spec)
"""

CHANGELOG = """# Spec Changelog

(no entries yet)
"""

BACKLOG = """# Backlog

Last updated: (never — run /forge:matrix after your first spec)

| Rank | Spec | Title | BV | E | R | SR | Score | Depends | Status |
|------|------|-------|----|---|---|----|-------|---------|--------|
"""

SESSION_TEMPLATE = """# Session Log — YYYY-MM-DD-NNN

- Date: YYYY-MM-DD
- Session number: NNN
- Specs touched:
- Change lane(s):

## Summary

## Decisions made

## Process pain points

## Spec triggers
"""


def slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "project"


def main() -> int:
    ap = argparse.ArgumentParser(description="FORGE greenfield scaffolder (zero copier)")
    ap.add_argument("target")
    ap.add_argument("--name", default=None)
    ap.add_argument("--slug", default=None)
    ap.add_argument("--description", default="")
    ap.add_argument("--author", default="")
    ap.add_argument("--owner", default="")
    args = ap.parse_args()

    target = Path(args.target)
    if target.exists() and not target.is_dir():
        print(f"scaffold: target {target} exists and is not a directory", file=sys.stderr)
        return 3

    # Overwrite guardrail — check BEFORE any write (Req 1 / AC2).
    tripped = [g for g in GUARD_PATHS if (target / g).exists()]
    if tripped:
        print(
            "scaffold: ABORT — target already contains FORGE project files: "
            + ", ".join(tripped)
            + ". Nothing was written. Use /forge:stoke (copier-managed) or /forge:reconcile "
            "(existing history) instead of scaffolding over an existing project.",
            file=sys.stderr,
        )
        return 2

    name = args.name or target.resolve().name
    slug = args.slug or slugify(name)
    fields = dict(
        name=name,
        slug=slug,
        description=args.description,
        author=args.author,
        owner=args.owner,
    )

    files = {
        "AGENTS.md": AGENTS_MD.format(**fields),
        "CLAUDE.md": CLAUDE_MD,
        "docs/specs/README.md": SPECS_README,
        "docs/specs/CHANGELOG.md": CHANGELOG,
        "docs/backlog.md": BACKLOG,
        "docs/sessions/_template.md": SESSION_TEMPLATE,
        "docs/sessions/signals.md": "# Signals\n",
        "docs/sessions/scratchpad.md": "# Scratchpad\n",
        ".forge/state/.gitkeep": "",
    }
    try:
        for rel, content in files.items():
            p = target / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding="utf-8", newline="\n")
    except OSError as e:
        print(f"scaffold: write failed: {e}", file=sys.stderr)
        return 3

    print(f"scaffolded FORGE project '{name}' at {target} ({len(files)} files, zero copier)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

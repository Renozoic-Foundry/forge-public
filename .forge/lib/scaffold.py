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
        [--layout contained|classic]   (Spec 575 — default: contained)

Layouts (Spec 575): `contained` (default for new scaffolds) places all FORGE
process data under .forge/project/ and writes the forge.paths block + the
ownership manifest; `classic` reproduces the pre-575 docs/... layout
byte-identically (plus the additive .forge/ownership.yaml).

Exit codes: 0 scaffolded; 2 guardrail abort (pre-existing project files);
            3 bad arguments / unwritable target.
Stdlib only (ADR-359).
"""
import argparse
import re
import sys
from pathlib import Path

# Guardrail checks BOTH layouts' spec locations regardless of the requested
# layout (Spec 575) — scaffolding over either shape is refused.
GUARD_PATHS = ("AGENTS.md", "docs/specs", ".forge/project/specs", ".copier-answers.yml")

# Spec 575 — layout presets over the Spec 564 forge.paths.* keys.
LAYOUT_PRESETS = {
    "classic": {
        "specs": "docs/specs",
        "sessions": "docs/sessions",
        "decisions": "docs/decisions",
        "research": "docs/research",
        "process_kit": "docs/process-kit",
        "backlog": "docs/backlog.md",
    },
    "contained": {
        "specs": ".forge/project/specs",
        "sessions": ".forge/project/sessions",
        "decisions": ".forge/project/decisions",
        "research": ".forge/project/research",
        "process_kit": ".forge/project/process-kit",
        "backlog": ".forge/project/backlog.md",
    },
}

# Rendered into the scaffolded AGENTS.md for non-classic layouts only — an
# absent block means classic defaults (behavior-neutral rule, Spec 564/575).
PATHS_BLOCK = """
## Runtime Configuration

```yaml
# forge.paths — process-state locations (Spec 564/575 `contained` preset).
# Resolve via forge_path (bash) / runtime_config.py path (python); do not hardcode.
forge:
  paths:
    specs: {specs}
    sessions: {sessions}
    decisions: {decisions}
    research: {research}
    process_kit: {process_kit}
    backlog: {backlog}
```
"""

OWNERSHIP_YAML = """# .forge/ownership.yaml — FORGE-owned path manifest (Spec 575, schema 1).
# Machine-readable partition of FORGE files vs solution files. Consumed by
# `forge-py .forge/lib/ownership.py --list` and the Spec 577 retrofit inventory.
# Classes: process-data | runtime-state | config | framework-doc
schema: 1
layout: {layout}
paths:
  - {{path: {specs}/, class: process-data}}
  - {{path: {sessions}/, class: process-data}}
  - {{path: {decisions}/, class: process-data}}
  - {{path: {research}/, class: process-data}}
  - {{path: {process_kit}/, class: process-data}}
  - {{path: {backlog}, class: process-data}}
  - {{path: .forge/state/, class: runtime-state}}
  - {{path: .forge/ownership.yaml, class: config}}
  - {{path: AGENTS.md, class: config}}
  - {{path: CLAUDE.md, class: config}}
  - {{path: bin/forge, class: config}}
  - {{path: bin/forge.ps1, class: config}}
  - {{path: {qr_path}, class: framework-doc}}
"""

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

**Non-Claude agents / CLI (Spec 576)**: command bodies live at the runtime root —
resolution chain: CLAUDE_PLUGIN_ROOT -> FORGE_RUNTIME_ROOT -> ~/.forge/runtime-root
(pointer file to a pinned framework checkout) -> project-local. Invoke any command as
`bin/forge <name>` (Windows: `bin\forge.ps1`). Optional integrity pin: add
`forge.runtime.pin: <tag-or-sha>` under Runtime Configuration — the launcher warns on
checkout mismatch.

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
    ap.add_argument("--layout", choices=("contained", "classic"), default="contained",
                    help="process-data layout (Spec 575; default: contained)")
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

    paths = LAYOUT_PRESETS[args.layout]
    agents_md = AGENTS_MD.format(**fields)
    if args.layout != "classic":
        # Absent block == classic defaults; only non-classic layouts write it.
        agents_md += PATHS_BLOCK.format(**paths)
    qr_path = ("docs/QUICK-REFERENCE.md" if args.layout == "classic"
               else f"{paths['process_kit']}/QUICK-REFERENCE.md")
    files = {
        "AGENTS.md": agents_md,
        "CLAUDE.md": CLAUDE_MD,
        f"{paths['specs']}/README.md": SPECS_README,
        f"{paths['specs']}/CHANGELOG.md": CHANGELOG,
        paths["backlog"]: BACKLOG,
        f"{paths['sessions']}/_template.md": SESSION_TEMPLATE,
        f"{paths['sessions']}/signals.md": "# Signals\n",
        f"{paths['sessions']}/scratchpad.md": "# Scratchpad\n",
        ".forge/state/.gitkeep": "",
        ".forge/ownership.yaml": OWNERSHIP_YAML.format(layout=args.layout, qr_path=qr_path, **paths),
    }
    try:
        for rel, content in files.items():
            p = target / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding="utf-8", newline="\n")
    except OSError as e:
        print(f"scaffold: write failed: {e}", file=sys.stderr)
        return 3

    # Spec 571 — ship the generated quick reference with the scaffold. The plugin
    # payload root (this script's ../../ — CLAUDE_PLUGIN_ROOT at runtime) carries
    # docs/QUICK-REFERENCE.md with its provenance/revision-history block; copy it
    # so consumers start with a current reference. Best-effort: absent source
    # (trimmed payload) skips silently — never fails the scaffold.
    copied = 0
    plugin_root = Path(__file__).resolve().parent.parent.parent
    # Spec 576 — ship the two thin cross-IDE launchers with every scaffold.
    for launcher in ("bin/forge", "bin/forge.ps1"):
        src = plugin_root / launcher
        if src.is_file():
            try:
                dst = target / launcher
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_text(src.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
                copied += 1
            except OSError:
                pass
    qr_src = plugin_root / "docs" / "QUICK-REFERENCE.md"
    if qr_src.is_file():
        try:
            qr_dst = target / qr_path
            qr_dst.parent.mkdir(parents=True, exist_ok=True)
            qr_dst.write_text(qr_src.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
            copied = 1
        except OSError:
            pass

    print(f"scaffolded FORGE project '{name}' at {target} "
          f"({len(files) + copied} files, zero copier)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

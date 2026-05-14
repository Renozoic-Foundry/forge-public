"""FORGE spec frontmatter parser (Spec 254 — Approach D).

Parses the leading frontmatter block from a spec file into a dict.

Spec files use a non-YAML "list-prefixed" frontmatter format:
    # Framework: FORGE
    # Spec NNN — Title

    - Status: in-progress
    - Change-Lane: `small-change`
    - Priority-Score: <!-- BV=N E=N R=N SR=N → score=NN -->
    - Trigger: ...
    - Dependencies: ...
    - Last updated: 2026-05-06
    - valid-until: 2026-08-01
    ...

This parser extracts those `- Field: value` lines into a flat dict, preserving the
raw value strings. It also extracts BV/E/R/SR from the Priority-Score HTML comment
when present.

The frontmatter block ends at the first `## ` heading or blank-line-followed-by-`#`
top-level marker after the title.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Optional

# `- Field: value` — captures field name and value (rest of line)
_FIELD_RE = re.compile(r"^-\s+([A-Za-z][A-Za-z0-9_/.-]*?):\s*(.*)$")
# Priority-Score HTML comment: <!-- BV=N E=N R=N SR=N → score=NN -->
_SCORE_RE = re.compile(
    r"BV\s*=\s*(\d+)\s+E\s*=\s*(\d+)\s+R\s*=\s*(\d+)\s+SR\s*=\s*(\d+)"
)


def parse_frontmatter(text: str) -> dict:
    """Parse the leading frontmatter block from a spec file's contents.

    Returns a dict with:
        - All `- Field: value` pairs (key normalized lowercase)
        - 'bv', 'e', 'r', 'sr', 'score' (ints) extracted from Priority-Score if present
        - 'title' (string) extracted from the second `# Spec NNN — Title` header
        - 'spec_id' (string) extracted from the `# Spec NNN` header

    Lines are scanned until the first `## ` H2 heading is encountered.
    """
    out: dict = {}
    for line in text.splitlines():
        stripped = line.rstrip()
        # Stop at first H2 — that's the body proper
        if stripped.startswith("## "):
            break
        # Title: # Spec NNN — Title  OR  # Spec NNN - Title
        if stripped.startswith("# Spec "):
            m = re.match(r"^# Spec\s+(\d+)\s*[—–\-]\s*(.+?)\s*$", stripped)
            if m:
                out.setdefault("spec_id", m.group(1))
                out.setdefault("title", m.group(2))
            continue
        # `- Field: value` pairs
        m = _FIELD_RE.match(stripped)
        if m:
            key = m.group(1).strip().lower().replace("-", "_")
            value = m.group(2).strip()
            out[key] = value
            # Extract score components
            if key == "priority_score":
                sm = _SCORE_RE.search(value)
                if sm:
                    out["bv"] = int(sm.group(1))
                    out["e"] = int(sm.group(2))
                    out["r"] = int(sm.group(3))
                    out["sr"] = int(sm.group(4))
                    out["score"] = (
                        out["bv"] * 3
                        + (6 - out["e"]) * 2
                        + (6 - out["r"]) * 2
                        + out["sr"]
                    )
    return out


def parse_spec_file(path: Path) -> Optional[dict]:
    """Read a spec file and return its parsed frontmatter dict (with 'path' added).

    Returns None if the file cannot be read.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    fm = parse_frontmatter(text)
    fm["path"] = str(path)
    if "spec_id" not in fm:
        # Fallback: derive from filename NNN-*.md
        m = re.match(r"^(\d+)-", path.name)
        if m:
            fm["spec_id"] = m.group(1)
    return fm


def iter_spec_files(specs_dir: Path) -> list[Path]:
    """Glob spec files matching NNN-*.md under specs_dir, sorted by spec id."""
    if not specs_dir.exists():
        return []
    files = []
    for p in specs_dir.glob("[0-9][0-9][0-9]-*.md"):
        if p.is_file():
            files.append(p)
    files.sort(key=lambda p: p.name)
    return files

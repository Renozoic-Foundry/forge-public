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
# Spec 493 (Defect A): trailing `<!-- … -->` strip — ReDoS-safe (non-greedy + end-anchored).
# Non-greedy `.*?` + `$` anchor over an already-`.strip()`ed single-line value ⇒ linear-time.
# An unterminated `<!--` (no closing `-->`) does NOT match and is left intact (no hang).
_COMMENT_RE = re.compile(r"\s*<!--.*?-->\s*$", re.DOTALL)


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
            m = re.match(r"^# Spec\s+(\d+[a-z]?)\s*[—–:\-]\s*(.+?)\s*$", stripped)
            if m:
                out.setdefault("spec_id", m.group(1))
                out.setdefault("title", m.group(2))
            continue
        # `- Field: value` pairs
        m = _FIELD_RE.match(stripped)
        if m:
            key = m.group(1).strip().lower().replace("-", "_")
            value = m.group(2).strip()
            # Extract score components from the RAW value FIRST (Priority-Score's
            # value legitimately IS an HTML comment), then strip.
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
            # Spec 493: strip AFTER _SCORE_RE — Priority-Score's value legitimately IS an HTML comment
            value = _COMMENT_RE.sub("", value)
            out[key] = value
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
        # Fallback: derive from filename NNN-*.md (or NNN[a-z]-*.md, Spec 493)
        m = re.match(r"^(\d+[a-z]?)-", path.name)
        if m:
            fm["spec_id"] = m.group(1)
    return fm


def iter_spec_files(specs_dir: Path) -> list[Path]:
    """Glob spec files matching NNN-*.md under specs_dir, sorted by spec id."""
    if not specs_dir.exists():
        return []
    # Spec 493 (Defect B): union the plain-NNN glob with the suffixed NNN[a-z]
    # glob, de-dup by path. String sort by filename keeps 004 < 004a < 004b.
    seen: dict[Path, None] = {}
    for pattern in ("[0-9][0-9][0-9]-*.md", "[0-9][0-9][0-9][a-z]-*.md"):
        for p in specs_dir.glob(pattern):
            if p.is_file():
                seen[p] = None
    files = list(seen.keys())
    files.sort(key=lambda p: p.name)
    return files

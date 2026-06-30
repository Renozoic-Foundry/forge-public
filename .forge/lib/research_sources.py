#!/usr/bin/env python3
"""Spec 458 — research-source inventory parser for the Signal-to-Strategy Loop.

Walks a directory of Markdown research clippings and extracts lightweight metadata
(file name, title, source URL, author, date) for the loop's source inventory
(Spec 458 Req 1). It does NOT copy article bodies — only metadata (Constraint 1).

Designed to degrade gracefully: if the corpus directory is absent (common — the
default corpus lives in a local Obsidian vault, not in the repo), it prints a clear
notice and exits 0 with an empty inventory, so a missing corpus never breaks a run.

Metadata sources, in priority order, per file:
  1. YAML-ish frontmatter (between leading `---` fences): `title`, `source`/`url`,
     `author`, `created`/`date`/`published`.
  2. Inline metadata lines near the top: `Source: <url>`, `Author: <name>`,
     `Created: <date>` / `Published: <date>` (case-insensitive).
  3. The first `# H1` heading as a title fallback; the file stem otherwise.

Usage:
  research_sources.py <corpus-dir> [--format=table|json] [--limit=N]
  research_sources.py --help

Exit codes:
  0  success (including absent corpus — empty inventory)
  2  usage error
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Spec 401: Python 3.10+ floor — defense-in-depth for direct invocation when the
# forge-py wrapper is bypassed.
if sys.version_info < (3, 10):
    sys.stderr.write(
        f"error: Python 3.10+ required (found {sys.version_info.major}.{sys.version_info.minor})\n"
    )
    sys.exit(1)

USAGE = (
    "usage: research_sources.py <corpus-dir> [--format=table|json] [--limit=N]\n"
    "       research_sources.py --help\n"
)

_URL_RE = re.compile(r"https?://\S+")
_INLINE_RE = re.compile(
    r"^\s*(source|url|author|created|date|published)\s*[:=]\s*(.+?)\s*$",
    re.IGNORECASE,
)
_H1_RE = re.compile(r"^#\s+(.*\S)\s*$")
# YAML-ish frontmatter `key: value` (no nested structures needed for clippings).
_FM_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.*?)\s*$")


def _strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1].strip()
    return value


def _parse_frontmatter(lines: list[str]) -> tuple[dict, int]:
    """If lines start with a `---` fence, parse the simple key:value frontmatter.

    Returns (mapping, body_start_index). body_start_index is the first line index
    after the closing fence, or 0 if there is no frontmatter.
    """
    if not lines or lines[0].strip() != "---":
        return {}, 0
    fm: dict[str, str] = {}
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return fm, i + 1
        m = _FM_RE.match(lines[i])
        if m:
            fm[m.group(1).lower()] = _strip_quotes(m.group(2))
    # Unterminated frontmatter — treat as no frontmatter.
    return {}, 0


def extract_metadata(path: Path) -> dict:
    """Extract metadata from one Markdown clipping. Reads at most the top of the file."""
    record: dict[str, str | None] = {
        "file": path.name,
        "title": None,
        "url": None,
        "author": None,
        "date": None,
    }
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:  # pragma: no cover - filesystem edge
        record["title"] = path.stem
        record["error"] = str(exc)
        return record

    lines = text.splitlines()
    fm, body_start = _parse_frontmatter(lines)

    if fm:
        record["title"] = fm.get("title") or record["title"]
        record["url"] = fm.get("source") or fm.get("url") or record["url"]
        record["author"] = fm.get("author") or record["author"]
        record["date"] = (
            fm.get("created") or fm.get("date") or fm.get("published") or record["date"]
        )

    # Scan the first ~30 body lines for inline metadata and an H1 title fallback.
    for line in lines[body_start : body_start + 30]:
        if record["title"] is None:
            h1 = _H1_RE.match(line)
            if h1:
                record["title"] = h1.group(1)
                continue
        inline = _INLINE_RE.match(line)
        if inline:
            key = inline.group(1).lower()
            val = _strip_quotes(inline.group(2))
            if key in ("source", "url") and not record["url"]:
                url = _URL_RE.search(val)
                record["url"] = url.group(0) if url else val
            elif key == "author" and not record["author"]:
                record["author"] = val
            elif key in ("created", "date", "published") and not record["date"]:
                record["date"] = val

    if record["title"] is None:
        record["title"] = path.stem
    return record


def inventory(corpus_dir: Path, limit: int | None = None) -> list[dict]:
    """Return a metadata record per `*.md` file under corpus_dir (recursive)."""
    files = sorted(corpus_dir.rglob("*.md"))
    if limit is not None:
        files = files[:limit]
    return [extract_metadata(p) for p in files]


def _render_table(records: list[dict]) -> str:
    if not records:
        return "(no markdown sources found)"
    rows = ["file\ttitle\turl\tauthor\tdate"]
    for r in records:
        rows.append(
            "\t".join(
                str(r.get(k) or "") for k in ("file", "title", "url", "author", "date")
            )
        )
    return "\n".join(rows)


def main(argv: list[str]) -> int:
    args = argv[1:]
    if not args or args[0] in ("-h", "--help"):
        sys.stdout.write(__doc__ or USAGE)
        return 0 if args else 2

    corpus = None
    fmt = "table"
    limit: int | None = None
    for a in args:
        if a.startswith("--format="):
            fmt = a.split("=", 1)[1]
        elif a.startswith("--limit="):
            try:
                limit = int(a.split("=", 1)[1])
            except ValueError:
                sys.stderr.write(f"error: --limit must be an integer (got: {a})\n")
                return 2
        elif a.startswith("--"):
            sys.stderr.write(f"error: unknown option {a}\n{USAGE}")
            return 2
        elif corpus is None:
            corpus = a
        else:
            sys.stderr.write(f"error: unexpected argument {a}\n{USAGE}")
            return 2

    if fmt not in ("table", "json"):
        sys.stderr.write(f"error: --format must be table or json (got: {fmt})\n")
        return 2
    if corpus is None:
        sys.stderr.write(USAGE)
        return 2

    corpus_dir = Path(corpus)
    if not corpus_dir.exists():
        # Graceful degradation: absent corpus is not an error for the loop.
        notice = f"notice: corpus directory not found: {corpus_dir} — empty inventory.\n"
        sys.stderr.write(notice)
        if fmt == "json":
            sys.stdout.write(json.dumps({"corpus": str(corpus_dir), "count": 0, "sources": []}, indent=2) + "\n")
        else:
            sys.stdout.write("(corpus absent; 0 sources)\n")
        return 0
    if not corpus_dir.is_dir():
        sys.stderr.write(f"error: not a directory: {corpus_dir}\n")
        return 2

    records = inventory(corpus_dir, limit=limit)
    if fmt == "json":
        out = {"corpus": str(corpus_dir), "count": len(records), "sources": records}
        sys.stdout.write(json.dumps(out, indent=2) + "\n")
    else:
        sys.stdout.write(_render_table(records) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

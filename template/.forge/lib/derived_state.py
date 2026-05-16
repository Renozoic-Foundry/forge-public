#!/usr/bin/env python3
"""FORGE shared state helper (Spec 399).

Single Python module concentrating ALL schema knowledge for derived state
(backlog, spec index, changelog). Slash commands invoke this module via
`.forge/bin/forge-py .forge/lib/derived_state.py --<flag>` instead of
opening canonical files directly. The helper IS the schema contract;
callers depend on the Python API and CLI signature, not on artifact
on-disk format.

Public Python API:
    detect_mode(project_root) -> Literal["split-file", "generated", "skip-canonical"]
    get_backlog_rows(project_root) -> list[dict]
    get_spec_index(project_root) -> list[dict]
    get_changelog_entries(project_root) -> list[dict]
    should_skip_canonical_write(project_root) -> bool

CLI dispatch (single-shot per invocation):
    forge-py derived_state.py --detect-mode
    forge-py derived_state.py --get-backlog [--format=table|json|count]
    forge-py derived_state.py --get-spec-index [--format=table|json|count]
    forge-py derived_state.py --get-changelog [--format=table|json|count]
    forge-py derived_state.py --skip-canonical-write
        stdout: `skip\\n` (split-file mode) or `proceed\\n` (otherwise).
        Exit code 0 = helper succeeded; nonzero = helper error (caller MUST abort).

Constraints (Spec 399 + Spec 401):
- stdlib only (no PyYAML or third-party imports).
- Binary-mode I/O for any file read (Spec 398 lesson — CRLF/BOM safety).
- Read-source: spec frontmatter (`docs/specs/NNN-*.md`) + per-spec event streams
  (`.forge/state/events/<spec-id>/*.jsonl`). The helper does NOT parse the
  rendered `.generated/<artifact>.md` files; rendered artifacts are an
  output of the same source. This keeps the helper independent of any
  rendering bug and satisfies AC 2 ("same logical content under all 3 modes").
- Mode is purely a write-side classifier (and a diagnostic for `--detect-mode`).
- Degenerate state (`.generated/` exists but no curated parent has a
  `<!-- FORGE-INCLUDE: ... -->` marker) raises a clear error rather than
  silently falling back to canonical reads.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Optional

if sys.version_info < (3, 10):
    sys.stderr.write(
        f"error: Python 3.10+ required (found {sys.version_info.major}.{sys.version_info.minor})\n"
    )
    sys.exit(1)

try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    sys.stderr.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except (AttributeError, OSError):
    pass

_LIB_DIR = Path(__file__).resolve().parent
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))


# Curated parents that should hold include markers in split-file mode.
CURATED_PARENTS = (
    "docs/backlog.md",
    "docs/specs/README.md",
    "docs/specs/CHANGELOG.md",
)

INCLUDE_MARKER_RE = re.compile(rb"<!--\s*FORGE-INCLUDE:\s*([^\s>]+)\s*-->")
# `#  DO NOT EDIT — generated` — em-dash (U+2014, UTF-8 \xe2\x80\x94), en-dash (U+2013, \xe2\x80\x93), or ASCII hyphen.
GENERATED_TAG_RE = re.compile(
    rb"#\s*DO NOT EDIT\s*(?:\xe2\x80\x94|\xe2\x80\x93|-)\s*generated",
    re.IGNORECASE,
)


class DerivedStateError(RuntimeError):
    """Raised on degenerate state or unrecoverable parse error."""


def _resolve_root(project_root: Optional[Path]) -> Path:
    return Path(project_root) if project_root is not None else Path.cwd()


def _read_bytes(p: Path) -> bytes:
    """Binary-mode read; tolerates absent file by raising FileNotFoundError."""
    return p.read_bytes()


# ---------- Mode detection ----------

def detect_mode(project_root: Optional[Path] = None) -> str:
    """Classify the project's rendering mode.

    Returns one of:
        - "split-file"     — docs/.generated/ exists AND at least one curated
                             parent contains a <!-- FORGE-INCLUDE: ... -->
                             marker pointing at an existing .generated/ artifact.
        - "generated"      — docs/.generated/ does not exist AND any canonical
                             file's first 5 lines contain
                             "# DO NOT EDIT — generated".
        - "skip-canonical" — neither of the above (legacy / greenfield default).

    Raises DerivedStateError on the degenerate partial-migration state where
    docs/.generated/ exists but no curated parent has an include marker.
    """
    root = _resolve_root(project_root)
    generated_dir = root / "docs" / ".generated"

    has_include_marker = False
    for rel in CURATED_PARENTS:
        p = root / rel
        if not p.is_file():
            continue
        try:
            data = _read_bytes(p)
        except OSError:
            continue
        m = INCLUDE_MARKER_RE.search(data)
        if not m:
            continue
        target_rel = m.group(1).decode("utf-8", errors="replace")
        target = (p.parent / target_rel).resolve()
        if target.is_file():
            has_include_marker = True
            break

    if generated_dir.is_dir() and has_include_marker:
        return "split-file"

    if generated_dir.is_dir() and not has_include_marker:
        raise DerivedStateError(
            "degenerate split-file state: docs/.generated/ exists but no "
            "curated parent ({}) contains a "
            "<!-- FORGE-INCLUDE: ... --> marker pointing at an existing "
            ".generated/ artifact. Either complete the migration "
            "(`python scripts/migrate-to-derived-view.py --mode=split-file`) "
            "or remove docs/.generated/ to revert to legacy mode."
            .format(", ".join(CURATED_PARENTS))
        )

    # generated_dir absent — check for legacy "generated" mode
    for rel in CURATED_PARENTS:
        p = root / rel
        if not p.is_file():
            continue
        try:
            with p.open("rb") as fh:
                head = b"".join(fh.readline() for _ in range(5))
        except OSError:
            continue
        if GENERATED_TAG_RE.search(head):
            return "generated"

    return "skip-canonical"


# ---------- Read-side getters ----------

def _import_renderers():
    """Lazy-import the renderer modules; they share .forge/lib/."""
    from spec_frontmatter import iter_spec_files, parse_spec_file  # type: ignore
    from events import load_events  # type: ignore
    return iter_spec_files, parse_spec_file, load_events


def _backlog_row_dict(fm: dict, *, rank: Optional[str] = None) -> dict:
    return {
        "rank": rank,
        "spec_id": fm.get("spec_id") or "",
        "title": fm.get("title") or "",
        "bv": fm.get("bv"),
        "e": fm.get("e"),
        "r": fm.get("r"),
        "sr": fm.get("sr"),
        "score": fm.get("score"),
        "depends": fm.get("dependencies") or "",
        "status": (fm.get("status") or "").strip().lower(),
    }


def get_backlog_rows(project_root: Optional[Path] = None) -> list[dict]:
    """Return the ranked backlog as a list of dicts.

    Source: per-spec frontmatter (docs/specs/NNN-*.md) — same data the
    renderer consumes. Mode-independent (read source is the same in all
    three modes; mode classification is for the write side).

    Output order:
      1. status=in-progress, sorted by spec_id
      2. status=implemented, sorted by spec_id
      3. status=draft, sorted by score desc then spec_id (numeric rank assigned)
      4. status=deferred, sorted by spec_id
      5. status=closed, sorted by spec_id
      6. status=deprecated, sorted by spec_id

    Each row is a dict with keys:
      rank, spec_id, title, bv, e, r, sr, score, depends, status
    """
    root = _resolve_root(project_root)
    iter_spec_files, parse_spec_file, _ = _import_renderers()
    files = iter_spec_files(root / "docs" / "specs")

    rows: list[dict] = [parse_spec_file(f) for f in files]
    rows = [r for r in rows if r is not None]

    by_status: dict[str, list[dict]] = {}
    for r in rows:
        st = (r.get("status") or "").strip().lower()
        by_status.setdefault(st, []).append(r)

    out: list[dict] = []

    rank_marker = {
        "in-progress": "→",
        "implemented": "→",
        "deferred": "⏸",
        "closed": "✅",
        "deprecated": "⊘",
    }

    for s in ("in-progress", "implemented"):
        for r in sorted(by_status.get(s, []), key=lambda x: x.get("spec_id", "")):
            out.append(_backlog_row_dict(r, rank=rank_marker[s]))

    drafts = sorted(
        by_status.get("draft", []),
        key=lambda r: (-(r.get("score") or 0), r.get("spec_id", "")),
    )
    for idx, r in enumerate(drafts, 1):
        out.append(_backlog_row_dict(r, rank=str(idx)))

    for s in ("deferred", "closed", "deprecated"):
        for r in sorted(by_status.get(s, []), key=lambda x: x.get("spec_id", "")):
            out.append(_backlog_row_dict(r, rank=rank_marker[s]))

    return out


def get_spec_index(project_root: Optional[Path] = None) -> list[dict]:
    """Return the spec index as a list of dicts, sorted by spec_id.

    Source: per-spec frontmatter. Each row has keys: spec_id, slug, status, title.
    """
    root = _resolve_root(project_root)
    iter_spec_files, parse_spec_file, _ = _import_renderers()
    files = iter_spec_files(root / "docs" / "specs")

    out: list[dict] = []
    for f in files:
        fm = parse_spec_file(f)
        if fm is None:
            continue
        sid = fm.get("spec_id") or ""
        if not sid:
            continue
        out.append({
            "spec_id": sid,
            "slug": Path(f).stem,
            "status": (fm.get("status") or "?").strip(),
            "title": fm.get("title") or "",
        })
    out.sort(key=lambda r: r["spec_id"])
    return out


_CHANGELOG_EVENT_TYPES = {
    "spec-started",
    "spec-approved",
    "spec-implemented",
    "spec-closed",
    "spec-deferred",
    "spec-deprecated",
    "revise",
}


def get_changelog_entries(project_root: Optional[Path] = None) -> list[dict]:
    """Return chronologically-newest-first changelog entries.

    Source: per-spec event streams (.forge/state/events/<spec-id>/*.jsonl).
    Each entry: {timestamp, spec_id, event_type, title, message}.
    """
    root = _resolve_root(project_root)
    iter_spec_files, parse_spec_file, load_events = _import_renderers()

    # spec_id → title for joins
    title_by_id: dict[str, str] = {}
    for f in iter_spec_files(root / "docs" / "specs"):
        fm = parse_spec_file(f)
        if fm is None:
            continue
        sid = str(fm.get("spec_id", ""))
        if sid:
            title_by_id[sid] = fm.get("title", "")

    events = load_events(base_dir=root / ".forge" / "state" / "events")

    out: list[dict] = []
    for ev in events:
        et = ev.get("event_type", "")
        if et not in _CHANGELOG_EVENT_TYPES:
            continue
        sid = ev.get("_spec_id", "?")
        ts = ev.get("timestamp", "")
        msg = (ev.get("payload", {}) or {}).get("message", "")
        out.append({
            "timestamp": ts,
            "spec_id": sid,
            "event_type": et,
            "title": title_by_id.get(sid, ""),
            "message": msg,
        })
    out.sort(key=lambda r: r["timestamp"], reverse=True)
    return out


# ---------- Write-side gate ----------

def should_skip_canonical_write(project_root: Optional[Path] = None) -> bool:
    """Return True iff the project is in split-file mode.

    Callers (/spec, /implement, /close, /matrix) consult this before any
    canonical-table-row write. In split-file mode, the renderer-owned
    .generated/ artifact is the source of truth; canonical files contain
    only an include marker, and writing a row to them would shadow the
    marker (the duplicate-row class Spec 398 was designed to prevent).

    NOTE: This function returns False under "skip-canonical" and "generated"
    modes — the names refer to the rendering MODE, not the write decision.
    Phase 2 #3 (universal dual-write retirement) becomes a 1-line edit
    here when burn-in completes.
    """
    return detect_mode(project_root) == "split-file"


# ---------- CLI dispatch ----------

def _format_rows_table(rows: list[dict], columns: list[str]) -> str:
    """Plain-text fallback table; one row per line, tab-separated columns.

    Used only for --get-spec-index and --get-changelog. The --get-backlog
    path delegates to render_backlog.render() so the helper's table output
    is byte-identical to the table portion of docs/.generated/backlog-table.md
    (Spec 439 Req 4 — delegation, no parallel formatter).
    """
    lines = ["\t".join(columns)]
    for r in rows:
        lines.append("\t".join(str(r.get(c, "") if r.get(c) is not None else "") for c in columns))
    return "\n".join(lines) + "\n"


def _backlog_table_via_renderer(project_root: Optional[Path] = None) -> str:
    """Spec 439 Req 4 — delegate --format=table to render_backlog.render().

    Returns the markdown table portion (column headers + separator + data rows)
    that appears under "## Ranked backlog" in docs/.generated/backlog-table.md.
    The file-level wrapping (page title, generated-by comment, rendered timestamp,
    scoring-formula prose) is omitted — those are render_backlog header=True
    concerns that include a non-deterministic timestamp. The table content
    delegated here is byte-identical to the corresponding section of the
    rendered artifact.
    """
    from render_backlog import render  # delegate — no parallel formatter
    full = render(_resolve_root(project_root) / "docs" / "specs", header=True)
    lines = full.splitlines()
    try:
        start = next(i for i, ln in enumerate(lines) if ln.startswith("| Rank "))
    except StopIteration:
        return "\n"
    return "\n".join(lines[start:]) + "\n"


def _emit(rows: list[dict], fmt: str, columns: list[str], *, backlog: bool = False) -> str:
    if fmt == "json":
        return json.dumps(rows, ensure_ascii=False) + "\n"
    if fmt == "count":
        return f"{len(rows)}\n"
    if fmt == "table":
        if backlog:
            return _backlog_table_via_renderer()
        return _format_rows_table(rows, columns)
    raise ValueError(f"unknown format: {fmt}")


def main(argv: Optional[list[str]] = None) -> int:
    p = argparse.ArgumentParser(
        prog="derived_state.py",
        description="FORGE shared derived-state helper (Spec 399).",
    )
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--detect-mode", action="store_true",
                   help="Print the mode classifier output.")
    g.add_argument("--get-backlog", action="store_true",
                   help="Emit the ranked backlog rows.")
    g.add_argument("--get-spec-index", action="store_true",
                   help="Emit the spec index rows.")
    g.add_argument("--get-changelog", action="store_true",
                   help="Emit the changelog entries (newest first).")
    g.add_argument("--skip-canonical-write", action="store_true",
                   help="Print 'skip' or 'proceed' for the canonical-write decision.")
    p.add_argument("--format", default="table", choices=("table", "json", "count"),
                   help="Output format for --get-* (default: table).")
    args = p.parse_args(argv)

    try:
        if args.detect_mode:
            sys.stdout.write(detect_mode() + "\n")
            return 0

        if args.skip_canonical_write:
            sys.stdout.write("skip\n" if should_skip_canonical_write() else "proceed\n")
            return 0

        if args.get_backlog:
            cols = ["rank", "spec_id", "title", "bv", "e", "r", "sr", "score", "status"]
            sys.stdout.write(_emit(get_backlog_rows(), args.format, cols, backlog=True))
            return 0

        if args.get_spec_index:
            cols = ["spec_id", "slug", "status", "title"]
            sys.stdout.write(_emit(get_spec_index(), args.format, cols))
            return 0

        if args.get_changelog:
            cols = ["timestamp", "spec_id", "event_type", "title", "message"]
            sys.stdout.write(_emit(get_changelog_entries(), args.format, cols))
            return 0

    except DerivedStateError as exc:
        sys.stderr.write(f"derived_state: {exc}\n")
        return 2
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"derived_state: {type(exc).__name__}: {exc}\n")
        return 1

    return 1


if __name__ == "__main__":
    sys.exit(main())

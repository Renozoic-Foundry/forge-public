#!/usr/bin/env python3
"""FORGE render-changelog (Spec 254 — Approach D).

Renders the spec changelog view chronologically (newest-first) from per-spec
event streams (`.forge/state/events/<spec-id>/*.jsonl`).

Falls back to spec frontmatter `Closed:`/`Status:` fields when no event streams
exist (greenfield projects, pre-migration state).

Usage:
    python3 .forge/lib/render_changelog.py [--specs-dir docs/specs] \
                                            [--events-dir .forge/state/events] \
                                            [--output -]

Determinism: byte-identical output across two consecutive invocations against
the same input state (Spec 254 AC 14 substitute).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Spec 401: Python 3.10+ floor — defense-in-depth for direct invocation when forge-py wrapper is bypassed.
if sys.version_info < (3, 10):
    sys.stderr.write(f"error: Python 3.10+ required (found {sys.version_info.major}.{sys.version_info.minor})\n")
    sys.exit(1)

_LIB_DIR = Path(__file__).resolve().parent
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

# Force UTF-8 on stdout/stderr — Windows cp1252 default chokes on `→` `−` etc.
try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    sys.stderr.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except (AttributeError, OSError):
    pass

from events import load_events  # noqa: E402
from spec_frontmatter import iter_spec_files, parse_spec_file  # noqa: E402
from render_invariant import assert_complete  # noqa: E402

import re as _re

_BODY_DATE_RE = _re.compile(r"^-\s+(\d{4}-\d{2}-\d{2})[:\s]", _re.MULTILINE)


def _body_last_date(path: Path) -> str:
    """Final date fallback (Spec 534): latest dated Revision-Log bullet — legacy
    closed specs may carry neither Closed: nor Last updated: frontmatter."""
    try:
        dates = _BODY_DATE_RE.findall(path.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return ""
    return max(dates) if dates else ""


# Event types to surface in the changelog (chronological-history-relevant)
CHANGELOG_EVENT_TYPES = {
    "spec-started",
    "spec-approved",
    "spec-implemented",
    "spec-closed",
    "spec-deferred",
    "spec-deprecated",
    "revise",
}


def render(specs_dir: Path, events_dir: Path, *, header: bool = True) -> str:
    # Build spec_id → title map for joins
    title_by_id: dict[str, str] = {}
    for f in iter_spec_files(specs_dir):
        fm = parse_spec_file(f)
        if fm is None:
            continue
        sid = str(fm.get("spec_id", ""))
        if sid:
            title_by_id[sid] = fm.get("title", "")

    # Load all events
    all_events = load_events(base_dir=events_dir)

    # Build entries: (timestamp, spec_id, event_type, line)
    entries: list[tuple[str, str, str, str]] = []
    recognized = 0  # Spec 494: count of changelog-relevant events that must each render
    for ev in all_events:
        et = ev.get("event_type", "")
        if et not in CHANGELOG_EVENT_TYPES:
            continue
        recognized += 1
        spec_id = ev.get("_spec_id", "?")
        ts = ev.get("timestamp", "")
        title = title_by_id.get(spec_id, "")
        msg = ev.get("payload", {}).get("message", "")
        date = ts.split("T", 1)[0] if "T" in ts else ts

        verb = {
            "spec-started": "started",
            "spec-approved": "approved",
            "spec-implemented": "implemented",
            "spec-closed": "closed",
            "spec-deferred": "deferred",
            "spec-deprecated": "deprecated",
            "revise": "revised",
        }.get(et, et)

        line = f"- {date}: Spec {spec_id} {verb}"
        if title:
            line += f" — {title}"
        if msg:
            line += f" ({msg})"
        line += "."
        entries.append((ts, spec_id, et, line))

    # --- Spec 534: closed-spec completeness (frontmatter fallback + invariant) ---
    # "Closed" set = `Status: closed` frontmatter ONLY (deprecated is a separate
    # terminal state with its own event type — DA-pinned 2026-07-07).
    #
    # Layering (DA option (a) — the fallback must not mute the gap signal):
    #   1. RAW-STORE GAP (loud warning, exit 0): a closed spec with no spec-closed
    #      event is synthesized from frontmatter at render time, and stderr names
    #      every such ID so the store gap stays visible. Run
    #      .forge/lib/backfill_close_events.py to make the store durable.
    #   2. HARD INVARIANT (exit non-zero): a closed spec that CANNOT be rendered
    #      at all (no event AND no derivable frontmatter date) fails the render,
    #      naming the ID — output completeness is never silently sacrificed.
    closed_event_ids = {sid for _, sid, et, _ in entries if et == "spec-closed"}
    fallback_ids: list[str] = []
    unrenderable: list[str] = []
    for f in iter_spec_files(specs_dir):
        fm = parse_spec_file(f)
        if fm is None or fm.get("status", "").strip().lower() != "closed":
            continue
        sid = str(fm.get("spec_id", "")).strip()
        if not sid or sid in closed_event_ids:
            continue
        date = fm.get("closed", "").strip() or fm.get("last_updated", "").strip()
        if not date:
            date = _body_last_date(f)
        date = date.split()[0] if date else ""
        if not date or len(date) < 10:
            unrenderable.append(sid)
            continue
        title = title_by_id.get(sid, fm.get("title", ""))
        line = f"- {date[:10]}: Spec {sid} closed"
        if title:
            line += f" — {title}"
        line += "."
        entries.append((f"{date[:10]}T00:00:00Z", sid, "spec-closed", line))
        fallback_ids.append(sid)

    if unrenderable:
        sys.stderr.write(
            "render_changelog: INVARIANT FAIL — closed spec(s) missing from the "
            "changelog with no derivable close date (no spec-closed event, no "
            f"Closed:/Last updated: frontmatter): {' '.join(sorted(unrenderable))}\n"
        )
        raise SystemExit(3)
    if fallback_ids:
        sys.stderr.write(
            f"render_changelog: warning — events-store gap: {len(fallback_ids)} closed "
            "spec(s) had no spec-closed event and were rendered via frontmatter fallback: "
            f"{' '.join(sorted(fallback_ids))}. Run .forge/lib/backfill_close_events.py "
            "to make the store durable (SIG-519-R3).\n"
        )

    # Sort chronologically newest-first; tiebreak by spec_id then event_type
    entries.sort(key=lambda x: (x[0], x[1], x[2]), reverse=True)

    # Spec 494: every recognized changelog event must produce exactly one line.
    # Guards against a future filter silently dropping a recognized event (the
    # SIG-493-02 / EA-309-P1 silent-drop class). Intentional event-type filtering
    # above is NOT a drop — only recognized-but-unrendered events fail this.
    # (Spec 534 fallback entries are counted too — they are recognized closes.)
    assert_complete("render_changelog", recognized + len(fallback_ids), len(entries))

    lines: list[str] = []
    if header:
        lines.append("# Specs Changelog")
        lines.append("")
        lines.append("<!--")
        lines.append(
            "  DO NOT EDIT — generated by render_changelog.py (Spec 254 — Approach D)."
        )
        lines.append(
            "  Source: per-spec event streams under .forge/state/events/<spec-id>/"
        )
        lines.append("-->")
        lines.append("")
        lines.append("## Entries")
        lines.append("")

    if not entries:
        lines.append("_No events recorded yet. Lifecycle commands (/implement, /close, /revise) populate event streams._")
    else:
        for _, _, _, line in entries:
            lines.append(line)

    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Render FORGE changelog from event streams")
    p.add_argument("--specs-dir", default="docs/specs")
    p.add_argument("--events-dir", default=".forge/state/events")
    p.add_argument("--output", default="-")
    p.add_argument("--no-header", action="store_true")
    p.add_argument(
        "--mode",
        choices=("stdout", "split-file"),
        default="stdout",
        help="Spec 398: split-file writes to docs/.generated/changelog-entries.md "
             "via binary-mode atomic-replace.",
    )
    p.add_argument(
        "--split-file-target",
        default="docs/.generated/changelog-entries.md",
    )
    args = p.parse_args(argv)

    out = render(
        Path(args.specs_dir),
        Path(args.events_dir),
        header=not args.no_header,
    )

    if args.mode == "split-file":
        from split_file_writer import write_split_file_artifact
        write_split_file_artifact(Path(args.split_file_target), out)
        return 0

    if args.output == "-":
        sys.stdout.write(out)
    else:
        Path(args.output).write_text(out, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

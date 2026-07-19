#!/usr/bin/env python3
"""FORGE events-store close-event backfill (Spec 534 — retire SIG-519-R3).

Synthesizes a `spec-closed` event for every frontmatter-closed spec that has no
spec-closed event in the per-clone events store (`.forge/state/events/<id>/`).
The events store is gitignored, so ~70 pre-events-store closes never got events;
without them a changelog re-render silently drops history.

Rules (DA-reviewed 2026-07-07):
  - "Closed" set = `- Status: closed` frontmatter ONLY (deprecated is a distinct
    terminal state with its own spec-deprecated event type — never conflated).
  - Timestamp source: `- Closed: YYYY-MM-DD` (authoritative). Legacy specs with
    no Closed field fall back to `- Last updated:` and the payload is marked
    `"date_approximate": true` (payload-only — the rendered line stays uniform).
  - A closed spec with NEITHER date is reported and skipped (the renderer's
    hard invariant will name it — see render_changelog.py).
  - Idempotent: specs that already have a spec-closed event are skipped; a
    second run reports 0 new events.
  - Writes ONLY the gitignored events store (Spec 534 constraint — never spec
    files or CHANGELOG.md).

Usage:
    forge-py .forge/lib/backfill_close_events.py [--specs-dir docs/specs]
                                                  [--events-dir .forge/state/events]
                                                  [--dry-run]
    # forge:path-literal-ok (comment) — usage example; real default resolved via runtime_config
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

if sys.version_info < (3, 10):
    sys.stderr.write(f"error: Python 3.10+ required (found {sys.version_info.major}.{sys.version_info.minor})\n")
    sys.exit(1)

_LIB_DIR = Path(__file__).resolve().parent
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    sys.stderr.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except (AttributeError, OSError):
    pass

from spec_frontmatter import iter_spec_files, parse_spec_file  # noqa: E402

try:
    from runtime_config import resolve_path as _rc_resolve_path  # Spec 564 helper
except ImportError:
    _rc_resolve_path = None

import re

_BODY_DATE_RE = re.compile(r"^-\s+(\d{4}-\d{2}-\d{2})[:\s]", re.MULTILINE)


def body_last_date(path: Path) -> str:
    """Final date fallback (Spec 534): the LATEST dated bullet in the spec body
    (Revision Log convention `- YYYY-MM-DD: ...`) — 25 legacy closed specs carry
    neither `Closed:` nor `Last updated:` frontmatter. Always approximate."""
    try:
        dates = _BODY_DATE_RE.findall(path.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return ""
    return max(dates) if dates else ""



def has_close_event(events_dir: Path, spec_id: str) -> bool:
    f = events_dir / spec_id / "spec-closed.jsonl"
    if not f.is_file():
        return False
    try:
        for line in f.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            if json.loads(line).get("event_type") == "spec-closed":
                return True
    except (OSError, json.JSONDecodeError):
        return False
    return False


def _default_specs_dir() -> str:
    """Resolve forge.paths.specs via runtime_config; fall back to the classic default."""
    if _rc_resolve_path is not None:
        try:
            value, error = _rc_resolve_path(Path("."), "specs")
            if not error and value:
                return value
        except Exception:
            pass
    return "docs/specs"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Backfill spec-closed events from frontmatter (Spec 534)")
    p.add_argument("--specs-dir", default=_default_specs_dir())
    p.add_argument("--events-dir", default=".forge/state/events")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args(argv)

    specs_dir = Path(args.specs_dir)
    events_dir = Path(args.events_dir)

    new = 0
    skipped = 0
    dateless: list[str] = []

    for f in iter_spec_files(specs_dir):
        fm = parse_spec_file(f)
        if fm is None:
            continue
        if fm.get("status", "").strip().lower() != "closed":
            continue
        sid = str(fm.get("spec_id", "")).strip()
        if not sid:
            continue
        if has_close_event(events_dir, sid):
            skipped += 1
            continue

        date = fm.get("closed", "").strip()
        approximate = False
        if not date:
            date = fm.get("last_updated", "").strip()
            approximate = True
        if not date:
            date = body_last_date(f)
            approximate = True
        # keep only a leading YYYY-MM-DD token
        date = date.split()[0] if date else ""
        if not date or len(date) < 10:
            dateless.append(sid)
            continue

        payload: dict = {
            "backfilled": True,
            "source": "frontmatter",
            "message": fm.get("title", ""),
        }
        if approximate:
            payload["date_approximate"] = True

        event = {
            "timestamp": f"{date[:10]}T00:00:00Z",
            "event_type": "spec-closed",
            "payload": payload,
        }
        if not args.dry_run:
            d = events_dir / sid
            d.mkdir(parents=True, exist_ok=True)
            with (d / "spec-closed.jsonl").open("a", encoding="utf-8", newline="\n") as fh:
                fh.write(json.dumps(event, ensure_ascii=False) + "\n")
        new += 1

    mode = "DRY-RUN: would backfill" if args.dry_run else "backfilled"
    print(f"backfill-close-events: {mode} {new} spec-closed event(s); {skipped} already present.")
    if dateless:
        print(
            "backfill-close-events: WARNING — closed spec(s) with no derivable date "
            f"(no Closed:, no Last updated:) skipped: {' '.join(sorted(dateless))}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

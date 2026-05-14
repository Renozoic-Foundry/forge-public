#!/usr/bin/env python3
"""FORGE migrate-to-derived-view (Spec 254 — Approach D).

Migrates a FORGE project from monolithic-tracking-files architecture to
Approach D's per-spec event-stream + renderer model.

Two phases:
  1. Seed events from existing artifacts (CHANGELOG, activity-log, spec frontmatter)
  2. Optionally transform canonical files (mode=generated keeps as artifacts;
     mode=delete removes them; mode=skip-canonical leaves them as-is)

Idempotent: re-running produces no diff against current state.

Usage:
    python3 scripts/migrate-to-derived-view.py [--mode=generated|delete|skip-canonical]
                                                [--specs-dir docs/specs]
                                                [--events-dir .forge/state/events]
                                                [--backlog docs/backlog.md]
                                                [--changelog docs/specs/CHANGELOG.md]
                                                [--activity-log docs/sessions/activity-log.jsonl]
                                                [--dry-run]
                                                [--no-backup]

Default mode: generated. Default --backup behavior: backup canonical files to
.forge/state/migration-backup-<ISO timestamp>/ before any destructive op.

Exit codes:
  0 = success
  1 = argument error
  2 = migration aborted (diff failed, etc.)
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

# Spec 401: Python 3.10+ floor — defense-in-depth for direct invocation when forge-py wrapper is bypassed.
if sys.version_info < (3, 10):
    sys.stderr.write(f"error: Python 3.10+ required (found {sys.version_info.major}.{sys.version_info.minor})\n")
    sys.exit(1)

_SCRIPT_DIR = Path(__file__).resolve().parent
_LIB_DIR = _SCRIPT_DIR.parent / ".forge" / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

# Force UTF-8.
try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    sys.stderr.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except (AttributeError, OSError):
    pass

from events import append_event, load_events  # noqa: E402
from spec_frontmatter import iter_spec_files, parse_spec_file  # noqa: E402

# CHANGELOG line patterns we recognize. Order matters — most-specific first.
_CHANGELOG_LINE_RE = re.compile(
    r"^\s*-\s*(?P<date>\d{4}-\d{2}-\d{2}):\s*Spec\s+(?P<spec_id>\d+)\s+(?P<verb>.+?)\.?\s*$"
)

# Verb → event_type mapping
VERB_TO_EVENT = {
    "approved": "spec-approved",
    "approved inline": "spec-approved",
    "implemented": "spec-implemented",
    "closed": "spec-closed",
    "deferred": "spec-deferred",
    "deprecated": "spec-deprecated",
    "revised": "revise",
}


def _verb_norm(verb: str) -> str:
    """Normalize a CHANGELOG verb to an event_type token. Returns empty if unknown."""
    v = verb.strip().lower()
    # Try longest match first
    for key in sorted(VERB_TO_EVENT, key=len, reverse=True):
        if v.startswith(key):
            return VERB_TO_EVENT[key]
    return ""


def parse_changelog(path: Path) -> list[tuple[str, str, str, str]]:
    """Parse CHANGELOG.md → list of (date, spec_id, event_type, message)."""
    if not path.exists():
        return []
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        m = _CHANGELOG_LINE_RE.match(line)
        if not m:
            continue
        date = m.group("date")
        spec_id = m.group("spec_id")
        verb = m.group("verb")
        event_type = _verb_norm(verb)
        if not event_type:
            continue
        out.append((date, spec_id, event_type, verb.strip()))
    return out


def parse_activity_log(path: Path) -> list[dict]:
    """Parse activity-log.jsonl → list of records (full dicts)."""
    if not path.exists():
        return []
    out = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            rec = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if isinstance(rec, dict) and "spec_id" in rec and "event_type" in rec:
            out.append(rec)
    return out


def _existing_event_signatures(spec_id: str, events_dir: Path) -> set[tuple[str, str]]:
    """Return a set of (timestamp, event_type) tuples already in this spec's streams."""
    sigs: set[tuple[str, str]] = set()
    for ev in load_events(spec_id, base_dir=events_dir):
        sigs.add((ev.get("timestamp", ""), ev.get("event_type", "")))
    return sigs


def seed_events(
    *,
    specs_dir: Path,
    events_dir: Path,
    changelog_path: Path,
    activity_log_path: Path,
    dry_run: bool = False,
) -> dict:
    """Seed per-spec event streams from CHANGELOG + activity-log + frontmatter.

    Returns a dict with counts: {seeded, skipped_dup, sources_used}.
    """
    seeded = 0
    skipped_dup = 0

    # 1) From spec frontmatter — Closed: <date> for closed specs
    spec_close_dates: dict[str, str] = {}
    for f in iter_spec_files(specs_dir):
        fm = parse_spec_file(f)
        if fm is None:
            continue
        sid = fm.get("spec_id")
        status = (fm.get("status") or "").strip().lower()
        closed = fm.get("closed", "").strip()
        if sid and status == "closed" and closed:
            spec_close_dates[sid] = closed

    # 2) From CHANGELOG — chronological events
    cl_events = parse_changelog(changelog_path)

    # 3) From activity-log — already-structured events
    al_records = parse_activity_log(activity_log_path)

    # Build a working list of (timestamp, spec_id, event_type, payload) tuples.
    # Date-only timestamps from CHANGELOG get T00:00:00Z appended (best-effort).
    pending: list[tuple[str, str, str, dict]] = []

    # CHANGELOG entries — date-only, append T12:00:00Z midpoint
    for date, sid, et, raw_verb in cl_events:
        ts = f"{date}T12:00:00Z"
        pending.append((ts, sid, et, {"source": "changelog-migration", "verb": raw_verb}))

    # Spec frontmatter close dates — only for specs with no spec-closed in CL
    cl_closed_specs = {sid for _, sid, et, _ in cl_events if et == "spec-closed"}
    for sid, date in spec_close_dates.items():
        if sid not in cl_closed_specs:
            ts = f"{date}T12:00:00Z"
            pending.append(
                (ts, sid, "spec-closed", {"source": "frontmatter-migration"})
            )

    # Activity-log entries — preserve full timestamp
    for rec in al_records:
        sid = str(rec.get("spec_id", ""))
        ts = rec.get("timestamp", "")
        et = rec.get("event_type", "")
        payload = {
            "source": "activity-log-migration",
            "agent_id": rec.get("agent_id"),
            "message": rec.get("message"),
            "metadata": rec.get("metadata", {}),
        }
        if sid and ts and et:
            pending.append((ts, sid, et, payload))

    # Dedup against existing events (idempotency)
    existing_per_spec: dict[str, set[tuple[str, str]]] = {}

    for ts, sid, et, payload in pending:
        sigs = existing_per_spec.setdefault(sid, _existing_event_signatures(sid, events_dir))
        if (ts, et) in sigs:
            skipped_dup += 1
            continue
        sigs.add((ts, et))
        if dry_run:
            seeded += 1
            continue
        append_event(sid, et, payload, base_dir=events_dir, timestamp=ts)
        seeded += 1

    return {
        "seeded": seeded,
        "skipped_dup": skipped_dup,
        "changelog_lines": len(cl_events),
        "activity_log_lines": len(al_records),
        "frontmatter_closed_specs": len(spec_close_dates),
    }


def backup_canonicals(*, root: Path, paths: list[Path]) -> Path:
    """Copy canonical files to .forge/state/migration-backup-<ISO>/. Returns backup dir."""
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup_dir = root / ".forge" / "state" / f"migration-backup-{ts}"
    backup_dir.mkdir(parents=True, exist_ok=True)
    for p in paths:
        if p.exists():
            target = backup_dir / p.relative_to(root)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, target)
    return backup_dir


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Migrate FORGE project to Approach D derived-view architecture",
    )
    p.add_argument(
        "--mode",
        choices=("generated", "delete", "skip-canonical", "split-file"),
        default="generated",
        help="What to do with canonical files post-migration (default: generated). "
             "skip-canonical leaves them untouched. split-file (Spec 398) creates "
             "docs/.generated/ with renderer-owned artifacts and prints include-marker "
             "insertion guidance for the curated parents (operator pastes manually).",
    )
    p.add_argument("--specs-dir", default="docs/specs")
    p.add_argument("--events-dir", default=".forge/state/events")
    p.add_argument("--backlog", default="docs/backlog.md")
    p.add_argument("--changelog", default="docs/specs/CHANGELOG.md")
    p.add_argument("--activity-log", default="docs/sessions/activity-log.jsonl")
    p.add_argument("--root", default=".", help="Project root (default: cwd)")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument(
        "--no-backup",
        action="store_true",
        help="Skip backup before destructive ops (mode=delete or mode=generated rewrite). DANGEROUS.",
    )
    args = p.parse_args(argv)

    root = Path(args.root).resolve()
    specs_dir = (root / args.specs_dir).resolve()
    events_dir = (root / args.events_dir).resolve()
    backlog_path = (root / args.backlog).resolve()
    changelog_path = (root / args.changelog).resolve()
    activity_log_path = (root / args.activity_log).resolve()

    if not specs_dir.exists():
        print(f"ERROR: specs-dir not found: {specs_dir}", file=sys.stderr)
        return 1

    print(f"FORGE migrate-to-derived-view (Spec 254 — Approach D)")
    print(f"  root:          {root}")
    print(f"  specs-dir:     {specs_dir}")
    print(f"  events-dir:    {events_dir}")
    print(f"  mode:          {args.mode}")
    print(f"  dry-run:       {args.dry_run}")
    print()

    # Seed events first (always safe — purely additive, idempotent)
    print("Phase 1: Seeding event streams from existing artifacts…")
    stats = seed_events(
        specs_dir=specs_dir,
        events_dir=events_dir,
        changelog_path=changelog_path,
        activity_log_path=activity_log_path,
        dry_run=args.dry_run,
    )
    print(f"  CHANGELOG lines parsed:        {stats['changelog_lines']}")
    print(f"  activity-log records parsed:   {stats['activity_log_lines']}")
    print(f"  frontmatter close dates:       {stats['frontmatter_closed_specs']}")
    print(f"  events seeded:                 {stats['seeded']}")
    print(f"  events skipped (already exist): {stats['skipped_dup']}")

    if args.mode == "skip-canonical":
        print()
        print("Phase 2: skip-canonical — leaving canonical files untouched.")
        return 0

    if args.mode == "split-file":
        # Spec 398 (corrected post-implementation per /revise 2026-05-07):
        # create docs/.generated/ with renderer-owned artifacts; atomically
        # replace each curated parent's rendered region with the include marker.
        # The script DOES mutate the curated parent — an operator-paste-only
        # model left half-migrated state where the assembled view contained
        # duplicate content (canonical region + spliced generated artifact).
        # The H2-bounded region (anchor → next H2 or EOF) is replaced wholesale
        # with `<H2>\n\n<marker>\n\n` (preserving the H2 line itself).
        print()
        print("Phase 2: split-file — creating docs/.generated/ + atomically rewriting curated parents.")
        from render_backlog import render as render_backlog
        from render_changelog import render as render_changelog
        from render_spec_index import render as render_spec_index
        from split_file_writer import write_split_file_artifact

        generated_dir = (root / "docs" / ".generated").resolve()
        if not args.dry_run:
            generated_dir.mkdir(parents=True, exist_ok=True)

        artifacts = [
            (generated_dir / "backlog-table.md", render_backlog(specs_dir, header=False)),
            (
                generated_dir / "changelog-entries.md",
                render_changelog(specs_dir, events_dir, header=False),
            ),
            (generated_dir / "spec-index-table.md", render_spec_index(specs_dir, header=False)),
        ]

        for target, content in artifacts:
            if args.dry_run:
                print(f"  [dry-run] would write: {target.relative_to(root)} ({len(content)} bytes)")
            else:
                write_split_file_artifact(target, content)
                print(f"  wrote: {target.relative_to(root)}")

        print()
        print("Phase 3 (split-file) — rewriting curated parents (H2-bounded region → include marker):")

        rewrites = [
            (
                root / "docs" / "backlog.md",
                "## Ranked backlog",
                "<!-- FORGE-INCLUDE: .generated/backlog-table.md -->",
            ),
            (
                root / "docs" / "specs" / "CHANGELOG.md",
                "## Entries",
                "<!-- FORGE-INCLUDE: ../.generated/changelog-entries.md -->",
            ),
            (
                root / "docs" / "specs" / "README.md",
                "## Specs",
                "<!-- FORGE-INCLUDE: ../.generated/spec-index-table.md -->",
            ),
        ]

        for parent, h2_anchor, marker in rewrites:
            rel = parent.relative_to(root) if parent.is_relative_to(root) else parent
            if not parent.exists():
                print(f"  - {rel}: SKIP (file does not exist)")
                continue

            original = parent.read_text(encoding="utf-8")
            new_text, action = _rewrite_h2_region(original, h2_anchor, marker)

            if action == "anchor-not-found":
                print(f"  - {rel}: SKIP (anchor `{h2_anchor}` not found)")
                continue
            if action == "no-op":
                print(f"  - {rel}: no-op (region already contains only the marker)")
                continue

            # action: replaced | half-migration-cleaned
            if args.dry_run:
                print(f"  - {rel}: [dry-run] would {action} ({len(original)} → {len(new_text)} bytes)")
                # Show a brief diff preview (range affected)
                lines_before = original.count("\n") + (0 if original.endswith("\n") else 1)
                lines_after = new_text.count("\n") + (0 if new_text.endswith("\n") else 1)
                print(f"      lines: {lines_before} → {lines_after}; H2 anchor preserved; region collapsed to marker")
            else:
                parent.write_text(new_text, encoding="utf-8")
                print(f"  - {rel}: {action} ({len(original)} → {len(new_text)} bytes)")

        # Spec 400 Req 2 — write `.forge/migrations/spec-398.applied` sentinel
        # on successful split-file migration. Single-line file with ISO timestamp + spec ID.
        # Contract extension: copier.yml `_tasks` gate keys off this file's presence.
        # Idempotent: re-running mid-flight overwrites with a fresh timestamp; fresh-copy
        # paths also write the sentinel ("first-render also marks the migration boundary").
        sentinel_path = (root / ".forge" / "migrations" / "spec-398.applied").resolve()
        if args.dry_run:
            print()
            print(f"  [dry-run] would write sentinel: {sentinel_path.relative_to(root)}")
        else:
            sentinel_path.parent.mkdir(parents=True, exist_ok=True)
            sentinel_ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            sentinel_path.write_text(f"{sentinel_ts} spec-398\n", encoding="utf-8")
            print()
            print(f"  wrote sentinel: {sentinel_path.relative_to(root)} ({sentinel_ts} spec-398)")

        print()
        print("Migration complete (split-file mode).")
        return 0


def _rewrite_h2_region(text: str, h2_anchor: str, marker: str) -> tuple[str, str]:
    """Replace lines between `h2_anchor` H2 and the next H2 (or EOF) with `marker`.

    Returns (new_text, action). action ∈ {"replaced", "half-migration-cleaned",
    "no-op", "anchor-not-found"}.

    Idempotent: if the region already contains exactly `\\n<marker>\\n\\n`, returns
    no-op. If the region contains the marker AND additional content (half-migrated
    state — what Spec 398's operator-paste-only model produced), strips the
    additional content and reports half-migration-cleaned.
    """
    lines = text.splitlines(keepends=True)
    h2_idx: int | None = None
    for i, line in enumerate(lines):
        if line.rstrip("\r\n") == h2_anchor:
            h2_idx = i
            break
    if h2_idx is None:
        return text, "anchor-not-found"

    next_h2_idx: int | None = None
    for j in range(h2_idx + 1, len(lines)):
        if lines[j].startswith("## "):
            next_h2_idx = j
            break
    end_idx = next_h2_idx if next_h2_idx is not None else len(lines)

    region = "".join(lines[h2_idx + 1 : end_idx])
    canonical_region = "\n" + marker + "\n\n"
    canonical_region_eof = "\n" + marker + "\n"  # if region runs to EOF, single trailing newline

    if region == canonical_region or region == canonical_region_eof:
        return text, "no-op"

    had_marker = marker in region
    new_region = canonical_region if next_h2_idx is not None else canonical_region_eof
    new_text = "".join(lines[: h2_idx + 1]) + new_region + "".join(lines[end_idx:])
    return new_text, "half-migration-cleaned" if had_marker else "replaced"

    canonicals = [backlog_path, changelog_path]
    spec_index_path = (specs_dir / "README.md").resolve()
    if spec_index_path.exists():
        canonicals.append(spec_index_path)

    if not args.no_backup and not args.dry_run:
        print()
        print("Phase 2a: Backing up canonical files…")
        bdir = backup_canonicals(root=root, paths=canonicals)
        print(f"  Backup written to: {bdir.relative_to(root)}")

    if args.mode == "delete":
        print()
        print("Phase 2b: Deleting canonical files…")
        for c in canonicals:
            if c.exists():
                if args.dry_run:
                    print(f"  [dry-run] would delete: {c.relative_to(root)}")
                else:
                    c.unlink()
                    print(f"  deleted: {c.relative_to(root)}")

    elif args.mode == "generated":
        print()
        print("Phase 2b: Regenerating canonical files via renderers…")
        # Lazy import to avoid circular path issues
        from render_backlog import render as render_backlog
        from render_changelog import render as render_changelog
        from render_spec_index import render as render_spec_index

        rendered_backlog = render_backlog(specs_dir)
        rendered_changelog = render_changelog(specs_dir, events_dir)
        rendered_index = render_spec_index(specs_dir)

        if args.dry_run:
            print(f"  [dry-run] would rewrite: {backlog_path.relative_to(root)} ({len(rendered_backlog)} bytes)")
            print(f"  [dry-run] would rewrite: {changelog_path.relative_to(root)} ({len(rendered_changelog)} bytes)")
            print(f"  [dry-run] would rewrite: {spec_index_path.relative_to(root)} ({len(rendered_index)} bytes)")
        else:
            backlog_path.parent.mkdir(parents=True, exist_ok=True)
            backlog_path.write_text(rendered_backlog, encoding="utf-8")
            changelog_path.parent.mkdir(parents=True, exist_ok=True)
            changelog_path.write_text(rendered_changelog, encoding="utf-8")
            spec_index_path.parent.mkdir(parents=True, exist_ok=True)
            spec_index_path.write_text(rendered_index, encoding="utf-8")
            print(f"  rewrote: {backlog_path.relative_to(root)}")
            print(f"  rewrote: {changelog_path.relative_to(root)}")
            print(f"  rewrote: {spec_index_path.relative_to(root)}")

    print()
    print("Migration complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

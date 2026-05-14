"""FORGE event-stream helpers (Spec 254 — Approach D).

Per-spec append-only JSONL event streams under .forge/state/events/<spec-id>/<event-type>.jsonl.

Each line: {"timestamp": ISO8601, "event_type": str, "payload": {...}}

Defined event types (initial set; forward-extensible):
    spec-started, spec-implemented, spec-closed, spec-deferred, spec-deprecated,
    consensus, revise, signal-reference

Renderers and the migration script consume these via load_events() and iter_spec_dirs().
Lifecycle commands (/implement, /close, /revise, /consensus) write via append_event().

Forward-compat: unknown event_types are accepted (returned in load_events output).
Malformed JSONL lines are skipped with stderr warn including file path + line number.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Iterator, Optional

DEFAULT_BASE_DIR = Path(".forge/state/events")

REQUIRED_FIELDS = ("timestamp", "event_type", "payload")


def iso_now() -> str:
    """Return current time as ISO 8601 UTC with seconds precision (no microseconds)."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def append_event(
    spec_id: str,
    event_type: str,
    payload: Optional[dict] = None,
    *,
    base_dir: Path = DEFAULT_BASE_DIR,
    timestamp: Optional[str] = None,
) -> Path:
    """Append a single event line to .forge/state/events/<spec_id>/<event_type>.jsonl.

    Returns the Path to the file written.
    """
    if payload is None:
        payload = {}
    if timestamp is None:
        timestamp = iso_now()
    record = {"timestamp": timestamp, "event_type": event_type, "payload": payload}
    line = json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n"

    target_dir = Path(base_dir) / str(spec_id)
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / f"{event_type}.jsonl"
    with target.open("a", encoding="utf-8", newline="\n") as f:
        f.write(line)
    return target


def _validate_record(rec: object, source: str) -> Optional[dict]:
    """Validate one parsed JSONL row. Return the dict on success, None on schema violation.

    Schema violations emit a stderr warn but are not fatal (Spec 254 Req 18 — forward-compat).
    """
    if not isinstance(rec, dict):
        sys.stderr.write(f"WARN: {source}: record is not an object — skipping\n")
        return None
    missing = [k for k in REQUIRED_FIELDS if k not in rec]
    if missing:
        sys.stderr.write(f"WARN: {source}: missing required fields {missing} — skipping\n")
        return None
    if not isinstance(rec["timestamp"], str):
        sys.stderr.write(f"WARN: {source}: 'timestamp' must be a string — skipping\n")
        return None
    if not isinstance(rec["event_type"], str):
        sys.stderr.write(f"WARN: {source}: 'event_type' must be a string — skipping\n")
        return None
    if not isinstance(rec["payload"], dict):
        sys.stderr.write(f"WARN: {source}: 'payload' must be an object — skipping\n")
        return None
    return rec


def load_events(
    spec_id: Optional[str] = None,
    event_type: Optional[str] = None,
    *,
    base_dir: Path = DEFAULT_BASE_DIR,
) -> list[dict]:
    """Load events for a given spec_id (and optional event_type filter).

    Returns events sorted by timestamp (lexicographic; ISO 8601 UTC sorts correctly).

    spec_id=None loads events across all specs.
    event_type=None loads all event types under each spec dir.

    Malformed lines are warned to stderr and skipped (Req 18 forward-compat).
    """
    base = Path(base_dir)
    if not base.exists():
        return []

    if spec_id is not None:
        spec_dirs: Iterable[Path] = [base / str(spec_id)]
    else:
        spec_dirs = sorted(p for p in base.iterdir() if p.is_dir())

    events: list[dict] = []
    for spec_dir in spec_dirs:
        if not spec_dir.exists() or not spec_dir.is_dir():
            continue
        if event_type is not None:
            files = [spec_dir / f"{event_type}.jsonl"]
        else:
            files = sorted(spec_dir.glob("*.jsonl"))
        for f in files:
            if not f.exists():
                continue
            with f.open(encoding="utf-8") as fp:
                for lineno, raw in enumerate(fp, 1):
                    raw = raw.rstrip("\n").rstrip("\r")
                    if not raw.strip():
                        continue
                    try:
                        parsed = json.loads(raw)
                    except json.JSONDecodeError as e:
                        sys.stderr.write(
                            f"WARN: {f}:{lineno}: invalid JSON ({e}) — skipping\n"
                        )
                        continue
                    rec = _validate_record(parsed, f"{f}:{lineno}")
                    if rec is None:
                        continue
                    rec["_source_file"] = str(f)
                    rec["_spec_id"] = spec_dir.name
                    events.append(rec)

    events.sort(key=lambda e: (e.get("timestamp", ""), e.get("event_type", "")))
    return events


def iter_spec_dirs(*, base_dir: Path = DEFAULT_BASE_DIR) -> Iterator[Path]:
    """Yield each per-spec event directory under base_dir."""
    base = Path(base_dir)
    if not base.exists():
        return
    for p in sorted(base.iterdir()):
        if p.is_dir():
            yield p

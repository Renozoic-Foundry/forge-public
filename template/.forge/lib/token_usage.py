#!/usr/bin/env python3
"""FORGE token-usage capture (Spec 497, consuming Spec 496 GO / ADR-496).

ADR-496 returned GO: per-session token usage is durably capturable by parsing
the on-disk transcript JSONL (each assistant message carries a ``usage`` object).
This helper parses a transcript and emits a **token-only** record with the
ADR-496 field shape:

    {input_tokens, output_tokens, cache_creation_input_tokens,
     cache_read_input_tokens, total_tokens}

Per ADR-316 + ADR-496 it stores **token counts only** — never a cost (USD)
figure. ``total_tokens`` is the sum of the four movement fields.

Capture point (Spec 496-specified): end-of-/implement (or a Stop/SessionEnd
hook). /implement writes the record to the per-spec event stream as the
working-tree capture point; /session folds the latest record into the durable
``token_usage`` field of the session sidecar (tracked ``docs/sessions/*.json``).

Usage:
    forge-py .forge/lib/token_usage.py record --spec NNN --transcript PATH
                                       [--events-dir .forge/state/events] [--json]
    forge-py .forge/lib/token_usage.py parse --transcript PATH   # print record only

Exit code is always 0 — advisory telemetry; an unreadable transcript yields a
zeroed record rather than a failure.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import sys

# Token-only field shape (ADR-496). Order is canonical for the emitted record.
_FIELDS = (
    "input_tokens",
    "output_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
)


def _extract_usage(obj):
    """Return the usage dict from a transcript line, whether nested or top-level."""
    if not isinstance(obj, dict):
        return None
    msg = obj.get("message")
    if isinstance(msg, dict) and isinstance(msg.get("usage"), dict):
        return msg["usage"]
    if isinstance(obj.get("usage"), dict):
        return obj["usage"]
    return None


def parse_transcript(transcript_path: str) -> dict:
    """Sum token usage across every assistant message in a transcript JSONL."""
    totals = {f: 0 for f in _FIELDS}
    try:
        with open(transcript_path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue  # advisory: skip a malformed line
                usage = _extract_usage(obj)
                if not usage:
                    continue
                for field in _FIELDS:
                    val = usage.get(field)
                    if isinstance(val, int):
                        totals[field] += val
    except OSError:
        pass  # advisory: zeroed record on unreadable transcript

    record = dict(totals)
    record["total_tokens"] = sum(totals[f] for f in _FIELDS)
    return record


def _events_path(events_dir: str, spec: str) -> str:
    return os.path.join(events_dir, spec, "token-usage.jsonl")


def write_event(events_dir: str, spec: str, record: dict) -> str | None:
    """Append a token-usage event to the per-spec event stream. Advisory."""
    path = _events_path(events_dir, spec)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        event = {
            "timestamp": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "event_type": "token-usage",
            "payload": record,
        }
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(event) + "\n")
        return path
    except OSError:
        sys.stderr.write("WARN: token-usage event append failed (advisory; caller continues)\n")
        return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="FORGE token-usage capture (Spec 497)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_rec = sub.add_parser("record", help="parse transcript and write per-spec token-usage event")
    p_rec.add_argument("--spec", required=True, help="spec id, e.g. 497")
    p_rec.add_argument("--transcript", required=True, help="path to the transcript JSONL")
    p_rec.add_argument("--events-dir", default=".forge/state/events", help="per-spec event stream root")
    p_rec.add_argument("--json", action="store_true", help="print the record as JSON")

    p_parse = sub.add_parser("parse", help="parse transcript and print the record (no write)")
    p_parse.add_argument("--transcript", required=True, help="path to the transcript JSONL")

    args = parser.parse_args(argv)
    record = parse_transcript(args.transcript)

    if args.cmd == "record":
        path = write_event(args.events_dir, args.spec, record)
        if args.json:
            print(json.dumps(record))
        elif path:
            print(f"token-usage recorded: {path} ({record['total_tokens']} total tokens)")
    else:  # parse
        print(json.dumps(record))
    return 0


if __name__ == "__main__":
    sys.exit(main())

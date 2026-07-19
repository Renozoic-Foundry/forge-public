#!/usr/bin/env python3
"""FORGE rolling consensus acceptance-rate reader (Spec 497, read side of Spec 495).

Closes Spec 258 AC#5. Computes the rolling N-day (default 30) consensus
# forge:path-literal-ok (docstring/prose — classic-default spelling in help text; Spec 575)
acceptance rate from the session sidecars at ``docs/sessions/*.json``, per the
read-side contract in ``docs/process-kit/telemetry-capture-guide.md``:
# forge:path-literal-ok (comment) — module-docstring prose, actual default resolved below

    acceptance_rate = accepted / (accepted + modified + rejected)

Source: ``consensus_reviews[].operator_decision`` (canonical) plus the
``consensus_outcomes[]`` alias (the Spec 258 prose name) so historical sidecars
count. Classification is on the leading token of ``operator_decision``:
``accepted`` | ``modified`` (accepted-with-revisions) | ``rejected``; any other
value (e.g. ``deferred``) is procedural and excluded from the rate.

Window: a sidecar counts when its top-level ``date`` is within ``--days`` of
``--today`` (default: the system date). The empty-denominator case (no rated
decisions in the window) reports ``n/a`` — never a divide-by-zero (Spec 497 DA
finding).

This is a substrate reader invoked by thin call sites in ``/now`` and
``/evolve`` F4 — both call it identically (cross-platform via forge-py), so the
logic is not duplicated in command bodies.

Usage:
    forge-py .forge/lib/acceptance_rate.py [--days 30] [--sessions-dir DIR]
                                           [--today YYYY-MM-DD] [--json]

Exit code is always 0 — this is advisory telemetry; a parse error on one
sidecar is skipped, not fatal.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import glob
import json
import os
import sys
from pathlib import Path

_LIB_DIR = Path(__file__).resolve().parent
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))
try:
    from runtime_config import resolve_path as _rc_resolve_path  # Spec 564 helper
except ImportError:
    _rc_resolve_path = None

_BUCKETS = ("accepted", "modified", "rejected")


def _default_sessions_dir() -> str:
    """Resolve forge.paths.sessions via runtime_config; fall back to the classic default."""
    if _rc_resolve_path is not None:
        try:
            value, error = _rc_resolve_path(Path("."), "sessions")
            if not error and value:
                return value
        except Exception:
            pass
    return "docs/sessions"


def _classify(decision: str) -> str | None:
    """Map an operator_decision to a rate bucket on its leading token, or None."""
    if not isinstance(decision, str):
        return None
    token = decision.strip().lower().split()[0] if decision.strip() else ""
    # Tolerate punctuation after the leading word, e.g. "accepted," / "modified:".
    token = token.strip(",.;:()")
    return token if token in _BUCKETS else None


def _parse_date(value) -> _dt.date | None:
    if not isinstance(value, str):
        return None
    value = value.strip()
    # Accept bare dates and ISO timestamps; take the date portion.
    head = value.split("T")[0].split(" ")[0]
    try:
        return _dt.date.fromisoformat(head)
    except ValueError:
        return None


def _iter_reviews(sidecar: dict):
    """Yield review items from both the canonical and alias arrays."""
    for key in ("consensus_reviews", "consensus_outcomes"):
        arr = sidecar.get(key)
        if isinstance(arr, list):
            for item in arr:
                if isinstance(item, dict):
                    yield item


def compute(sessions_dir: str, days: int, today: _dt.date) -> dict:
    counts = {b: 0 for b in _BUCKETS}
    window_start = today - _dt.timedelta(days=days)
    sidecars_scanned = 0
    sidecars_in_window = 0

    for path in sorted(glob.glob(os.path.join(sessions_dir, "*.json"))):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            continue  # advisory: skip a malformed/unreadable sidecar
        if not isinstance(data, dict):
            continue
        sidecars_scanned += 1
        sidecar_date = _parse_date(data.get("date"))
        if sidecar_date is None or not (window_start < sidecar_date <= today):
            continue
        sidecars_in_window += 1
        for review in _iter_reviews(data):
            bucket = _classify(review.get("operator_decision", ""))
            if bucket:
                counts[bucket] += 1

    denom = counts["accepted"] + counts["modified"] + counts["rejected"]
    rate = (counts["accepted"] / denom) if denom else None
    return {
        "window_days": days,
        "today": today.isoformat(),
        "accepted": counts["accepted"],
        "modified": counts["modified"],
        "rejected": counts["rejected"],
        "rated_total": denom,
        "acceptance_rate": rate,  # float in [0,1] or None when denom == 0
        "sidecars_scanned": sidecars_scanned,
        "sidecars_in_window": sidecars_in_window,
    }


def format_line(result: dict) -> str:
    if result["rated_total"] == 0:
        return (
            f"Consensus acceptance rate (last {result['window_days']}d): n/a "
            f"(no rated decisions in window)"
        )
    pct = round(result["acceptance_rate"] * 100)
    return (
        f"Consensus acceptance rate (last {result['window_days']}d): {pct}% "
        f"({result['accepted']}/{result['rated_total']} accepted; "
        f"{result['modified']} modified, {result['rejected']} rejected)"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="FORGE consensus acceptance-rate reader (Spec 497)")
    parser.add_argument("--days", type=int, default=30, help="rolling window size in days (default 30)")
    parser.add_argument("--sessions-dir", default=_default_sessions_dir(), help="directory of session sidecars")
    parser.add_argument("--today", default=None, help="reference date YYYY-MM-DD (default: system date)")
    parser.add_argument("--json", action="store_true", help="emit the full result as JSON")
    args = parser.parse_args(argv)

    if args.today:
        today = _parse_date(args.today) or _dt.date.today()
    else:
        today = _dt.date.today()

    result = compute(args.sessions_dir, args.days, today)
    if args.json:
        print(json.dumps(result))
    else:
        print(format_line(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())

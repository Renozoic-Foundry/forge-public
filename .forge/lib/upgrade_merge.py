#!/usr/bin/env python3
# forge:path-literal-ok (file: docstring prose + RUNBOOK_PATH operator-facing pointer — classic-default process-kit spelling, Spec 575)
"""Spec 559 — content-merge upgrade mechanism: 3-way merge engine.

Replaces `/forge stoke`'s `copier update` apply step for project-data files,
behind the opt-in `--merge-native` flag (classic `copier update` stays default
until Spec 558). Genuine 3-way merge (base/ours/theirs), DISTINCT from
`/reconcile`'s additive-only ingestion model (CTO critical, consensus R1).

Design constraints (Req 2, Constraints):
  - Base-snapshot state lives OUTSIDE `.git/` (default: `.forge/state/upgrade-base/`).
    This module never invokes git plumbing that writes objects/refs/index
    (no `git hash-object -w`, no direct `.git/objects` mutation) -- closes the
    git-corruption defect class documented in
    docs/process-kit/stoke-recovery-runbook.md Sec 1a.
  - Bootstrap (no recorded base for a file): the engine treats "ours" as if it
    were "theirs-at-install" -- i.e. the CURRENT ours content becomes the
    synthetic base for this run (no guessing at history). Because ours then
    trivially equals base, the merge cleanly adopts theirs with zero conflicts
    (Req 2 AC1/AC2 bootstrap semantics).
  - Conflict-marker convention matches stoke.py's existing
    `_scan_for_conflict_markers` / `_emit_recovery_output` shape
    (`<<<<<<<` / `=======` / `>>>>>>>`), and the recovery text names
    docs/process-kit/stoke-recovery-runbook.md, so that runbook stays the
    single recovery reference (no parallel runbook created).

Algorithm: a stdlib-only (ADR-359) line-based diff3, using difflib matching
blocks to find base-anchored synchronization points common to both `ours` and
`theirs`, then resolving each in-between gap:
  - unchanged in ours              -> take theirs
  - unchanged in theirs            -> take ours
  - changed identically both sides -> take either
  - changed differently both sides -> CONFLICT (markers emitted)

Usage:
    forge-py .forge/lib/upgrade_merge.py merge \
        --project-root DIR --upstream DIR [--state-dir DIR] --files REL [REL ...]

Exit codes: 0 = all files merged clean; 1 = one or more conflicts (files named
on stdout/stderr); 2 = argument/IO error.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

DEFAULT_STATE_DIR = ".forge/state/upgrade-base"
RUNBOOK_PATH = "docs/process-kit/stoke-recovery-runbook.md"


def _read_lines(path: Path) -> list[str]:
    # newline="" disables universal-newline translation on read so line-ending
    # bytes are preserved verbatim (Windows CRLF stays CRLF) -- paired with the
    # matching write below to avoid platform-dependent line-ending drift.
    if not path.is_file():
        return []
    try:
        text = path.read_text(encoding="utf-8", errors="replace", newline="")
    except OSError:
        return []
    return text.splitlines(keepends=True)


def _write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(lines), encoding="utf-8", newline="")


def _matching_map(base: list[str], other: list[str]) -> dict[int, int]:
    """base-index -> other-index for lines difflib considers unchanged."""
    import difflib

    sm = difflib.SequenceMatcher(None, base, other, autojunk=False)
    mapping: dict[int, int] = {}
    for block in sm.get_matching_blocks():
        for k in range(block.size):
            mapping[block.a + k] = block.b + k
    return mapping


def merge3(base: list[str], ours: list[str], theirs: list[str]) -> tuple[list[str], bool]:
    """Line-based 3-way merge. Returns (merged_lines, has_conflict)."""
    ours_map = _matching_map(base, ours)
    theirs_map = _matching_map(base, theirs)

    sync = sorted(i for i in range(len(base)) if i in ours_map and i in theirs_map)
    anchors: list[tuple[int, int]] = []
    idx = 0
    n = len(sync)
    while idx < n:
        start = sync[idx]
        end = start
        while (
            idx + 1 < n
            and sync[idx + 1] == end + 1
            and ours_map[end + 1] == ours_map[end] + 1
            and theirs_map[end + 1] == theirs_map[end] + 1
        ):
            idx += 1
            end = sync[idx]
        anchors.append((start, end))
        idx += 1

    merged: list[str] = []
    conflict = False
    prev_base = prev_ours = prev_theirs = 0

    def emit_gap(b_lo: int, b_hi: int, o_lo: int, o_hi: int, t_lo: int, t_hi: int) -> None:
        nonlocal conflict
        base_seg = base[b_lo:b_hi]
        ours_seg = ours[o_lo:o_hi]
        theirs_seg = theirs[t_lo:t_hi]
        if ours_seg == base_seg:
            merged.extend(theirs_seg)
        elif theirs_seg == base_seg:
            merged.extend(ours_seg)
        elif ours_seg == theirs_seg:
            merged.extend(ours_seg)
        else:
            conflict = True
            merged.append("<<<<<<< ours\n")
            merged.extend(ours_seg)
            merged.append("=======\n")
            merged.extend(theirs_seg)
            merged.append(">>>>>>> theirs\n")

    for a_start, a_end in anchors:
        o_start = ours_map[a_start]
        t_start = theirs_map[a_start]
        emit_gap(prev_base, a_start, prev_ours, o_start, prev_theirs, t_start)
        merged.extend(base[a_start : a_end + 1])
        prev_base = a_end + 1
        prev_ours = ours_map[a_end] + 1
        prev_theirs = theirs_map[a_end] + 1

    emit_gap(prev_base, len(base), prev_ours, len(ours), prev_theirs, len(theirs))
    return merged, conflict


def _emit_recovery(conflicted: list[str]) -> None:
    print("=" * 64, file=sys.stderr)
    print("UPGRADE-MERGE CONFLICT(S) — merge-native did not complete cleanly", file=sys.stderr)
    print("=" * 64, file=sys.stderr)
    print("Files with conflict markers:", file=sys.stderr)
    for rel in conflicted:
        print(f"  - {rel}", file=sys.stderr)
    print("\nRecovery — per-file:", file=sys.stderr)
    for rel in conflicted:
        print(f"  # resolve <<<<<<< / ======= / >>>>>>> markers in {rel} manually, then re-run", file=sys.stderr)
    print(f"\nRunbook: {RUNBOOK_PATH}", file=sys.stderr)
    print("=" * 64, file=sys.stderr)


def cmd_merge(args: argparse.Namespace) -> int:
    project_root = Path(args.project_root)
    upstream_root = Path(args.upstream)
    state_dir = Path(args.state_dir)

    conflicted: list[str] = []
    for rel in args.files:
        ours_path = project_root / rel
        theirs_path = upstream_root / rel
        base_path = state_dir / rel

        ours_lines = _read_lines(ours_path)
        theirs_lines = _read_lines(theirs_path)

        bootstrap = not base_path.is_file()
        base_lines = ours_lines if bootstrap else _read_lines(base_path)

        merged_lines, conflict = merge3(base_lines, ours_lines, theirs_lines)

        _write_lines(ours_path, merged_lines)
        # Record the new base (this run's upstream content) for the next run.
        # Base-snapshot storage lives OUTSIDE .git/ (Req 2/Constraints).
        _write_lines(base_path, theirs_lines)

        tag = "CONFLICT" if conflict else "clean"
        suffix = " (bootstrap)" if bootstrap else ""
        print(f"{tag}: {rel}{suffix}")
        if conflict:
            conflicted.append(rel)

    if conflicted:
        _emit_recovery(conflicted)
        return 1
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Spec 559 3-way content-merge engine (merge-native)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    m = sub.add_parser("merge", help="3-way merge upstream content into the project working tree")
    m.add_argument("--project-root", required=True, help="live 'ours' tree (merge result written here)")
    m.add_argument("--upstream", required=True, help="'theirs' tree (new upstream content)")
    m.add_argument("--state-dir", default=DEFAULT_STATE_DIR, help="recorded base snapshots (outside .git/)")
    m.add_argument("--files", nargs="+", required=True, help="repo-relative file paths to merge")
    m.set_defaults(func=cmd_merge)

    args = ap.parse_args()
    try:
        return args.func(args)
    except OSError as exc:
        print(f"upgrade_merge: IO error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

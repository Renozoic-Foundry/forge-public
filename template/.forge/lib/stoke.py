#!/usr/bin/env python3
"""Spec 381 — /forge stoke transactional shadow-tree helper.

Single Python source for stoke's transactional safety mechanism. Bash and
PowerShell wrappers (.forge/lib/stoke.{sh,ps1}) forward args here — they
contain no business logic, eliminating the 3-language drift surface CEfO
flagged in /consensus round 3.

Subcommands:
  shadow-create [--shadow-dir DIR]
      Create a shadow tree at $TMPDIR/forge-stoke-shadow-<pid> (or DIR).
      Copies all tracked files (git ls-files) into it. Captures mtime baseline
      to <shadow>/.mtime-baseline.tsv. Prints the shadow path on stdout.
      Live tree's untracked files NEVER enter shadow — Step 0b restoration in
      shadow cannot collide with operator's untracked working content.

  audit <shadow-dir> [--live-root DIR] [--soft-pct N] [--hard-pct N] [--min-lines N]
      Compare shadow vs live for Tier 3 files (AGENTS.md, CLAUDE.md, .mcp.json).
      Predicate (per Spec 381 R3): audit fires for a file when ANY of:
        - sections_lost > 0  (H2 sections present in live but missing in shadow)
        - delta_pct > N AND delta_lines >= M  (combined backstop, default 30%/15)
      Output: JSON with {fired: bool, flagged: [{path, pre_lines, post_lines,
      delta_lines, delta_pct, sections_lost: [names...], severity: "high"|"low"}]}.
      Silent on clean stokes (fired=false → no output to stderr; JSON still
      printed to stdout for caller to parse).

  mtime-check <shadow-dir> [--live-root DIR]
      Compare current mtime of each tracked file in live vs the baseline
      captured at shadow-create. Prints any drifted paths (one per line,
      stderr). Exit 0 = no drift; exit 1 = drift detected (race window).

  apply <shadow-dir> [--live-root DIR] [--exclude PATH ...]
      Apply shadow → live atomically. For each tracked file in shadow:
        1. Write shadow content to <live>/<rel>.new
        2. fsync the .new file
        3. os.replace(.new, <rel>) — atomic POSIX rename
      Files matching --exclude paths are SKIPPED (kept at live's existing
      version per recover-all/recover-selective semantics).

  cleanup <shadow-dir>
      rm -rf the shadow directory. Always exits 0 (idempotent).

  orphan-gc [--max-age-hours N]
      Remove orphaned $TMPDIR/forge-stoke-shadow-* directories older than N
      hours (default 24). Caller invokes at start of next stoke per Spec 381 R9.

Constraints (Spec 381 Constraints section):
  - No rsync dependency. Uses os.replace (atomic on POSIX, MOVEFILE_REPLACE_EXISTING
    on Windows via Python's wrapper).
  - No mutation of the live tree until `apply` is invoked explicitly.
  - No retention. Caller is responsible for invoking `cleanup` at end of every stoke.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

TIER3_FILES = ("AGENTS.md", "CLAUDE.md", ".mcp.json")
DEFAULT_SOFT_PCT = 30
DEFAULT_HARD_PCT = 30  # combined-backstop %, NOT a separate tier (Spec 381 R3)
DEFAULT_MIN_LINES = 15
SHADOW_PREFIX = "forge-stoke-shadow-"


# ---- shadow-create ----------------------------------------------------------

def cmd_shadow_create(args: argparse.Namespace) -> int:
    if args.shadow_dir:
        shadow = Path(args.shadow_dir)
    else:
        tmp = Path(tempfile.gettempdir())
        shadow = tmp / f"{SHADOW_PREFIX}{os.getpid()}"
    shadow.mkdir(parents=True, exist_ok=False)
    try:
        os.chmod(shadow, 0o700)
    except OSError:
        pass

    # Enumerate tracked files via git ls-files
    try:
        result = subprocess.run(
            ["git", "ls-files"], capture_output=True, text=True, check=True
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"ERROR: git ls-files failed: {e}", file=sys.stderr)
        shutil.rmtree(shadow, ignore_errors=True)
        return 2

    tracked = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if not tracked:
        print(f"ERROR: no tracked files (git ls-files empty)", file=sys.stderr)
        shutil.rmtree(shadow, ignore_errors=True)
        return 2

    # Copy tracked files preserving directory structure; capture mtime baseline
    baseline_path = shadow / ".mtime-baseline.tsv"
    with baseline_path.open("w", encoding="utf-8") as baseline_f:
        for rel in tracked:
            src = Path(rel)
            if not src.is_file():
                continue  # tracked but missing from working tree (deleted, not committed)
            dst = shadow / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            try:
                mtime_ns = src.stat().st_mtime_ns
            except OSError:
                mtime_ns = 0
            baseline_f.write(f"{rel}\t{mtime_ns}\n")

    print(str(shadow))
    return 0


# ---- audit ------------------------------------------------------------------

_FENCE_RE = re.compile(r"^(?:```|~~~)")
_H2_RE = re.compile(r"^##\s+(.+?)\s*$")


def _parse_h2_sections(text: str) -> list[str]:
    """ATX-only H2 parser. Skips fenced code blocks. Treats YAML front-matter
    (between leading `---` lines) as a single named pseudo-section."""
    lines = text.splitlines()
    sections: list[str] = []
    in_fence = False
    in_yaml_front = False

    if lines and lines[0].strip() == "---":
        in_yaml_front = True
        sections.append("__yaml_frontmatter__")

    for i, line in enumerate(lines):
        if in_yaml_front:
            if i > 0 and line.strip() == "---":
                in_yaml_front = False
            continue
        if _FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = _H2_RE.match(line)
        if m:
            sections.append(m.group(1))
    return sections


def _audit_file(live_path: Path, shadow_path: Path, hard_pct: int, min_lines: int) -> dict | None:
    """Compute audit result for one Tier 3 file. Returns None if file absent."""
    if not live_path.is_file():
        return None
    if not shadow_path.is_file():
        # Shadow lacks the file (deleted by stoke?). Treat as full deletion.
        live_text = live_path.read_text(encoding="utf-8", errors="replace")
        live_lines = len(live_text.splitlines())
        return {
            "path": str(live_path.name),
            "pre_lines": live_lines,
            "post_lines": 0,
            "delta_lines": live_lines,
            "delta_pct": 100,
            "sections_lost": _parse_h2_sections(live_text),
            "fired": True,
            "severity": "high",
        }

    live_text = live_path.read_text(encoding="utf-8", errors="replace")
    shadow_text = shadow_path.read_text(encoding="utf-8", errors="replace")
    pre_lines = len(live_text.splitlines())
    post_lines = len(shadow_text.splitlines())
    delta_lines = pre_lines - post_lines  # positive = lines removed
    delta_pct = round((delta_lines * 100) / max(pre_lines, 1))

    live_sections = _parse_h2_sections(live_text)
    shadow_sections = _parse_h2_sections(shadow_text)
    sections_lost = [s for s in live_sections if s not in shadow_sections]

    # Audit predicate: sections_lost > 0 OR (delta_pct > hard_pct AND delta_lines >= min_lines)
    fired_section = len(sections_lost) > 0
    fired_backstop = delta_pct > hard_pct and delta_lines >= min_lines
    fired = fired_section or fired_backstop

    severity = "high" if (sections_lost or delta_pct > hard_pct) else "low"

    return {
        "path": str(live_path.name),
        "pre_lines": pre_lines,
        "post_lines": post_lines,
        "delta_lines": delta_lines,
        "delta_pct": delta_pct,
        "sections_lost": sections_lost,
        "fired": fired,
        "severity": severity,
    }


def cmd_audit(args: argparse.Namespace) -> int:
    shadow = Path(args.shadow_dir)
    live_root = Path(args.live_root) if args.live_root else Path.cwd()

    flagged = []
    any_fired = False
    for fname in TIER3_FILES:
        live_path = live_root / fname
        shadow_path = shadow / fname
        result = _audit_file(live_path, shadow_path, args.hard_pct, args.min_lines)
        if result is None:
            continue
        flagged.append(result)
        if result["fired"]:
            any_fired = True

    # Sort by severity (high first), then delta_pct desc
    flagged.sort(key=lambda r: (0 if r["severity"] == "high" else 1, -r["delta_pct"]))

    output = {
        "fired": any_fired,
        "flagged": [r for r in flagged if r["fired"]],
        "all_files": flagged,
    }
    print(json.dumps(output, indent=2))
    return 0


# ---- mtime-check ------------------------------------------------------------

def cmd_mtime_check(args: argparse.Namespace) -> int:
    shadow = Path(args.shadow_dir)
    live_root = Path(args.live_root) if args.live_root else Path.cwd()
    baseline_path = shadow / ".mtime-baseline.tsv"
    if not baseline_path.is_file():
        print(f"ERROR: baseline not found at {baseline_path}", file=sys.stderr)
        return 2

    drifted = []
    with baseline_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            try:
                rel, expected_str = line.split("\t", 1)
            except ValueError:
                continue
            expected = int(expected_str)
            live_file = live_root / rel
            if not live_file.is_file():
                continue
            try:
                actual = live_file.stat().st_mtime_ns
            except OSError:
                continue
            if actual != expected:
                drifted.append(rel)

    if drifted:
        for rel in drifted:
            print(rel, file=sys.stderr)
        return 1
    return 0


# ---- apply ------------------------------------------------------------------

def cmd_apply(args: argparse.Namespace) -> int:
    shadow = Path(args.shadow_dir)
    live_root = Path(args.live_root) if args.live_root else Path.cwd()
    excludes = set(args.exclude or [])

    # Walk shadow tree, applying each file to live (excluding .mtime-baseline.tsv)
    applied = 0
    skipped = 0
    for shadow_file in shadow.rglob("*"):
        if not shadow_file.is_file():
            continue
        rel = shadow_file.relative_to(shadow)
        if str(rel) == ".mtime-baseline.tsv":
            continue
        rel_str = str(rel).replace("\\", "/")
        if rel_str in excludes or rel.name in excludes:
            skipped += 1
            continue
        target = live_root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        new_path = target.with_suffix(target.suffix + ".new")
        shutil.copy2(shadow_file, new_path)
        # fsync
        try:
            with open(new_path, "rb") as fh:
                os.fsync(fh.fileno())
        except OSError:
            pass
        # Atomic rename — os.replace works on POSIX and Windows (MoveFileEx with REPLACE)
        os.replace(new_path, target)
        applied += 1

    print(json.dumps({"applied": applied, "skipped": skipped}))
    return 0


# ---- cleanup ----------------------------------------------------------------

def cmd_cleanup(args: argparse.Namespace) -> int:
    shadow = Path(args.shadow_dir)
    if shadow.is_dir():
        shutil.rmtree(shadow, ignore_errors=True)
    return 0


# ---- orphan-gc --------------------------------------------------------------

def cmd_parse_sections(args: argparse.Namespace) -> int:
    """Print H2 section names from a markdown file, one per line. Used by fixtures."""
    text = Path(args.file_path).read_text(encoding="utf-8", errors="replace")
    for name in _parse_h2_sections(text):
        print(name)
    return 0


def cmd_orphan_gc(args: argparse.Namespace) -> int:
    tmp = Path(tempfile.gettempdir())
    cutoff = time.time() - (args.max_age_hours * 3600)
    removed = 0
    for entry in tmp.glob(f"{SHADOW_PREFIX}*"):
        if not entry.is_dir():
            continue
        try:
            mtime = entry.stat().st_mtime
        except OSError:
            continue
        if mtime < cutoff:
            shutil.rmtree(entry, ignore_errors=True)
            removed += 1
    print(json.dumps({"removed": removed}))
    return 0


# ---- main -------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(prog="stoke.py", description="Spec 381 stoke shadow-tree helper")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("shadow-create")
    p.add_argument("--shadow-dir", default=None)
    p.set_defaults(func=cmd_shadow_create)

    p = sub.add_parser("audit")
    p.add_argument("shadow_dir")
    p.add_argument("--live-root", default=None)
    p.add_argument("--hard-pct", type=int, default=DEFAULT_HARD_PCT)
    p.add_argument("--min-lines", type=int, default=DEFAULT_MIN_LINES)
    p.set_defaults(func=cmd_audit)

    p = sub.add_parser("mtime-check")
    p.add_argument("shadow_dir")
    p.add_argument("--live-root", default=None)
    p.set_defaults(func=cmd_mtime_check)

    p = sub.add_parser("apply")
    p.add_argument("shadow_dir")
    p.add_argument("--live-root", default=None)
    p.add_argument("--exclude", action="append", default=[])
    p.set_defaults(func=cmd_apply)

    p = sub.add_parser("cleanup")
    p.add_argument("shadow_dir")
    p.set_defaults(func=cmd_cleanup)

    p = sub.add_parser("orphan-gc")
    p.add_argument("--max-age-hours", type=float, default=24)
    p.set_defaults(func=cmd_orphan_gc)

    # parse-sections — exposed for fixture testability of the H2 parser (AC15)
    p = sub.add_parser("parse-sections")
    p.add_argument("file_path")
    p.set_defaults(func=cmd_parse_sections)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

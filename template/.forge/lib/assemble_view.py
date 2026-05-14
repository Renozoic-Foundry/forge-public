#!/usr/bin/env python3
"""FORGE assemble-view (Spec 398 — Split-File Rendering Architecture).

Reads a curated parent file + resolves FORGE-INCLUDE markers to their
referenced generated artifacts + emits the assembled view to stdout.

Render-time only — never persists output. Binary-mode I/O throughout to
preserve CRLF/BOM/encoding byte-for-byte (DA-critical from /consensus
round 1).

Usage:
    python3 .forge/lib/assemble_view.py <curated-parent-path>

Examples:
    python3 .forge/lib/assemble_view.py docs/backlog.md
    python3 .forge/lib/assemble_view.py docs/specs/CHANGELOG.md

Marker syntax (single line, in the curated parent):
    <!-- FORGE-INCLUDE: <relative-path> -->

The path is resolved relative to the curated parent's directory.

Exit codes:
  0 = success (may include stderr stale-warning)
  1 = referenced generated artifact missing
  2 = argument / I/O error
"""

from __future__ import annotations

import re
import sys

# Spec 401: Python 3.10+ floor — defense-in-depth for direct invocation when forge-py wrapper is bypassed.
if sys.version_info < (3, 10):
    sys.stderr.write(f"error: Python 3.10+ required (found {sys.version_info.major}.{sys.version_info.minor})\n")
    sys.exit(1)
from pathlib import Path

# Marker regex: line-anchored, single-line, whitespace-tolerant inside the comment.
# Captures the relative path. The marker MUST occupy the entire line content
# (modulo leading/trailing whitespace and the platform's line ending).
# Tolerates CRLF: the trailing `[ \t]*\r?` allows the carriage return that
# precedes `\n` on Windows-line-ending files (re.MULTILINE's `$` anchors
# before `\n`, not before `\r\n`).
_MARKER_RE = re.compile(
    rb"^[ \t]*<!--[ \t]+FORGE-INCLUDE:[ \t]+(?P<path>[^\s][^\r\n]*?)[ \t]+-->[ \t]*\r?$",
    re.MULTILINE,
)

_STALE_WARNING = b"stale view: run /matrix to regenerate"


def _detect_line_ending(content: bytes) -> bytes:
    """Return b'\\r\\n' if dominant in content, else b'\\n'."""
    crlf = content.count(b"\r\n")
    lf = content.count(b"\n") - crlf
    if crlf > lf:
        return b"\r\n"
    return b"\n"


def _is_stale(parent_path: Path, generated_paths: list[Path]) -> bool:
    """Return True if any generated artifact is older than any spec file or
    event-stream file under the project root.

    Project root inferred as the parent's anchor (walk up to find a `docs/`
    sibling of `.forge/`). Best-effort — staleness is a warning, not a gate.
    """
    # Find project root: walk up from parent until we find both `docs/` and `.forge/`
    root = parent_path.resolve().parent
    while root != root.parent:
        if (root / "docs").is_dir() and (root / ".forge").is_dir():
            break
        root = root.parent
    else:
        return False

    specs_dir = root / "docs" / "specs"
    events_dir = root / ".forge" / "state" / "events"

    if not generated_paths:
        return False

    try:
        gen_mtime = min(p.stat().st_mtime for p in generated_paths if p.exists())
    except (OSError, ValueError):
        return False

    candidates: list[float] = []
    if specs_dir.is_dir():
        for f in specs_dir.glob("*.md"):
            try:
                candidates.append(f.stat().st_mtime)
            except OSError:
                continue
    if events_dir.is_dir():
        for f in events_dir.rglob("*.jsonl"):
            try:
                candidates.append(f.stat().st_mtime)
            except OSError:
                continue

    if not candidates:
        return False
    return max(candidates) > gen_mtime


def assemble(parent_path: Path) -> tuple[bytes, list[Path], list[Path]]:
    """Read parent + resolve markers → assembled bytes.

    Returns (assembled_bytes, resolved_artifact_paths, missing_paths).
    Raises FileNotFoundError if parent itself is missing.
    """
    parent_bytes = parent_path.read_bytes()
    parent_dir = parent_path.parent

    resolved: list[Path] = []
    missing: list[Path] = []

    def _replace(match: re.Match[bytes]) -> bytes:
        rel = match.group("path").decode("utf-8").strip()
        target = (parent_dir / rel).resolve()
        if not target.exists():
            missing.append(target)
            return match.group(0)  # leave marker untouched on missing
        resolved.append(target)
        # Read in binary; do NOT decode/re-encode. Strip exactly one trailing
        # newline if present (the splice already replaces a line that ended
        # in a newline; we don't want a double-blank).
        content = target.read_bytes()
        if content.endswith(b"\r\n"):
            content = content[:-2]
        elif content.endswith(b"\n"):
            content = content[:-1]
        return content

    assembled = _MARKER_RE.sub(_replace, parent_bytes)
    return assembled, resolved, missing


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1 or args[0] in ("-h", "--help"):
        sys.stderr.write(
            "usage: assemble_view.py <curated-parent-path>\n"
            "  reads curated parent + resolves FORGE-INCLUDE markers\n"
            "  emits assembled view to stdout (binary)\n"
        )
        return 2 if args and args[0] not in ("-h", "--help") else 0

    parent_path = Path(args[0])
    if not parent_path.exists():
        sys.stderr.write(f"error: curated parent not found: {parent_path}\n")
        return 2

    try:
        assembled, resolved, missing = assemble(parent_path)
    except OSError as exc:
        sys.stderr.write(f"error: I/O failure: {exc}\n")
        return 2

    if missing:
        for m in missing:
            sys.stderr.write(
                f"error: FORGE-INCLUDE referenced missing generated artifact: {m}\n"
                f"  regenerate with one of:\n"
                f"    python .forge/lib/render_backlog.py --mode=split-file\n"
                f"    python .forge/lib/render_changelog.py --mode=split-file\n"
                f"    python .forge/lib/render_spec_index.py --mode=split-file\n"
                f"  or run /matrix to regenerate all artifacts.\n"
            )
        return 1

    if _is_stale(parent_path, resolved):
        sys.stderr.write(_STALE_WARNING.decode("utf-8") + "\n")

    # Emit assembled bytes to stdout (binary). On Windows, sys.stdout is text
    # mode by default — use the underlying buffer to preserve bytes.
    out = sys.stdout.buffer if hasattr(sys.stdout, "buffer") else sys.stdout
    out.write(assembled)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

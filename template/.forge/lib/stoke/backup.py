"""Spec 431 — pre-cleanup backup snapshot.

Backup target: $TMPDIR/forge-stoke-legacy-cleanup-<ISO8601>-<PID>/

POSIX security contract (Req 6, AC 7):
  - Directory created with mode 0o700.
  - On POSIX, opened with O_NOFOLLOW + O_EXCL semantics so a pre-placed
    symlink under $TMPDIR cannot redirect the backup elsewhere.
  - 30-day retention warning; cleanup-old-backups helper enforces pruning.

Windows compatibility:
  - os.makedirs with restrictive ACLs is not portable; we instead create the
    directory + warn that Windows tmp policies (and the lack of POSIX-style
    mode bits) mean operators relying on durable backups should pass
    --backup-dir <path> to a location they control.

Retention warning (Req 6):
  - $TMPDIR may be pruned by OS policies sooner than 30 days. The helper
    emits this in the cleanup report.
"""
from __future__ import annotations

import errno
import os
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path

BACKUP_PREFIX = "forge-stoke-legacy-cleanup"


def _now_compact() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def create_backup_dir(parent: Path | None = None) -> Path:
    """Create a fresh backup directory with mode 0o700.

    parent: override the default $TMPDIR target. Used by --backup-dir for
    operators who want durable backups outside $TMPDIR's prune policy.
    """
    base = parent if parent is not None else Path(tempfile.gettempdir())
    base.mkdir(parents=True, exist_ok=True)
    name = f"{BACKUP_PREFIX}-{_now_compact()}-{os.getpid()}"
    target = base / name

    if os.name == "nt":
        target.mkdir(mode=0o700, parents=False, exist_ok=False)
        return target

    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW

    try:
        os.mkdir(target, mode=0o700)
    except FileExistsError:
        raise
    try:
        fd = os.open(target, flags)
    except OSError as e:
        if e.errno == errno.ELOOP:
            target.rmdir()
            raise RuntimeError(
                f"Backup target {target} is a symlink — refused (O_NOFOLLOW). "
                f"Remove the symlink or pass --backup-dir."
            ) from e
        raise
    finally:
        try:
            os.close(fd)
        except Exception:
            pass
    return target


def copy_file_into_backup(source: Path, backup_dir: Path, rel_label: str) -> Path:
    """Copy source into backup_dir under rel_label, preserving mode.

    Refuses to copy symlinks (Req 7). Returns the destination path.
    """
    if source.is_symlink():
        raise RuntimeError(
            f"Refusing to back up symlink {source} — symlink deletion is "
            f"refused by policy (Req 7)."
        )
    dest = backup_dir / rel_label
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, dest)
    return dest


def retention_warning(backup_dir: Path) -> str:
    """Return a human-readable retention warning suitable for the cleanup
    report. The 30-day retention is best-effort; $TMPDIR policies may prune
    sooner (Linux systemd-tmpfiles, macOS periodic, Windows Storage Sense)."""
    return (
        f"Backup at {backup_dir}. Default retention is 30 days but $TMPDIR "
        f"OS-level pruning policies may remove it sooner. For durable backups "
        f"pass --backup-dir <path> to a location you control."
    )

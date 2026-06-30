"""Spec 431 — install manifest at ~/.claude/.forge-installed.json.

The manifest is the provenance spine for FORGE installs under ~/.claude/. Every
file FORGE places (via /forge-bootstrap or /forge-stoke) is recorded with a
sha256, source template src_path + commit, originating spec, and timestamp.

Manifest schema (schema_version: 1):

    {
      "schema_version": 1,
      "installs": {
        "<src_path>": {
          "commit": "<git-sha>",
          "installed_at": "<ISO 8601>",
          "files": [
            {
              "rel_path": "commands/forge.md",
              "sha256": "<64-char hex>",
              "spec_id": "431",
              "installed_at": "<ISO 8601>"
            },
            ...
          ],
          "claude_md_sections": [
            {
              "section_id": "<id>",
              "content_sha256": "<64-char hex>",
              "spec_id": "<id>",
              "installed_at": "<ISO 8601>"
            },
            ...
          ]
        },
        ...
      }
    }

Multiple projects under the same operator coexist keyed by src_path (Req 1).

Atomic write contract (Req 1a):
  - Mutations write to a sibling tempfile then os.replace() over the target.
  - Mutation is performed while holding an advisory lock on a sibling lockfile
    (~/.claude/.forge-installed.json.lock).
  - Lock acquisition has a 30s timeout. On timeout: diagnostic + refuse, no
    force.

Manifest-attested CLAUDE.md delimiters (Req 1b, AC 22):
  - claude_md_sections[] records (section_id, content_sha256) for every
    FORGE-injected <!-- FORGE:BEGIN <id> --> / <!-- FORGE:END <id> --> block.
  - Cleanup of CLAUDE.md sections refuses to act on unattested ids.

Schema version refusal (Req 1, AC 20):
  - Readers MUST refuse manifests with schema_version > MAX_SUPPORTED_SCHEMA
    and emit upgrade-required diagnostic. No silent misinterpretation.
"""
from __future__ import annotations

import errno
import hashlib
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MAX_SUPPORTED_SCHEMA = 1
LOCK_TIMEOUT_SECONDS = 30
LOCK_POLL_INTERVAL = 0.1


def manifest_path(home: Path | None = None) -> Path:
    """Return the canonical manifest path under ~/.claude/."""
    base = home if home is not None else Path.home()
    return base / ".claude" / ".forge-installed.json"


def _lock_path(mpath: Path) -> Path:
    return mpath.with_name(mpath.name + ".lock")


def _tempfile_path(mpath: Path) -> Path:
    return mpath.with_name(f"{mpath.name}.tmp.{os.getpid()}")


class ManifestLockTimeout(RuntimeError):
    """Raised when the advisory lock cannot be acquired within the timeout."""


class ManifestSchemaUnsupported(RuntimeError):
    """Raised when a manifest's schema_version exceeds what this reader supports."""


def _acquire_lock(lock_file: Path, timeout: float = LOCK_TIMEOUT_SECONDS) -> Any:
    """Acquire an exclusive advisory lock on lock_file.

    Cross-platform:
      - POSIX: fcntl.flock(LOCK_EX | LOCK_NB) polled with timeout.
      - Windows: msvcrt.locking(LK_NBLCK) polled with timeout.

    Returns the locked file handle (caller MUST keep it open and pass it to
    _release_lock when done).
    """
    lock_file.parent.mkdir(parents=True, exist_ok=True)
    fh = open(lock_file, "a+b")
    deadline = time.monotonic() + timeout

    if os.name == "nt":
        import msvcrt

        while True:
            try:
                msvcrt.locking(fh.fileno(), msvcrt.LK_NBLCK, 1)
                return fh
            except OSError as e:
                if time.monotonic() >= deadline:
                    fh.close()
                    raise ManifestLockTimeout(
                        f"Failed to acquire manifest lock {lock_file} within "
                        f"{timeout}s. Another stoke/bootstrap process may be "
                        f"holding it. Wait or remove the lock file if stale."
                    ) from e
                time.sleep(LOCK_POLL_INTERVAL)
    else:
        import fcntl

        while True:
            try:
                fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                return fh
            except OSError as e:
                if e.errno not in (errno.EAGAIN, errno.EACCES):
                    fh.close()
                    raise
                if time.monotonic() >= deadline:
                    fh.close()
                    raise ManifestLockTimeout(
                        f"Failed to acquire manifest lock {lock_file} within "
                        f"{timeout}s. Another stoke/bootstrap process may be "
                        f"holding it. Wait or remove the lock file if stale."
                    ) from e
                time.sleep(LOCK_POLL_INTERVAL)


def _release_lock(fh: Any) -> None:
    try:
        if os.name == "nt":
            import msvcrt

            try:
                fh.seek(0)
                msvcrt.locking(fh.fileno(), msvcrt.LK_UNLCK, 1)
            except OSError:
                pass
        else:
            import fcntl

            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
    finally:
        fh.close()


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def empty_manifest() -> dict[str, Any]:
    return {"schema_version": MAX_SUPPORTED_SCHEMA, "installs": {}}


def read(mpath: Path | None = None) -> dict[str, Any]:
    """Read manifest; returns empty manifest if file does not exist.

    Raises ManifestSchemaUnsupported when schema_version exceeds support.
    """
    mp = mpath if mpath is not None else manifest_path()
    if not mp.exists():
        return empty_manifest()
    try:
        data = json.loads(mp.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Manifest corrupted at {mp}: {e}") from e
    schema = data.get("schema_version", 0)
    if not isinstance(schema, int) or schema > MAX_SUPPORTED_SCHEMA:
        raise ManifestSchemaUnsupported(
            f"Manifest at {mp} has schema_version={schema}, exceeds supported "
            f"version {MAX_SUPPORTED_SCHEMA}. Upgrade FORGE before consuming "
            f"this manifest."
        )
    if "installs" not in data or not isinstance(data["installs"], dict):
        raise RuntimeError(f"Manifest at {mp} is missing or has invalid 'installs' map")
    return data


def _atomic_write(mpath: Path, data: dict[str, Any]) -> None:
    """Tempfile + os.replace atomic write. Assumes caller holds the lock."""
    mpath.parent.mkdir(parents=True, exist_ok=True)
    tmp = _tempfile_path(mpath)
    serialized = json.dumps(data, indent=2, sort_keys=True) + "\n"
    tmp.write_text(serialized, encoding="utf-8")
    os.replace(tmp, mpath)


def write_install(
    src_path: str,
    commit: str,
    files: list[dict[str, Any]],
    claude_md_sections: list[dict[str, Any]] | None = None,
    spec_id: str | None = None,
    mpath: Path | None = None,
    timeout: float = LOCK_TIMEOUT_SECONDS,
) -> Path:
    """Atomically record (or replace) an install entry for src_path.

    files: list of {"rel_path", "sha256", "spec_id"?} dicts. installed_at and
    spec_id (top-level) are set by this function if absent on per-file entries.

    claude_md_sections: list of {"section_id", "content_sha256", "spec_id"?}
    dicts. Per-section installed_at is set by this function.

    Returns the manifest path on success.
    """
    mp = mpath if mpath is not None else manifest_path()
    lock = _lock_path(mp)
    fh = _acquire_lock(lock, timeout=timeout)
    try:
        existing = read(mp)
        now = _now_iso()
        normalized_files = []
        for entry in files:
            normalized_files.append(
                {
                    "rel_path": entry["rel_path"],
                    "sha256": entry["sha256"],
                    "spec_id": entry.get("spec_id", spec_id) or "",
                    "installed_at": entry.get("installed_at", now),
                }
            )
        normalized_sections = []
        for sec in claude_md_sections or []:
            normalized_sections.append(
                {
                    "section_id": sec["section_id"],
                    "content_sha256": sec["content_sha256"],
                    "spec_id": sec.get("spec_id", spec_id) or "",
                    "installed_at": sec.get("installed_at", now),
                }
            )
        existing["installs"][src_path] = {
            "commit": commit,
            "installed_at": now,
            "files": normalized_files,
            "claude_md_sections": normalized_sections,
        }
        _atomic_write(mp, existing)
        return mp
    finally:
        _release_lock(fh)


def remove_install(src_path: str, mpath: Path | None = None) -> bool:
    """Remove an install entry by src_path. Returns True if removed."""
    mp = mpath if mpath is not None else manifest_path()
    lock = _lock_path(mp)
    fh = _acquire_lock(lock)
    try:
        existing = read(mp)
        if src_path not in existing["installs"]:
            return False
        del existing["installs"][src_path]
        _atomic_write(mp, existing)
        return True
    finally:
        _release_lock(fh)


def is_attested(
    src_path: str,
    section_id: str,
    mpath: Path | None = None,
) -> bool:
    """Return True iff a FORGE:BEGIN/END <section_id> is recorded in the
    manifest for src_path. Used by cleanup to refuse forged-id removal."""
    try:
        data = read(mpath)
    except (ManifestSchemaUnsupported, RuntimeError):
        return False
    install = data["installs"].get(src_path)
    if not install:
        return False
    for sec in install.get("claude_md_sections", []):
        if sec.get("section_id") == section_id:
            return True
    return False


def all_attested_files(mpath: Path | None = None) -> dict[str, list[dict[str, Any]]]:
    """Return {src_path: [file-entry, ...]} for every recorded install."""
    data = read(mpath)
    return {src: install.get("files", []) for src, install in data["installs"].items()}


def report_unsupported_schema(exc: ManifestSchemaUnsupported, stream=sys.stderr) -> None:
    """Print the canonical upgrade-required diagnostic."""
    print(f"ERROR (manifest): {exc}", file=stream)

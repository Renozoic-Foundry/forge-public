#!/usr/bin/env python3
"""Spec 427 — /forge stoke copier-direct apply helper.

Replaces the Spec 381 shadow-tree apply mechanism with direct in-place
`copier update` invocation. Project-data exclusion is centralized at
`copier.yml::_exclude` (single source of truth — DA + MT convergent concern
from /consensus 427 round 1).

Subcommands:
  direct-apply [--live-root DIR] [--allow-dirty] [--no-cleanup-old-backups]
                [--vcs-ref SHA] [--trust]
      Entry point for the new stoke apply mechanism. Orchestrates:
        1. _exclude integrity preflight (AC 17)
        2. Dirty-tree pre-apply guard (Req 4 / AC 1 dirty-tree-refuses)
        3. Old-backup cleanup (Req 7 / AC 11)
        4. Pre-apply backup snapshot with mode 0700 (Req 5,6 / AC 5,6)
        5. `copier update --vcs-ref=$_commit --skip-answered --defaults`
        6. Conflict-marker check + crash-recovery output (Req 8 / AC 15,16)

  audit <backup-dir> [--live-root DIR] [--hard-pct N] [--min-lines N]
      Compare live vs backup snapshot for Tier 3 files (AGENTS.md, CLAUDE.md,
      .mcp.json). Predicate: fires on sections_lost > 0 OR (delta_pct > N AND
      delta_lines >= M) OR path-classification (any file matching _exclude
      fires CONDITIONAL_PASS regardless of delta — Spec 427 Req 9).

  parse-sections <file>
      Print H2 section names. Used by fixtures.

  backup-create [--live-root DIR] [--copier-yml PATH]
      Standalone backup snapshot helper (also invoked by direct-apply).
      Reads `copier.yml::_exclude` at runtime to derive the backup-set
      (programmatic derivation — Req 5). Creates mode 0700 dir, copies
      classified files + .git/ into it, prints backup-dir path on stdout.

  cleanup-old-backups [--max-age-days N]
      Remove backup dirs older than N days (default 30). Best-effort:
      cleanup failure emits warning to stderr and exits 0 (Req 7 / COO).

# CROSS-SPEC CONTRACT — DO NOT EDIT, RENAME, OR DELETE.
# The literal byte-string below is a contract token grepped by Spec 426's
# preflight as the "Spec 427 fix-in-place" signal. The description in the
# token references the original mechanism (.git/** exclusion); the current
# mechanism is copier-direct (Spec 427 revised 2026-05-14), but the token
# MUST remain byte-identical to preserve the cross-spec contract.
# Spec 427: .git/** exclusion enforced
"""
from __future__ import annotations

import argparse
import datetime
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# Spec 401: Python 3.10+ floor.
if sys.version_info < (3, 10):
    sys.stderr.write(f"error: Python 3.10+ required (found {sys.version_info.major}.{sys.version_info.minor})\n")
    sys.exit(1)

TIER3_FILES = ("AGENTS.md", "CLAUDE.md", ".mcp.json")
DEFAULT_HARD_PCT = 30
DEFAULT_MIN_LINES = 15
BACKUP_PREFIX = "forge-stoke-backup-"
DEFAULT_MAX_BACKUP_AGE_DAYS = 30

# Conflict-marker patterns copier-direct may write into files on merge collision.
CONFLICT_MARKERS = ("<<<<<<<", "=======", ">>>>>>>")


# ---- copier.yml::_exclude parsing -------------------------------------------

def _read_copier_exclude(copier_yml: Path) -> list[str]:
    """Parse `copier.yml::_exclude` and return the pattern list.

    AC 17: integrity preflight. Returns [] if _exclude is missing.
    Raises ValueError on malformed YAML or non-list _exclude.

    Minimal YAML parser to avoid adding a PyYAML dependency: scans line-by-line
    for `_exclude:` at column 0 and reads `- "<pattern>"` or `- <pattern>`
    until the next column-0 line. This is sufficient for the well-formed
    copier.yml shape; malformed cases raise so AC 17 fires.
    """
    if not copier_yml.is_file():
        raise FileNotFoundError(f"copier.yml not found at {copier_yml}")
    text = copier_yml.read_text(encoding="utf-8")
    lines = text.splitlines()
    patterns: list[str] = []
    in_exclude = False
    for line in lines:
        if not in_exclude:
            if re.match(r"^_exclude\s*:", line):
                in_exclude = True
                # Allow inline list form: `_exclude: ["a", "b"]`
                rest = line.split(":", 1)[1].strip()
                if rest:
                    if not rest.startswith("["):
                        raise ValueError(
                            f"_exclude must be a list, got non-list scalar: {rest!r}"
                        )
                    inline = rest.rstrip()
                    if not inline.endswith("]"):
                        raise ValueError(f"_exclude inline list missing closing ']': {rest}")
                    inner = inline[1:-1]
                    for item in inner.split(","):
                        item = item.strip().strip('"').strip("'")
                        if item:
                            patterns.append(item)
                    return patterns
            continue
        # In _exclude block: gather `- ...` items; stop at next column-0 key
        if re.match(r"^[A-Za-z_]", line):
            break
        stripped = line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("- "):
            item = stripped[2:].strip().strip('"').strip("'")
            if item:
                patterns.append(item)
        elif stripped == "[]":
            return []
        else:
            raise ValueError(f"malformed _exclude entry: {line!r}")
    return patterns


def _exclude_integrity_preflight(copier_yml: Path) -> list[str]:
    """AC 17: stoke aborts cleanly if `_exclude` is empty/missing/malformed
    BEFORE any apply or backup work. Returns the validated pattern list."""
    try:
        patterns = _read_copier_exclude(copier_yml)
    except (FileNotFoundError, ValueError) as e:
        raise SystemExit(
            f"GATE [_exclude-integrity]: FAIL — {e}\n"
            f"Remediation: ensure {copier_yml} contains a non-empty `_exclude:` list "
            f"of gitignore-style patterns. See docs/process-kit/stoke-recovery-runbook.md."
        )
    if not patterns:
        raise SystemExit(
            "GATE [_exclude-integrity]: FAIL — `_exclude` is empty in copier.yml.\n"
            "Remediation: add project-data patterns to copier.yml::_exclude. "
            "Without these, stoke would overwrite operator-curated content."
        )
    return patterns


# ---- pattern matching -------------------------------------------------------

def _path_matches_patterns(rel_path: str, patterns: list[str]) -> bool:
    """Match a relative path against a list of gitignore-style patterns.

    Supports `**` (recursive), `*` (segment), `?` (single char), and `[...]`
    via fnmatch. Patterns ending in `/` match directories.
    """
    rel = rel_path.replace("\\", "/")
    for pat in patterns:
        p = pat.replace("\\", "/")
        # `**` recursive match
        if "**" in p:
            # Convert `docs/sessions/**` -> regex
            regex = re.escape(p).replace(r"\*\*", ".*").replace(r"\*", "[^/]*").replace(r"\?", ".")
            if re.fullmatch(regex, rel):
                return True
        elif fnmatch.fnmatch(rel, p):
            return True
        # Match basename too for patterns without a slash
        elif "/" not in p and fnmatch.fnmatch(Path(rel).name, p):
            return True
    return False


# ---- dirty-tree guard -------------------------------------------------------

def _check_dirty_tree(live_root: Path) -> tuple[bool, str]:
    """Returns (is_dirty, status_porcelain_output).

    Req 4 / AC 1 (dirty-tree-refuses): hard-abort if modified, staged, or
    untracked files exist in template scope.
    """
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=live_root,
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False, ""
    output = result.stdout.strip()
    return bool(output), output


# ---- backup snapshot --------------------------------------------------------

def _create_backup_dir() -> Path:
    """Create $TMPDIR/forge-stoke-backup-<ISO8601>/ with mode 0700.

    Req 6 / AC 6: POSIX 0700; on Windows, Path.chmod is best-effort but the
    directory inherits umask-restricted parent perms. Windows ACL parity is
    a follow-up axis — current implementation logs a note when running on
    Windows so the operator knows POSIX-strict perms aren't enforced.
    """
    # Use umask to enforce 0077 on creation
    old_umask = os.umask(0o077)
    try:
        ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        tmp = Path(tempfile.gettempdir())
        # Disambiguate concurrent invocations (same-second timestamp + pid suffix)
        backup = tmp / f"{BACKUP_PREFIX}{ts}-{os.getpid()}"
        # Use mkdtemp pattern if the path still collides
        suffix = 0
        while backup.exists():
            suffix += 1
            backup = tmp / f"{BACKUP_PREFIX}{ts}-{os.getpid()}-{suffix}"
        backup.mkdir(parents=True, exist_ok=False, mode=0o700)
        if sys.platform != "win32":
            os.chmod(backup, 0o700)
        else:
            # Windows: emit a one-line note. AC 6 Windows ACL parity is a
            # documented follow-up (test scaffold present; full icacls
            # enforcement deferred to follow-up spec).
            print(
                "NOTE: Windows host — backup directory uses default ACL inheritance. "
                "POSIX-equivalent 0700 not enforced. See docs/process-kit/stoke-recovery-runbook.md "
                "for hardening guidance.",
                file=sys.stderr,
            )
    finally:
        os.umask(old_umask)
    return backup


def _create_backup_snapshot(live_root: Path, copier_yml: Path) -> Path:
    """Create pre-apply backup snapshot.

    Req 5: backup-set derived programmatically from copier.yml::_exclude
    (read at runtime, no parallel list).
    Req 6: created with mode 0700.
    AC 10: includes `.git/` + all files matching _exclude.
    """
    patterns = _exclude_integrity_preflight(copier_yml)
    backup = _create_backup_dir()

    # Copy .git/ verbatim (audit/recovery safety net)
    git_dir = live_root / ".git"
    if git_dir.is_dir():
        shutil.copytree(git_dir, backup / ".git", symlinks=True)

    # Copy files matching _exclude
    copied = 0
    for root, dirs, files in os.walk(live_root):
        # Skip .git (already copied) and the backup dir itself if it lives under live_root
        root_path = Path(root)
        try:
            rel_root = root_path.relative_to(live_root)
        except ValueError:
            continue
        rel_root_str = str(rel_root).replace("\\", "/")
        if rel_root_str == ".git" or rel_root_str.startswith(".git/"):
            dirs[:] = []
            continue
        for fname in files:
            full = root_path / fname
            try:
                rel = full.relative_to(live_root)
            except ValueError:
                continue
            rel_str = str(rel).replace("\\", "/")
            if _path_matches_patterns(rel_str, patterns):
                dst = backup / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(full, dst)
                copied += 1

    # Write the patterns that drove this backup as a manifest (audit trail).
    manifest = backup / ".forge-backup-manifest.json"
    manifest.write_text(
        json.dumps(
            {
                "spec": "427",
                "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "live_root": str(live_root),
                "exclude_patterns": patterns,
                "file_count": copied,
                "git_dir_included": git_dir.is_dir(),
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    return backup


def cmd_backup_create(args: argparse.Namespace) -> int:
    live_root = Path(args.live_root) if args.live_root else Path.cwd()
    copier_yml = Path(args.copier_yml) if args.copier_yml else (live_root / "copier.yml")
    backup = _create_backup_snapshot(live_root, copier_yml)
    print(str(backup))
    return 0


# ---- cleanup-old-backups ----------------------------------------------------

def cmd_cleanup_old_backups(args: argparse.Namespace) -> int:
    """Req 7 / AC 11: remove backup dirs older than --max-age-days.

    Best-effort-with-warning: cleanup failure emits warning, exits 0.
    """
    tmp = Path(tempfile.gettempdir())
    cutoff = time.time() - (args.max_age_days * 86400)
    removed = 0
    warnings = []
    for entry in tmp.glob(f"{BACKUP_PREFIX}*"):
        if not entry.is_dir():
            continue
        try:
            mtime = entry.stat().st_mtime
        except OSError as e:
            warnings.append(f"WARNING: could not stat {entry}: {e}")
            continue
        if mtime < cutoff:
            try:
                shutil.rmtree(entry)
                removed += 1
            except OSError as e:
                warnings.append(f"WARNING: could not prune {entry}: {e}")
    for w in warnings:
        print(w, file=sys.stderr)
    print(json.dumps({"removed": removed, "warnings": len(warnings)}))
    return 0  # Always exit 0 — best-effort per Req 7


# ---- conflict-marker detection ----------------------------------------------

def _scan_for_conflict_markers(live_root: Path, patterns_excluded: list[str]) -> list[Path]:
    """After copier update, scan working tree for conflict markers.

    AC 15: returns list of files containing `<<<<<<<` (or family).
    Excludes paths matching `_exclude` (those weren't touched).
    """
    conflicts = []
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only"],
            cwd=live_root,
            capture_output=True,
            text=True,
            check=False,
        )
        candidates = [line for line in result.stdout.splitlines() if line.strip()]
    except (subprocess.CalledProcessError, FileNotFoundError):
        # Fall back to walking the tree
        candidates = []
        for root, dirs, files in os.walk(live_root):
            root_path = Path(root)
            for fname in files:
                try:
                    rel = (root_path / fname).relative_to(live_root)
                    candidates.append(str(rel).replace("\\", "/"))
                except ValueError:
                    continue

    for rel in candidates:
        if _path_matches_patterns(rel, patterns_excluded):
            continue
        full = live_root / rel
        if not full.is_file():
            continue
        try:
            # Binary-safe quick scan: read first 256KB, check for markers
            with full.open("rb") as fh:
                head = fh.read(256 * 1024)
            text = head.decode("utf-8", errors="replace")
            if any(marker in text for marker in CONFLICT_MARKERS):
                conflicts.append(full)
        except OSError:
            continue
    return conflicts


def _emit_recovery_output(backup_dir: Path, conflicts: list[Path], error_msg: str | None = None) -> None:
    """Req 8 / AC 15,16: operator-actionable recovery output."""
    print("=" * 64, file=sys.stderr)
    print("STOKE FAILURE — copier update did not complete cleanly", file=sys.stderr)
    print("=" * 64, file=sys.stderr)
    if error_msg:
        print(f"Error: {error_msg}", file=sys.stderr)
    print(f"Backup snapshot: {backup_dir}", file=sys.stderr)
    if conflicts:
        print("\nFiles with conflict markers:", file=sys.stderr)
        for path in conflicts:
            print(f"  - {path}", file=sys.stderr)
        print("\nRecovery — per-file:", file=sys.stderr)
        for path in conflicts:
            print(f"  git restore {path}    # discard copier changes, keep your local version", file=sys.stderr)
            print(f"  # OR resolve markers manually, then: git add {path}", file=sys.stderr)
    print("\nRecovery — full rollback:", file=sys.stderr)
    print(f"  git stash --include-untracked", file=sys.stderr)
    print(f"  # Inspect {backup_dir}/.git for pre-apply ref state if needed", file=sys.stderr)
    print(f"\nRunbook: docs/process-kit/stoke-recovery-runbook.md", file=sys.stderr)
    print("=" * 64, file=sys.stderr)


# ---- direct-apply orchestration --------------------------------------------

def _stoke_sentinel_path() -> Path:
    """Sentinel file path for the current stoke-in-progress invocation.

    /consensus 427 round 3 (MT + CISO concern): replaces the inheritable
    FORGE_COPIER_POST_TASK env-var back-channel with a PID-stamped sentinel
    file. The env-var was a true back-channel — any descendant process that
    exported it could disarm the dirty-tree guard. The sentinel approach
    binds the disarm to the specific stoke PID; misconfigured CI or wrapper
    scripts cannot accidentally enable it.
    """
    state_dir = Path(".forge") / "state"
    return state_dir / f"stoke-in-progress-{os.getpid()}"


# Spec 430 — sentinel TTL reduced from 300s (Spec 427) to 60s.
# Smaller window reduces stale-sentinel race surface after crashed-stoke.
SENTINEL_TTL_SECONDS = 60


def _pid_is_alive(pid: int) -> bool:
    """Liveness check. Returns False if the named PID is not a running process.

    Spec 430 AC 5 + AC 7: cross-platform. POSIX uses `os.kill(pid, 0)`; Windows
    uses `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, ...)` via ctypes.
    """
    if pid <= 0:
        return False
    if sys.platform == "win32":
        try:
            import ctypes
            PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
            handle = ctypes.windll.kernel32.OpenProcess(
                PROCESS_QUERY_LIMITED_INFORMATION, False, pid
            )
            if not handle:
                return False
            # Check exit code: STILL_ACTIVE = 259 means running
            exit_code = ctypes.c_ulong()
            ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code))
            ctypes.windll.kernel32.CloseHandle(handle)
            return exit_code.value == 259
        except (OSError, AttributeError, ImportError):
            # Fallback: can't determine — assume not alive (fail-closed)
            return False
    else:
        try:
            os.kill(pid, 0)
            return True
        except (ProcessLookupError, PermissionError):
            return False
        except OSError:
            return False


def _pid_ancestors_linux(start_pid: int, max_depth: int = 16) -> list[int]:
    """Linux-only PID ancestry chain via /proc/<pid>/status PPid lines.

    Spec 430 AC 7: Linux uses /proc/<pid>/status. macOS has no /proc (uses
    libproc/sysctl) — macOS callers MUST NOT use this function; the caller
    routes macOS through the TTL-only fallback in _detect_copier_post_task.

    Returns a list of ancestor PIDs walking upward from start_pid (exclusive)
    until PID 0/1 or depth limit.
    """
    ancestors: list[int] = []
    pid = start_pid
    for _ in range(max_depth):
        status_path = Path(f"/proc/{pid}/status")
        if not status_path.is_file():
            break
        try:
            text = status_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            break
        m = re.search(r"^PPid:\s*(\d+)", text, re.MULTILINE)
        if not m:
            break
        ppid = int(m.group(1))
        if ppid <= 1 or ppid == pid:
            break
        ancestors.append(ppid)
        pid = ppid
    return ancestors


def _stoke_sentinel_path() -> Path:
    """Sentinel file path for the current stoke-in-progress invocation.

    /consensus 427 round 3 (MT + CISO concern): replaces the inheritable
    FORGE_COPIER_POST_TASK env-var back-channel with a PID-stamped sentinel
    file. The env-var was a true back-channel — any descendant process that
    exported it could disarm the dirty-tree guard. The sentinel approach
    binds the disarm to the specific stoke PID; misconfigured CI or wrapper
    scripts cannot accidentally enable it.

    Spec 430 (Linux ancestry): on Linux, _detect_copier_post_task additionally
    verifies the sentinel PID is an ancestor of the current process. On
    Windows + macOS, ancestry is degraded to TTL-only (60s).
    """
    state_dir = Path(".forge") / "state"
    return state_dir / f"stoke-in-progress-{os.getpid()}"


def _detect_copier_post_task() -> bool:
    """Detect when running inside the current stoke invocation's copier task.

    Spec 430 AC 5 + AC 7 hardening of Spec 427 round-3 sentinel:
      - Liveness: sentinel PID MUST be alive (os.kill on POSIX, OpenProcess
        on Windows). A dead PID (stoke crashed) does NOT disarm the guard.
      - Ancestry (Linux only): sentinel PID MUST be an ancestor of the
        current process. A live PID from a concurrent unrelated process
        does NOT disarm the guard.
      - TTL: 60s upper bound (down from Spec 427's 5min). A sentinel older
        than 60s is treated as stale regardless of PID state.

    Windows + macOS degrade to TTL+liveness without ancestry. Future hardening:
    NtQueryInformationProcess (Windows) + libproc/sysctl (macOS) named as
    follow-up triggers if the race becomes operationally material.

    Returns True iff at least one sentinel passes all checks.
    """
    state_dir = Path(".forge") / "state"
    if not state_dir.is_dir():
        return False

    # Compute ancestry chain once on Linux for the ancestor check
    if sys.platform.startswith("linux"):
        my_ancestors = set(_pid_ancestors_linux(os.getpid()))
    else:
        my_ancestors = None  # signal "ancestry-not-available"

    for sentinel in state_dir.glob("stoke-in-progress-*"):
        try:
            pid_str = sentinel.name.removeprefix("stoke-in-progress-")
            sentinel_pid = int(pid_str)
        except ValueError:
            continue

        # TTL check
        try:
            sentinel_age = time.time() - sentinel.stat().st_mtime
        except OSError:
            continue
        if sentinel_age >= SENTINEL_TTL_SECONDS:
            continue  # stale — skip

        # Liveness check
        if not _pid_is_alive(sentinel_pid):
            continue  # crashed stoke; sentinel is forensic, not authoritative

        # Ancestry check (Linux only; Windows/macOS degrade to liveness+TTL)
        if my_ancestors is not None:
            if sentinel_pid not in my_ancestors and sentinel_pid != os.getpid():
                continue  # live PID but not in our ancestor chain — forged

        return True
    return False


def _read_copier_answers(live_root: Path) -> dict | None:
    """Read .copier-answers.yml for _commit (template ref)."""
    answers = live_root / ".copier-answers.yml"
    if not answers.is_file():
        return None
    out: dict = {}
    for line in answers.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+?)\s*$", line)
        if m:
            key, val = m.group(1), m.group(2).strip().strip('"').strip("'")
            out[key] = val
    return out


def cmd_direct_apply(args: argparse.Namespace) -> int:
    """Full orchestration of the new copier-direct apply mechanism.

    Order matters: integrity preflight → dirty-tree guard → cleanup-old →
    backup snapshot → copier update → conflict scan → emit results.
    """
    live_root = Path(args.live_root) if args.live_root else Path.cwd()
    copier_yml = Path(args.copier_yml) if args.copier_yml else (live_root / "copier.yml")

    # Step 1: AC 17 integrity preflight (raises SystemExit on failure)
    patterns = _exclude_integrity_preflight(copier_yml)
    print(f"GATE [_exclude-integrity]: PASS — {len(patterns)} patterns loaded", file=sys.stderr)

    # Step 2: Req 4 / AC 1 dirty-tree guard
    if not args.allow_dirty and not _detect_copier_post_task():
        dirty, status = _check_dirty_tree(live_root)
        if dirty:
            print(
                "GATE [dirty-tree-guard]: FAIL — working tree has uncommitted changes.\n"
                "Commit or stash before stoke. To override at your own risk: --allow-dirty\n"
                f"\n{status}",
                file=sys.stderr,
            )
            return 2
    print("GATE [dirty-tree-guard]: PASS — clean working tree (or override active)", file=sys.stderr)

    # Step 3: Req 7 / AC 11 cleanup old backups (best-effort)
    if not args.no_cleanup_old_backups:
        cleanup_args = argparse.Namespace(max_age_days=DEFAULT_MAX_BACKUP_AGE_DAYS)
        cmd_cleanup_old_backups(cleanup_args)

    # Step 4: pre-apply backup snapshot
    backup = _create_backup_snapshot(live_root, copier_yml)
    print(f"Backup snapshot: {backup}", file=sys.stderr)

    # Step 5: determine VCS ref from .copier-answers.yml unless overridden
    answers = _read_copier_answers(live_root)
    vcs_ref = args.vcs_ref
    if not vcs_ref and answers:
        vcs_ref = answers.get("_commit") or answers.get("_src_path")

    # Step 6: invoke copier update.
    # /consensus 427 round 3 fix (CISO hard finding on AC 7 / Req 1 / Constraint):
    # --trust is OPERATOR-EXPLICIT per invocation. The helper does NOT bake it in
    # by default. The /forge stoke command body MUST prompt the operator and
    # pass --trust to this helper only after explicit consent.
    cmd = ["copier", "update", "--skip-answered", "--defaults"]
    if vcs_ref:
        cmd.extend(["--vcs-ref", vcs_ref])
    if args.trust:
        cmd.append("--trust")
        print("--trust: enabled (operator-explicit per-invocation)", file=sys.stderr)
    else:
        print("--trust: NOT passed (operator did not consent — copier tasks will be refused)", file=sys.stderr)

    print(f"Invoking: {' '.join(cmd)}", file=sys.stderr)
    # /consensus 427 round 3 fix (MT + CISO concern on env-var back-channel):
    # write a PID-stamped sentinel file (NOT an inheritable env-var) so the
    # copier.yml _tasks dirty-tree guard knows to skip ONLY for this specific
    # stoke invocation. Sentinel is cleaned up on exit (success or failure).
    sentinel = live_root / ".forge" / "state" / f"stoke-in-progress-{os.getpid()}"
    sentinel.parent.mkdir(parents=True, exist_ok=True)
    sentinel.write_text(
        f"stoke-pid:{os.getpid()}\nstarted:{datetime.datetime.now(datetime.timezone.utc).isoformat()}\n",
        encoding="utf-8",
    )
    try:
        result = subprocess.run(cmd, cwd=live_root, check=False)
        copier_exit = result.returncode
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        try:
            sentinel.unlink(missing_ok=True)
        except OSError:
            pass
        _emit_recovery_output(backup, [], error_msg=f"copier invocation failed: {e}")
        return 3
    finally:
        try:
            sentinel.unlink(missing_ok=True)
        except OSError:
            pass

    # Step 7: conflict-marker scan + recovery output
    conflicts = _scan_for_conflict_markers(live_root, patterns)
    if copier_exit != 0 or conflicts:
        _emit_recovery_output(
            backup,
            conflicts,
            error_msg=f"copier exited {copier_exit}" if copier_exit != 0 else "conflict markers detected",
        )
        return 4

    # Success
    print(
        json.dumps(
            {
                "status": "ok",
                "backup": str(backup),
                "vcs_ref": vcs_ref,
                "exclude_patterns": len(patterns),
            }
        )
    )
    return 0


# ---- audit (reframed against backup snapshot, with path-classification) ----

_FENCE_RE = re.compile(r"^(?:```|~~~)")
_H2_RE = re.compile(r"^##\s+(.+?)\s*$")


def _parse_h2_sections(text: str) -> list[str]:
    """ATX-only H2 parser. Skips fenced blocks. Treats YAML front-matter as
    a single named pseudo-section."""
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


def _audit_file(
    live_path: Path, backup_path: Path, hard_pct: int, min_lines: int, path_classified: bool
) -> dict | None:
    if not live_path.is_file():
        return None
    if not backup_path.is_file():
        # Backup lacks the file — treat as full deletion (i.e., copier added it).
        # We focus the audit on path-classification + delta heuristics for files
        # present in both. New files don't fire audit on their own.
        return None

    live_text = live_path.read_text(encoding="utf-8", errors="replace")
    backup_text = backup_path.read_text(encoding="utf-8", errors="replace")
    pre_lines = len(backup_text.splitlines())  # pre = backup state
    post_lines = len(live_text.splitlines())   # post = live state after copier
    delta_lines = pre_lines - post_lines  # positive = lines lost
    delta_pct = round((abs(delta_lines) * 100) / max(pre_lines, 1))

    backup_sections = _parse_h2_sections(backup_text)
    live_sections = _parse_h2_sections(live_text)
    sections_lost = [s for s in backup_sections if s not in live_sections]

    fired_section = len(sections_lost) > 0
    fired_backstop = delta_pct > hard_pct and abs(delta_lines) >= min_lines
    # Req 9 / AC 8: path-classification predicate fires CONDITIONAL_PASS
    # regardless of delta. We model this by raising severity to "high" and
    # fired=true whenever the file is in the project-data class AND any
    # change occurred at all.
    any_change = pre_lines != post_lines or backup_text != live_text
    fired_path_class = path_classified and any_change
    fired = fired_section or fired_backstop or fired_path_class

    if fired_path_class:
        severity = "high"
    elif sections_lost or delta_pct > hard_pct:
        severity = "high"
    else:
        severity = "low"

    return {
        "path": str(live_path.name),
        "pre_lines": pre_lines,
        "post_lines": post_lines,
        "delta_lines": delta_lines,
        "delta_pct": delta_pct,
        "sections_lost": sections_lost,
        "fired": fired,
        "fired_reason": "path-classification" if fired_path_class else ("section-loss" if fired_section else "delta-backstop"),
        "severity": severity,
    }


def cmd_audit(args: argparse.Namespace) -> int:
    backup = Path(args.backup_dir)
    live_root = Path(args.live_root) if args.live_root else Path.cwd()

    # Load _exclude patterns to drive path-classification (Req 9)
    copier_yml = live_root / "copier.yml"
    try:
        patterns = _read_copier_exclude(copier_yml)
    except (FileNotFoundError, ValueError):
        patterns = []

    flagged = []
    any_fired = False
    for fname in TIER3_FILES:
        live_path = live_root / fname
        backup_path = backup / fname
        path_classified = _path_matches_patterns(fname, patterns)
        result = _audit_file(live_path, backup_path, args.hard_pct, args.min_lines, path_classified)
        if result is None:
            continue
        flagged.append(result)
        if result["fired"]:
            any_fired = True

    flagged.sort(key=lambda r: (0 if r["severity"] == "high" else 1, -r["delta_pct"]))
    output = {
        "fired": any_fired,
        "flagged": [r for r in flagged if r["fired"]],
        "all_files": flagged,
    }
    print(json.dumps(output, indent=2))
    return 0


def cmd_parse_sections(args: argparse.Namespace) -> int:
    text = Path(args.file_path).read_text(encoding="utf-8", errors="replace")
    for name in _parse_h2_sections(text):
        print(name)
    return 0


# ---- main -------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(prog="stoke.py", description="Spec 427 copier-direct stoke helper")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("direct-apply")
    p.add_argument("--live-root", default=None)
    p.add_argument("--copier-yml", default=None)
    p.add_argument("--allow-dirty", action="store_true", help="Override dirty-tree guard (operator-explicit per Req 4)")
    p.add_argument("--no-cleanup-old-backups", action="store_true")
    p.add_argument("--vcs-ref", default=None, help="Override --vcs-ref (default: read from .copier-answers.yml::_commit)")
    p.add_argument("--trust", action="store_true", help="Pass --trust to copier update. OPERATOR-EXPLICIT per invocation per Req 1 / AC 7 / CISO Constraint — never baked into defaults, never from env, never from config. The /forge stoke command body prompts the operator and passes this flag only after explicit consent.")
    p.set_defaults(func=cmd_direct_apply)

    p = sub.add_parser("backup-create")
    p.add_argument("--live-root", default=None)
    p.add_argument("--copier-yml", default=None)
    p.set_defaults(func=cmd_backup_create)

    p = sub.add_parser("cleanup-old-backups")
    p.add_argument("--max-age-days", type=int, default=DEFAULT_MAX_BACKUP_AGE_DAYS)
    p.set_defaults(func=cmd_cleanup_old_backups)

    p = sub.add_parser("audit")
    p.add_argument("backup_dir")
    p.add_argument("--live-root", default=None)
    p.add_argument("--hard-pct", type=int, default=DEFAULT_HARD_PCT)
    p.add_argument("--min-lines", type=int, default=DEFAULT_MIN_LINES)
    p.set_defaults(func=cmd_audit)

    p = sub.add_parser("parse-sections")
    p.add_argument("file_path")
    p.set_defaults(func=cmd_parse_sections)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

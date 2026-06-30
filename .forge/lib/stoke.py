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

# Spec 432: scoped-staging catalog location (relative to script's package).
# Resolved at runtime via _project_type_exclusions_path() to allow testing
# with synthetic catalogs.
PROJECT_TYPE_EXCLUSIONS_FILENAME = "project-type-exclusions.yaml"

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


def _read_copier_tasks(copier_yml: Path) -> list[str]:
    """Parse `copier.yml::_tasks` and return one human-readable name per task.

    Spec 428: powers the `list-tasks` subcommand. Each `_tasks` entry is either a
    dict with a `command:` list (modern copier 9.x form) or a bare command
    string. The "name" emitted is a single-line summary the operator can read in
    the --trust consent prompt — typically the first concrete arg after the
    interpreter, or a sh-c excerpt for inline shell tasks.

    Minimal YAML parser to avoid a PyYAML dependency. Sufficient for the
    well-formed copier.yml shape FORGE ships; malformed input raises ValueError.
    Returns [] when `_tasks:` is absent or explicitly empty.
    """
    if not copier_yml.is_file():
        raise FileNotFoundError(f"copier.yml not found at {copier_yml}")
    text = copier_yml.read_text(encoding="utf-8")
    lines = text.splitlines()
    names: list[str] = []
    in_tasks = False
    current: list[str] = []

    _JINJA_RE = re.compile(r"\{\{[^}]*\}\}|\{%[^%]*%\}")

    def _strip_jinja(tok: str) -> str:
        # Remove all jinja interpolations and template tags, then collapse ws.
        return re.sub(r"\s+", " ", _JINJA_RE.sub("", tok)).strip()

    def _flush(current: list[str]) -> None:
        if not current:
            return
        # Strip jinja noise from each token; drop tokens that become empty or
        # are pure YAML literal-block markers / shell-wrapper noise.
        cleaned = []
        for c in current:
            s = _strip_jinja(c)
            if not s or s in ("|-", "|", "sh", "-c"):
                continue
            cleaned.append(s)
        # Prefer a token that looks like a script path.
        path_like = [c for c in cleaned if (c.endswith(".py") or c.endswith(".sh") or "/" in c)]
        if path_like:
            label = path_like[0]
        elif cleaned:
            label = cleaned[0]
        else:
            label = "inline shell task"
        if "\n" in label or len(label) > 80:
            label = label.replace("\n", " ")[:80].rstrip() + "…"
        names.append(label)

    for line in lines:
        if not in_tasks:
            if re.match(r"^_tasks\s*:", line):
                in_tasks = True
                rest = line.split(":", 1)[1].strip()
                if rest == "[]":
                    return []
                if rest:
                    raise ValueError(f"_tasks must be a list, got non-list scalar: {rest!r}")
            continue
        # In _tasks block: stop at next column-0 key.
        if re.match(r"^[A-Za-z_]", line):
            _flush(current)
            current = []
            break
        stripped = line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        # New task entry begins with `- ` (top-level list marker, 2-space indent).
        if re.match(r"^  - ", line):
            _flush(current)
            current = []
            tail = line[4:].strip()
            # Dict form `- command:` — skip the marker, collect from command: items.
            if tail.startswith("command:"):
                continue
            if tail.startswith('"') or tail.startswith("'"):
                current.append(tail.strip('"').strip("'"))
            elif tail:
                current.append(tail)
        elif re.match(r"^      - ", line):
            # Nested `command:` list items at 6-space indent.
            item = line[8:].strip().strip('"').strip("'")
            if item:
                current.append(item)
    _flush(current)
    return names


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


def _detect_fresh_clone_consent_state(live_root: Path, answers: dict | None) -> list[str] | None:
    """Spec 434 Req 4 — fresh-clone-detection warning preconditions.

    Returns a list of non-default security-gated keys if ALL of:
      (a) accept_security_overrides is true in .copier-answers.yml,
      (b) .copier-answers.yml is unchanged from prior commit OR brand-new (no git history),
      (c) at least one security-gated key has a non-default value.
    Returns None if any precondition fails (no warning needed).

    Threat model: a malicious / pre-positioned .copier-answers.yml with the flag set
    plus a crafted test_command/lint_command would be honored silently. The warning
    forces explicit operator confirmation when the answers file shows no sign of
    in-tree operator authorship (no working-tree edit; no prior commit).
    """
    if not answers:
        return None
    flag_val = answers.get("accept_security_overrides", "false").strip().lower()
    if flag_val not in ("true", "yes", "1"):
        return None  # (a) flag not set → nothing to warn about

    answers_path = live_root / ".copier-answers.yml"
    if not answers_path.is_file():
        return None

    # (b) is the answers file (i) brand-new (untracked or no git history at all)
    #     OR (ii) committed-and-unchanged (no working-tree edit since prior commit)?
    #     Either condition means the operator hasn't actively touched this file in
    #     this working session — the consent value came from elsewhere.
    git_dir = live_root / ".git"
    fresh_clone = False
    if not git_dir.exists():
        fresh_clone = True  # no git history at all
    else:
        try:
            tracked = subprocess.run(
                ["git", "ls-files", "--error-unmatch", ".copier-answers.yml"],
                cwd=str(live_root), capture_output=True, text=True, check=False,
            )
            if tracked.returncode != 0:
                fresh_clone = True  # untracked → operator hasn't committed it
            else:
                # `git status --porcelain` returns non-empty when the file has working-tree
                # changes; empty when committed-and-unchanged. Empty == fresh-clone state.
                status = subprocess.run(
                    ["git", "status", "--porcelain", "--", ".copier-answers.yml"],
                    cwd=str(live_root), capture_output=True, text=True, check=False,
                )
                if status.returncode == 0 and status.stdout.strip() == "":
                    # committed-and-unchanged: consent value came from the prior commit,
                    # not from an in-session operator edit.
                    fresh_clone = True
        except (FileNotFoundError, OSError):
            fresh_clone = True

    if not fresh_clone:
        return None  # (b) operator has actively edited the file → assume conscious consent

    # (c) any security-gated key has a non-default value?
    DEFAULTS = {
        "test_command": "pytest -q",
        "lint_command": "ruff check .",
        "harness_command": "",
        "include_nanoclaw": "false",
        "include_advanced_autonomy": "false",
        "include_two_stage_review": "false",
    }
    non_default = []
    for key, default in DEFAULTS.items():
        if key in answers and answers[key].strip() != default:
            non_default.append(key)
    if not non_default:
        return None  # (c) flag set but no actual override → nothing to warn about

    return non_default


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

    # Step 5b: Spec 434 Req 4 — fresh-clone-detection warning for security overrides.
    # Partial mitigation of the bootstrap-path consent gap (CISO round-1 finding).
    # See docs/process-kit/copier-gotchas.md § Bootstrap-path consent surface.
    consent_warn_keys = _detect_fresh_clone_consent_state(live_root, answers)
    if consent_warn_keys is not None:
        print(
            "GATE [security-override-consent]: WARN — .copier-answers.yml has "
            f"accept_security_overrides: true plus non-default values for "
            f"{', '.join(consent_warn_keys)}, and the answers file shows no in-session "
            "operator edit. Bootstrap-path consent gap (Spec 434 follow-up) — confirm "
            "you intend to honor these overrides. Pass --confirm-security-overrides to "
            "proceed; otherwise stoke aborts cleanly.",
            file=sys.stderr,
        )
        if not getattr(args, "confirm_security_overrides", False):
            print("GATE [security-override-consent]: ABORT — operator confirmation required", file=sys.stderr)
            return 2
        print("GATE [security-override-consent]: PASS — operator confirmed (--confirm-security-overrides)", file=sys.stderr)

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

    # Spec 444: --data K=V pass-through for chat-mediated security-override
    # consent. The /forge stoke command body's preflight-gates flow constructs
    # K=V strings from FORGE-controlled gate definitions
    # (stoke.gates.detect_gates) only after explicit operator yes-answers.
    # NEVER set --data from env vars, config files, or non-operator sources
    # (Spec 444 Constraint: "NEVER construct --data flags from any source
    # other than operator yes/no answers in the current chat turn").
    for kv in (args.data or []):
        if "=" not in kv:
            print(f"ERROR: --data argument must be KEY=VALUE (got: {kv!r})", file=sys.stderr)
            return 2
        cmd.extend(["--data", kv])

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


# ---- Spec 432: scoped-staging + project-type exclusions ---------------------

def _project_type_exclusions_path(override: Path | None = None) -> Path:
    """Resolve the path to project-type-exclusions.yaml.

    Default: alongside stoke.py at ../data/project-type-exclusions.yaml.
    Override path is honored for tests and operator extensions.
    """
    if override is not None:
        return override
    return Path(__file__).resolve().parent.parent / "data" / PROJECT_TYPE_EXCLUSIONS_FILENAME


def _parse_yaml_catalog(text: str) -> dict:
    """Minimal YAML parser for project-type-exclusions.yaml.

    Supports the schema documented in the catalog file:
      project_types:
        <name>:
          manifest_files: [<file>, ...]
          exclude_paths:  [<glob>, ...]

    Avoids PyYAML dependency (same pattern as _read_copier_exclude). Indented
    list items under each key are collected; comments and blank lines are
    ignored. Quoted strings are stripped of quotes.
    """
    result: dict = {"project_types": {}}
    lines = text.splitlines()
    current_type: str | None = None
    current_field: str | None = None
    in_project_types = False

    for raw in lines:
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        # Detect top-level `project_types:`
        if not line.startswith(" ") and not line.startswith("\t"):
            if stripped.startswith("project_types"):
                in_project_types = True
                current_type = None
                current_field = None
                continue
            else:
                in_project_types = False
                continue
        if not in_project_types:
            continue
        indent = len(line) - len(line.lstrip(" "))
        # 2-space indent: project type name (`maven:`)
        if indent == 2 and stripped.endswith(":"):
            current_type = stripped[:-1].strip()
            result["project_types"][current_type] = {"manifest_files": [], "exclude_paths": []}
            current_field = None
            continue
        # 4-space indent: field name (`manifest_files:` / `exclude_paths:`)
        if indent == 4 and stripped.endswith(":") and current_type:
            current_field = stripped[:-1].strip()
            continue
        # 6-space indent: list item (`- pom.xml`)
        if indent == 6 and stripped.startswith("- ") and current_type and current_field:
            item = stripped[2:].strip().strip('"').strip("'")
            if current_field in ("manifest_files", "exclude_paths"):
                result["project_types"][current_type][current_field].append(item)
            continue
    return result


def _load_exclusion_catalog(catalog_path: Path | None = None) -> dict:
    """Load and parse the project-type-exclusions.yaml catalog.

    Returns the parsed dict (with `project_types` key). Raises FileNotFoundError
    if the catalog is missing and ValueError if it cannot be parsed.
    """
    path = _project_type_exclusions_path(catalog_path)
    if not path.is_file():
        raise FileNotFoundError(f"project-type-exclusions catalog not found at {path}")
    text = path.read_text(encoding="utf-8")
    try:
        return _parse_yaml_catalog(text)
    except Exception as e:
        raise ValueError(f"malformed catalog {path}: {e}")


def _detect_project_types(live_root: Path, catalog: dict) -> list[str]:
    """Manifest-file-presence detection (Req 2).

    Returns the list of active project type names. Manifest matching supports
    fnmatch globs (e.g. `*.csproj`) at the project root only — manifest
    presence in subdirectories does NOT activate (root-only trigger).
    Multiple project types MAY be active simultaneously (Req 3).
    """
    active: list[str] = []
    try:
        root_entries = [p.name for p in live_root.iterdir() if p.is_file()]
    except OSError:
        return []
    for type_name, type_def in catalog.get("project_types", {}).items():
        for manifest in type_def.get("manifest_files", []):
            if "*" in manifest or "?" in manifest or "[" in manifest:
                if any(fnmatch.fnmatch(name, manifest) for name in root_entries):
                    active.append(type_name)
                    break
            else:
                if manifest in root_entries:
                    active.append(type_name)
                    break
    return active


def _active_exclusion_patterns(
    catalog: dict,
    active_types: list[str],
    operator_extra: list[str] | None = None,
) -> list[str]:
    """Aggregate exclude_paths from active project types + operator extras (Req 8).

    Operator-curated additions in `.copier-answers.yml::project_type_exclusions_extra`
    EXTEND (not replace) the template catalog.
    """
    patterns: list[str] = []
    for type_name in active_types:
        type_def = catalog.get("project_types", {}).get(type_name, {})
        for pat in type_def.get("exclude_paths", []):
            if pat and pat not in patterns:
                patterns.append(pat)
    if operator_extra:
        for pat in operator_extra:
            if pat and pat not in patterns:
                patterns.append(pat)
    return patterns


def _read_operator_extra_exclusions(live_root: Path) -> list[str]:
    """Read `.copier-answers.yml::project_type_exclusions_extra` (Req 8 / AC 6).

    Returns an empty list if the answers file or key is absent. Malformed
    values yield an empty list — operator typo should not block stoke.
    """
    answers = live_root / ".copier-answers.yml"
    if not answers.is_file():
        return []
    text = answers.read_text(encoding="utf-8")
    extras: list[str] = []
    in_block = False
    for raw in text.splitlines():
        line = raw.rstrip()
        if not in_block:
            m = re.match(r"^project_type_exclusions_extra\s*:\s*(.*)$", line)
            if m:
                rest = m.group(1).strip()
                if rest.startswith("[") and rest.endswith("]"):
                    inner = rest[1:-1]
                    for item in inner.split(","):
                        item = item.strip().strip('"').strip("'")
                        if item:
                            extras.append(item)
                    return extras
                if rest and rest != "":
                    return []  # Non-list scalar: ignore
                in_block = True
            continue
        # In block: gather `- ...` items; stop at next column-0 key
        if re.match(r"^[A-Za-z_]", line):
            break
        stripped = line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("- "):
            item = stripped[2:].strip().strip('"').strip("'")
            if item:
                extras.append(item)
    return extras


def _list_tracked_files(live_root: Path) -> list[str]:
    """Return paths tracked by git (relative, forward-slash). Empty on git error."""
    try:
        result = subprocess.run(
            ["git", "ls-files"],
            cwd=live_root,
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    return [line.replace("\\", "/") for line in result.stdout.splitlines() if line.strip()]


def _filter_safe_paths(
    candidate_paths: list[str],
    exclusion_patterns: list[str],
) -> tuple[list[str], list[str]]:
    """Split candidates into (safe, blocked).

    `safe` are paths to stage. `blocked` are paths that matched an exclusion
    pattern — they MUST NOT be staged even with --allow-dirty (Req 5).
    """
    safe: list[str] = []
    blocked: list[str] = []
    for rel in candidate_paths:
        norm = rel.replace("\\", "/")
        if _path_matches_patterns(norm, exclusion_patterns):
            blocked.append(norm)
        else:
            safe.append(norm)
    return safe, blocked


def _audit_commit_for_exclusions(
    live_root: Path,
    exclusion_patterns: list[str],
    commit_ref: str = "HEAD",
) -> list[str]:
    """Post-commit audit (Req 6 / AC 7): list committed files matching exclusions.

    Returns the list of offending paths in the named commit. Empty list = clean.
    Caller is expected to abort with non-zero exit if non-empty.
    """
    try:
        result = subprocess.run(
            ["git", "show", "--name-only", "--pretty=format:", commit_ref],
            cwd=live_root,
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    files = [line.replace("\\", "/") for line in result.stdout.splitlines() if line.strip()]
    offenders = [f for f in files if _path_matches_patterns(f, exclusion_patterns)]
    return offenders


def _explicit_stage_paths(live_root: Path, paths: list[str]) -> tuple[int, list[str]]:
    """Stage each path explicitly via `git add -- <path>`.

    Returns (count_added, errors). Never uses `git add -A` or `git add .`
    (Constraint). Each path is passed verbatim through `--` to defeat
    shell-globbing hazards (Constraint, Windows-PowerShell safety).
    """
    added = 0
    errors: list[str] = []
    for rel in paths:
        try:
            subprocess.run(
                ["git", "add", "--", rel],
                cwd=live_root,
                capture_output=True,
                text=True,
                check=True,
            )
            added += 1
        except subprocess.CalledProcessError as e:
            errors.append(f"{rel}: {e.stderr.strip() or e}")
        except FileNotFoundError as e:
            errors.append(f"{rel}: {e}")
    return added, errors


def cmd_safe_stage(args: argparse.Namespace) -> int:
    """Spec 432 entry point: scoped staging + exclusion audit.

    Stages paths from EITHER --paths (explicit operator-supplied list) OR
    the project's tracked-files-plus-restored set, filtered through the
    active project-type exclusion catalog. Never uses `git add -A`.

    On success, prints a JSON status block. On exclusion-violation (either
    pre-stage or post-commit audit), exits non-zero with recovery commands.
    """
    live_root = Path(args.live_root) if args.live_root else Path.cwd()
    catalog_path = Path(args.catalog) if args.catalog else None

    # Load catalog. Hard refusal on missing/malformed (Req 1).
    try:
        catalog = _load_exclusion_catalog(catalog_path)
    except (FileNotFoundError, ValueError) as e:
        print(
            f"GATE [exclusion-catalog]: FAIL — {e}\n"
            "Remediation: restore template/.forge/data/project-type-exclusions.yaml "
            "from the FORGE template, or pass --catalog <path>.",
            file=sys.stderr,
        )
        return 5

    active = _detect_project_types(live_root, catalog)
    extras = _read_operator_extra_exclusions(live_root)
    patterns = _active_exclusion_patterns(catalog, active, operator_extra=extras)

    print(
        f"Project types detected: {', '.join(active) if active else '(none)'}",
        file=sys.stderr,
    )
    if extras:
        print(f"Operator extras: {len(extras)} pattern(s)", file=sys.stderr)

    # Build candidate list:
    #   --paths <a> <b> ... → that exact list
    #   else                → tracked + operator-supplied restored set (--restored)
    if args.paths:
        candidates = [p.replace("\\", "/") for p in args.paths]
    else:
        tracked = _list_tracked_files(live_root)
        restored = [p.replace("\\", "/") for p in (args.restored or [])]
        # De-dup while preserving order.
        seen: set[str] = set()
        candidates = []
        for p in tracked + restored:
            if p not in seen:
                seen.add(p)
                candidates.append(p)

    safe, blocked = _filter_safe_paths(candidates, patterns)

    if blocked:
        print(
            f"GATE [scoped-staging]: REFUSED — {len(blocked)} path(s) matched the "
            f"project-type exclusion catalog and will NOT be staged.",
            file=sys.stderr,
        )
        for b in blocked[:20]:
            print(f"  - {b}", file=sys.stderr)
        if len(blocked) > 20:
            print(f"  ... and {len(blocked) - 20} more", file=sys.stderr)
        # Req 5: --allow-dirty does NOT relax the catalog. The blocked set is
        # always dropped; we proceed to stage `safe` only if any remain.

    if not safe:
        print(
            "GATE [scoped-staging]: ABORT — no safe paths to stage after exclusion filter.",
            file=sys.stderr,
        )
        return 6

    if args.dry_run:
        print(
            json.dumps(
                {
                    "status": "dry-run",
                    "active_project_types": active,
                    "patterns_in_effect": patterns,
                    "candidate_count": len(candidates),
                    "safe_count": len(safe),
                    "blocked_count": len(blocked),
                    "safe_sample": safe[:10],
                    "blocked_sample": blocked[:10],
                },
                indent=2,
            )
        )
        return 0

    added, errors = _explicit_stage_paths(live_root, safe)
    if errors:
        print("Staging errors:", file=sys.stderr)
        for err in errors[:10]:
            print(f"  - {err}", file=sys.stderr)

    # Commit if a message was provided.
    if args.commit_message:
        try:
            subprocess.run(
                ["git", "commit", "-m", args.commit_message],
                cwd=live_root,
                capture_output=True,
                text=True,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            print(
                f"GATE [scoped-staging]: FAIL — git commit failed: "
                f"{e.stderr.strip() or e}",
                file=sys.stderr,
            )
            return 7

        # Post-commit audit (Req 6 / AC 7).
        offenders = _audit_commit_for_exclusions(live_root, patterns)
        if offenders:
            print(
                f"GATE [post-commit-audit]: FAIL — {len(offenders)} exclusion-listed "
                f"path(s) landed in the commit. This is a defect — please report.",
                file=sys.stderr,
            )
            for o in offenders[:20]:
                print(f"  - {o}", file=sys.stderr)
            print(
                "\nRecovery:\n"
                "  git reset --soft HEAD~1   # undo the commit, keep staged\n"
                f"  git restore --staged {' '.join(offenders[:5])}{' ...' if len(offenders) > 5 else ''}\n"
                "  # then re-run safe-stage",
                file=sys.stderr,
            )
            return 8

    print(
        json.dumps(
            {
                "status": "ok",
                "active_project_types": active,
                "patterns_in_effect": len(patterns),
                "staged": added,
                "blocked": len(blocked),
                "committed": bool(args.commit_message),
            },
            indent=2,
        )
    )
    return 0


def cmd_audit_commit(args: argparse.Namespace) -> int:
    """Standalone post-commit audit (Req 6 / AC 7). Useful for retroactive checks."""
    live_root = Path(args.live_root) if args.live_root else Path.cwd()
    catalog_path = Path(args.catalog) if args.catalog else None
    try:
        catalog = _load_exclusion_catalog(catalog_path)
    except (FileNotFoundError, ValueError) as e:
        print(f"GATE [exclusion-catalog]: FAIL — {e}", file=sys.stderr)
        return 5
    active = _detect_project_types(live_root, catalog)
    extras = _read_operator_extra_exclusions(live_root)
    patterns = _active_exclusion_patterns(catalog, active, operator_extra=extras)
    offenders = _audit_commit_for_exclusions(live_root, patterns, commit_ref=args.commit_ref)
    print(
        json.dumps(
            {
                "commit": args.commit_ref,
                "active_project_types": active,
                "offenders": offenders,
                "clean": len(offenders) == 0,
            },
            indent=2,
        )
    )
    return 0 if not offenders else 8


# ---- Spec 433: consumer .gitignore audit -----------------------------------

# Each project type's exclude_paths from project-type-exclusions.yaml are
# normalized into operator-friendly gitignore rules (e.g., `target/**` → `target/`).
# The audit checks the consumer's project-root .gitignore for substring presence
# of these normalized rules, stripping comment and negation lines first to
# avoid false-positives (DA W-1, 2026-05-15).


def _normalize_to_gitignore_rule(pattern: str) -> str:
    """Collapse a catalog pattern to its operator-friendly .gitignore form.

    Rules:
      - `target/**`     → `target/`
      - `**/target/**`  → `target/`
      - `target/`       → `target/`
      - `*.pyc`         → `*.pyc`
      - `**/*.egg-info/**` → `*.egg-info/`
    """
    p = pattern.replace("\\", "/").strip()
    # Strip a leading `**/` (e.g., `**/__pycache__/**` → `__pycache__/**`).
    if p.startswith("**/"):
        p = p[3:]
    # Strip a trailing `/**` (e.g., `target/**` → `target/`).
    if p.endswith("/**"):
        p = p[:-3] + "/"
    # Strip a bare trailing `**` (e.g., `target**` → `target`).
    elif p.endswith("**"):
        p = p[:-2]
    return p


def _required_gitignore_rules_for_types(
    catalog: dict, active_types: list[str]
) -> dict[str, list[str]]:
    """Map project-type → unique list of normalized gitignore rules to require."""
    out: dict[str, list[str]] = {}
    for type_name in active_types:
        type_def = catalog.get("project_types", {}).get(type_name, {})
        seen: set[str] = set()
        rules: list[str] = []
        for pat in type_def.get("exclude_paths", []):
            rule = _normalize_to_gitignore_rule(pat)
            if rule and rule not in seen:
                seen.add(rule)
                rules.append(rule)
        out[type_name] = rules
    return out


def _read_gitignore_lines(gitignore: Path) -> tuple[list[str], str]:
    """Read .gitignore in binary, detect line terminator (CRLF/LF), return
    (decoded_lines_without_terminator, terminator_string).

    DA W-3 (2026-05-15): preserve the file's existing line ending. If the file
    is mixed, the dominant terminator wins. If the file is empty, default to
    the OS-native terminator.
    """
    if not gitignore.is_file():
        return [], os.linesep
    raw = gitignore.read_bytes()
    if not raw:
        return [], os.linesep
    crlf_count = raw.count(b"\r\n")
    # LF outside CRLF pairs:
    lf_count = raw.count(b"\n") - crlf_count
    terminator = "\r\n" if crlf_count > lf_count else "\n"
    text = raw.decode("utf-8", errors="replace")
    # Split on either CRLF or LF; preserve as decoded list without terminators.
    lines = re.split(r"\r\n|\n", text)
    # If the file ended with a terminator, split produces a trailing empty string;
    # drop it so we don't insert a phantom empty line on rejoin.
    if lines and lines[-1] == "":
        lines.pop()
    return lines, terminator


def _gitignore_active_rules(lines: list[str]) -> list[str]:
    """Strip comment lines (#-prefixed) and negation lines (!-prefixed) from
    the .gitignore. The remainder is the set of lines that actually ignore
    something.

    DA W-1 (2026-05-15): comment + negation stripping eliminates the
    false-positive class.
    """
    active: list[str] = []
    for line in lines:
        s = line.strip()
        if not s:
            continue
        if s.startswith("#"):
            continue
        if s.startswith("!"):
            continue
        active.append(s)
    return active


def _gitignore_satisfies_rule(active_lines: list[str], rule: str) -> bool:
    """Substring + trailing-slash equivalence (Req: scope §"Match semantics").

    `target/`, `target`, `**/target/`, `/target/` all satisfy a `target/` rule.
    """
    needle = rule.rstrip("/")
    if not needle:
        return False
    needle_slash = needle + "/"
    for active in active_lines:
        if needle in active or needle_slash in active:
            return True
    return False


def _audit_gitignore(
    live_root: Path,
    catalog: dict,
    active_types: list[str],
) -> dict:
    """Per-type audit of .gitignore against required rules.

    Returns:
        {
          "gitignore_exists": bool,
          "by_type": {"maven": {"required": [...], "missing": [...]}, ...},
          "any_missing": bool,
          "any_present_type_with_missing_rules": bool,
        }
    """
    gitignore = live_root / ".gitignore"
    required_by_type = _required_gitignore_rules_for_types(catalog, active_types)
    exists = gitignore.is_file()
    if exists:
        lines, _terminator = _read_gitignore_lines(gitignore)
        active_lines = _gitignore_active_rules(lines)
    else:
        active_lines = []

    by_type: dict[str, dict] = {}
    any_missing = False
    for type_name, required in required_by_type.items():
        missing = [r for r in required if not _gitignore_satisfies_rule(active_lines, r)]
        by_type[type_name] = {"required": required, "missing": missing}
        if missing:
            any_missing = True

    return {
        "gitignore_exists": exists,
        "by_type": by_type,
        "any_missing": any_missing,
    }


def _format_gitignore_diff(audit: dict, today: str) -> str:
    """Build a copy-pasteable diff block showing the lines that would be appended."""
    parts: list[str] = []
    parts.append(f"# Added by /forge stoke {today}")
    for type_name, type_audit in audit["by_type"].items():
        if type_audit["missing"]:
            parts.append(f"# {type_name}")
            parts.extend(type_audit["missing"])
    return "\n".join(parts)


def _append_to_gitignore(live_root: Path, audit: dict, today: str) -> dict:
    """Append missing rules to consumer's .gitignore (or create it).

    Preserves line-ending (DA W-3). Returns a status dict.
    """
    gitignore = live_root / ".gitignore"
    exists = gitignore.is_file()
    lines, terminator = _read_gitignore_lines(gitignore)
    # Ensure existing content ends cleanly before appending new block.
    new_lines = list(lines)  # copy to preserve byte-equality on unchanged content
    if new_lines and new_lines[-1].strip() != "":
        # File ends with content but no blank-line separator; we'll add one.
        new_lines.append("")
    # Compose appended block.
    append_block = [f"# Added by /forge stoke {today}"]
    for type_name, type_audit in audit["by_type"].items():
        if type_audit["missing"]:
            append_block.append(f"# {type_name}")
            append_block.extend(type_audit["missing"])
    new_lines.extend(append_block)
    # Reserialize using the original terminator.
    output = terminator.join(new_lines) + terminator
    gitignore.write_bytes(output.encode("utf-8"))
    return {
        "gitignore_path": str(gitignore),
        "created": not exists,
        "appended_lines": len(append_block),
        "terminator": "CRLF" if terminator == "\r\n" else "LF",
    }


def cmd_list_tasks(args: argparse.Namespace) -> int:
    """Spec 428 — emit one human-readable name per `_tasks` entry in copier.yml.

    Resolution order for source: --src-path arg; else .copier-answers.yml::_src_path
    in the live root. Empty output + exit 0 when no `_tasks` declared. Non-zero
    exit only on YAML parse failure or unreachable source.

    The Step 0pre.1 consent prompt in /forge stoke calls this to dynamically
    enumerate the tasks that will run if the operator passes --trust. Replaces
    the pre-Spec-428 hardcoded example list.
    """
    src_path = args.src_path
    if not src_path:
        live_root = Path(args.live_root) if args.live_root else Path.cwd()
        answers = _read_copier_answers(live_root)
        if answers:
            src_path = answers.get("_src_path")
    if not src_path:
        print("ERROR: no _src_path resolved; pass --src-path or run in a project with .copier-answers.yml", file=sys.stderr)
        return 2
    copier_yml = Path(src_path) / "copier.yml"
    if not copier_yml.is_file():
        print(f"ERROR: copier.yml not found at {copier_yml}", file=sys.stderr)
        return 2
    try:
        names = _read_copier_tasks(copier_yml)
    except ValueError as e:
        print(f"ERROR: copier.yml parse failure: {e}", file=sys.stderr)
        return 3
    for name in names:
        print(name)
    return 0


def cmd_audit_gitignore(args: argparse.Namespace) -> int:
    """Spec 433 entry point: audit consumer .gitignore against active project types.

    Behavior:
      - Detects active project types via Spec 432 catalog.
      - Reports per-type rule coverage.
      - If --apply is set and missing rules exist, appends them (operator's
        consent must be obtained by the calling command body, NOT by this
        helper — keep helper non-interactive for scripting).
      - --no-gitignore-audit: short-circuit; print 'skipped'.
    """
    if args.no_gitignore_audit:
        print(json.dumps({"status": "skipped", "reason": "--no-gitignore-audit"}))
        return 0

    live_root = Path(args.live_root) if args.live_root else Path.cwd()
    catalog_path = Path(args.catalog) if args.catalog else None
    try:
        catalog = _load_exclusion_catalog(catalog_path)
    except (FileNotFoundError, ValueError) as e:
        # Req 5 / Constraint: non-blocking on helper errors.
        print(
            f"WARN: gitignore audit skipped — catalog unavailable: {e}",
            file=sys.stderr,
        )
        print(json.dumps({"status": "skipped", "reason": f"catalog: {e}"}))
        return 0

    active = _detect_project_types(live_root, catalog)
    if not active:
        print(
            json.dumps(
                {"status": "ok", "reason": "no project types detected", "by_type": {}}
            )
        )
        return 0

    audit = _audit_gitignore(live_root, catalog, active)
    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")

    # Terse report (Req 7): one line per type, plus combined diff if missing.
    if not audit["any_missing"]:
        for type_name in active:
            print(f"{type_name.capitalize()}: OK", file=sys.stderr)
        print(
            json.dumps(
                {
                    "status": "ok",
                    "gitignore_exists": audit["gitignore_exists"],
                    "active_project_types": active,
                    "any_missing": False,
                }
            )
        )
        return 0

    for type_name, type_audit in audit["by_type"].items():
        if type_audit["missing"]:
            missing_str = ", ".join(f"`{r}`" for r in type_audit["missing"])
            print(f"{type_name.capitalize()}: missing {missing_str}", file=sys.stderr)
        else:
            print(f"{type_name.capitalize()}: OK", file=sys.stderr)

    diff_block = _format_gitignore_diff(audit, today)
    print("\nDiff (would be appended to .gitignore):", file=sys.stderr)
    print(diff_block, file=sys.stderr)
    print(
        "\nSee docs/process-kit/stoke-recovery-runbook.md for the audit rationale.",
        file=sys.stderr,
    )

    if args.apply:
        result = _append_to_gitignore(live_root, audit, today)
        print(
            json.dumps(
                {
                    "status": "applied",
                    "active_project_types": active,
                    "any_missing_pre_apply": True,
                    "apply_result": result,
                }
            )
        )
        return 0

    # Default: report only (Req 5 — non-blocking).
    print(
        json.dumps(
            {
                "status": "report-only",
                "active_project_types": active,
                "any_missing": True,
                "by_type": {
                    t: {"missing": d["missing"]}
                    for t, d in audit["by_type"].items()
                    if d["missing"]
                },
            }
        )
    )
    return 0


# ---- main -------------------------------------------------------------------

# Spec 431 — new subcommands shipped by the stoke/ package.
# Dispatched here so existing `.forge/lib/stoke.py <subcommand>` invocations
# continue to work after the package extraction (Req 9, AC 17).
_PACKAGE_SUBCOMMANDS = frozenset(
    {
        "detect-legacy",
        "cleanup-legacy",
        "manifest-init",
        "manifest-verify",
        "catalog-self-hash",
        "preflight-gates",
    }
)


def _dispatch_package_subcommand(argv: list[str]) -> int:
    """Forward to the stoke/ package's CLI when the first arg is a
    package-owned subcommand (Spec 431)."""
    from stoke.__main__ import main as package_main  # noqa: WPS433

    return package_main(argv)


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] in _PACKAGE_SUBCOMMANDS:
        return _dispatch_package_subcommand(sys.argv[1:])

    parser = argparse.ArgumentParser(prog="stoke.py", description="Spec 427 copier-direct stoke helper")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("direct-apply")
    p.add_argument("--live-root", default=None)
    p.add_argument("--copier-yml", default=None)
    p.add_argument("--allow-dirty", action="store_true", help="Override dirty-tree guard (operator-explicit per Req 4)")
    p.add_argument("--no-cleanup-old-backups", action="store_true")
    p.add_argument("--vcs-ref", default=None, help="Override --vcs-ref (default: read from .copier-answers.yml::_commit)")
    p.add_argument("--trust", action="store_true", help="Pass --trust to copier update. OPERATOR-EXPLICIT per invocation per Req 1 / AC 7 / CISO Constraint — never baked into defaults, never from env, never from config. The /forge stoke command body prompts the operator and passes this flag only after explicit consent.")
    p.add_argument("--confirm-security-overrides", action="store_true", help="Spec 434 Req 4: confirm honoring accept_security_overrides when .copier-answers.yml shows no in-session operator edit (fresh-clone state). Required to proceed when the security-override-consent gate WARNs.")
    p.add_argument("--data", action="append", default=[], help="Spec 444: pass KEY=VALUE through to `copier update --data`. Used by the /forge stoke chat-mediation flow to supply `accept_security_overrides=true` and `accept_security_overrides_confirmed=true` after explicit operator yes-answers via Step 0pre.05. Repeatable. MUST originate from operator yes-answers in the current chat turn — never from env vars, config files, or implicit context (Spec 444 Constraint).")
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

    # Spec 432 — scoped staging + exclusion audit
    p = sub.add_parser(
        "safe-stage",
        help="Stage paths through the project-type exclusion filter (Spec 432). "
             "Never uses `git add -A`. With --commit-message, also commits and runs "
             "the post-commit audit.",
    )
    p.add_argument("--live-root", default=None)
    p.add_argument("--catalog", default=None, help="Override path to project-type-exclusions.yaml (testing).")
    p.add_argument(
        "--paths",
        nargs="*",
        default=None,
        help="Explicit list of paths to stage. Mutually informative with --restored; "
             "if --paths is set, the tracked-files list is NOT used.",
    )
    p.add_argument(
        "--restored",
        nargs="*",
        default=None,
        help="Additional paths to stage on top of the tracked-files list "
             "(e.g., files restored by Step 0b before copier update).",
    )
    p.add_argument(
        "--commit-message",
        default=None,
        help="If set, run `git commit -m <msg>` after staging and audit the resulting commit.",
    )
    p.add_argument("--dry-run", action="store_true", help="Show what would be staged; do not modify the index.")
    p.set_defaults(func=cmd_safe_stage)

    p = sub.add_parser(
        "audit-commit",
        help="Post-hoc audit of an existing commit against the active exclusion catalog (Spec 432).",
    )
    p.add_argument("--live-root", default=None)
    p.add_argument("--catalog", default=None)
    p.add_argument("--commit-ref", default="HEAD")
    p.set_defaults(func=cmd_audit_commit)

    # Spec 433 — consumer .gitignore audit
    p = sub.add_parser(
        "audit-gitignore",
        help="Audit the consumer's .gitignore against the active project-type catalog (Spec 433). "
             "Reports missing rules; with --apply, appends them (preserves existing content + line endings).",
    )
    p.add_argument("--live-root", default=None)
    p.add_argument("--catalog", default=None, help="Override project-type-exclusions.yaml path.")
    p.add_argument(
        "--apply",
        action="store_true",
        help="Append missing rules to .gitignore (operator consent must be obtained "
             "by the caller per Req 4). Without --apply, the audit is report-only.",
    )
    p.add_argument(
        "--no-gitignore-audit",
        action="store_true",
        help="Short-circuit: print 'skipped' and exit. Required for the operator "
             "to disable the audit per invocation (Req 4).",
    )
    p.set_defaults(func=cmd_audit_gitignore)

    # Spec 428 — dynamic _tasks enumeration for Step 0pre.1 consent prompt.
    p = sub.add_parser(
        "list-tasks",
        help="Emit copier.yml::_tasks names from the resolved source, one per line. "
             "Powers the Step 0pre.1 --trust consent prompt (Spec 428).",
    )
    p.add_argument("--src-path", default=None, help="Override source path (default: read _src_path from .copier-answers.yml).")
    p.add_argument("--live-root", default=None, help="Project root for resolving .copier-answers.yml (default: cwd).")
    p.set_defaults(func=cmd_list_tasks)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

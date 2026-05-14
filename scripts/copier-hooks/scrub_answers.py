#!/usr/bin/env python3
"""Spec 294 — Copier-Native Placeholder Scrub and Migration.

Invoked from copier.yml's `_tasks:` and `_migrations:` blocks via
`{{ _copier_python }} {{ _copier_conf.src_path }}/scripts/copier-hooks/scrub_answers.py <mode>`.

Modes:
    scrub    (from _tasks:)       Guarded scrub on every copier copy/update.
                                   Only blanks a field when the field's current value
                                   equals a legacy placeholder AND the template's default
                                   for that field also equals the same placeholder — i.e.,
                                   the value is provably inherited from a legacy default,
                                   not operator-typed.
    migrate  (from _migrations:)  One-shot heal on pre-294 → post-294 update. Version-gated
                                   by Copier; unconditional allowlist scrub within scope.
                                   Creates .copier-answers.yml.pre-294.bak backup on first run.

Legacy allowlist (retained PERMANENTLY — required to reproduce historical migrations):
    author: "Your Name"
    harness_command: "# No harness configured — customize in CLAUDE.md"

On failure: writes to stderr with rollback runbook path, exits non-zero.
On no-op: prints nothing, exits 0.
On scrub: prints one-line summary to stdout.

See: docs/specs/294-canonical-project-yaml-with-answers-projection.md
     docs/process-kit/answers-file-rollback.md
     docs/decisions/ADR-294-copier-native-placeholder-scrub.md
"""
from __future__ import annotations

import os
import pathlib
import shutil
import sys
from typing import Any

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "scrub_answers.py: PyYAML not available. Copier bundles PyYAML; "
        "this should not happen. See docs/process-kit/answers-file-rollback.md\n"
    )
    sys.exit(2)

RUNBOOK = "docs/process-kit/answers-file-rollback.md"

# Retention: PERMANENT — required for migration of pre-294 projects.
# Do NOT prune entries even after all pre-294 consumers upgrade.
LEGACY_ALLOWLIST: dict[str, str] = {
    "author": "Your Name",
    "harness_command": "# No harness configured — customize in CLAUDE.md",
}

BUILD_FILES = (
    "pyproject.toml",
    "package.json",
    "Cargo.toml",
    "go.mod",
    "Gemfile",
    "pom.xml",
)


def _fail(msg: str) -> None:
    sys.stderr.write(f"Migration failed — {msg}. See {RUNBOOK} for recovery steps.\n")
    sys.exit(1)


def _detect_unambiguous_stack(project_root: pathlib.Path) -> str | None:
    """Return the single build file if exactly one is present, else None (ambiguous).

    AC5: exactly one build/lock file → stack = detected (single); zero or multiple → ambiguous.
    Migration never invents command values — this is used only to flag 'unambiguous but blank',
    which per AC5 migration still does NOT populate. The result is currently informational; the
    hook is here for future specs that may invent commands.
    """
    present = [f for f in BUILD_FILES if (project_root / f).exists()]
    return present[0] if len(present) == 1 else None


def _load_yaml(path: pathlib.Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        _fail(f"{path} did not parse as a YAML mapping")
    return data


def _copier_defaults(src_path: pathlib.Path) -> dict[str, Any]:
    """Read copier.yml from the template source and extract field defaults.

    Returns a mapping of field-name → default-value for fields in the allowlist.
    """
    copier_yml = src_path / "copier.yml"
    if not copier_yml.exists():
        return {}
    raw = _load_yaml(copier_yml)
    defaults: dict[str, Any] = {}
    for field in LEGACY_ALLOWLIST:
        spec = raw.get(field)
        if isinstance(spec, dict) and "default" in spec:
            defaults[field] = spec["default"]
    return defaults


def _ensure_gitignore_entry(project_root: pathlib.Path) -> None:
    """Append `.copier-answers.yml*.bak` to consumer's .gitignore if absent."""
    pattern = ".copier-answers.yml*.bak"
    gitignore = project_root / ".gitignore"
    if not gitignore.exists():
        return  # no .gitignore to update; not our job to create one
    content = gitignore.read_text(encoding="utf-8")
    # Match exact pattern or a broader wildcard that covers it.
    if pattern in content or ".copier-answers.yml*" in content or "*.bak" in content:
        return
    separator = "" if content.endswith("\n") else "\n"
    gitignore.write_text(
        f"{content}{separator}\n# Spec 294 — answers-file backup (created by _migrations: heal)\n{pattern}\n",
        encoding="utf-8",
    )


def _atomic_write_yaml(path: pathlib.Path, data: dict[str, Any]) -> None:
    """Write YAML atomically: temp file in same dir, then rename."""
    tmp = path.with_suffix(path.suffix + ".tmp")
    try:
        with tmp.open("w", encoding="utf-8") as f:
            yaml.safe_dump(data, f, sort_keys=False, default_flow_style=False)
        os.replace(tmp, path)
    except OSError as exc:
        if tmp.exists():
            try:
                tmp.unlink()
            except OSError:
                pass
        _fail(f"atomic write failed for {path}: {exc}")


def _answers_path(project_root: pathlib.Path, answers_filename: str) -> pathlib.Path:
    return project_root / answers_filename


def _determine_paths() -> tuple[pathlib.Path, pathlib.Path, str]:
    """Resolve project root, template source path, and answers filename from env.

    Copier sets environment variables and also passes {{ _copier_conf.dst_path }} /
    {{ _copier_conf.src_path }} to tasks. This script reads CWD for dst_path (Copier
    sets CWD to the destination), and COPIER_SRC_PATH for the template source. A CLI
    fallback via sys.argv is supported for testing.
    """
    # CWD = destination (Copier runs tasks with CWD set to the generated project root).
    project_root = pathlib.Path.cwd()

    # Template source path — passed as argv[2] by the task invocation, or via env.
    src_path_str = (
        sys.argv[2]
        if len(sys.argv) > 2
        else os.environ.get("COPIER_SRC_PATH") or ""
    )
    src_path = pathlib.Path(src_path_str) if src_path_str else project_root

    # Answers filename — default is .copier-answers.yml, configurable via _answers_file
    # in copier.yml, but 294 commits to the default (see Constraints in the spec).
    answers_filename = os.environ.get("COPIER_ANSWERS_FILE", ".copier-answers.yml")

    return project_root, src_path, answers_filename


def run_scrub(project_root: pathlib.Path, src_path: pathlib.Path, answers_filename: str) -> int:
    """Guarded scrub — only blanks when default == legacy (can't be operator-set)."""
    answers_path = _answers_path(project_root, answers_filename)
    if not answers_path.exists():
        # Fresh bootstrap before Copier has written the answers file — no-op.
        return 0

    answers = _load_yaml(answers_path)
    defaults = _copier_defaults(src_path)

    changed_fields: list[str] = []
    for field, legacy_value in LEGACY_ALLOWLIST.items():
        current = answers.get(field)
        default = defaults.get(field)
        if current == legacy_value and default == legacy_value:
            # Value is provably inherited from a legacy default — safe to blank.
            answers[field] = ""
            changed_fields.append(field)

    if not changed_fields:
        return 0

    _atomic_write_yaml(answers_path, answers)
    print(f"scrubbed: {len(changed_fields)} legacy default(s) — {', '.join(changed_fields)}")
    return 0


def run_migrate(project_root: pathlib.Path, src_path: pathlib.Path, answers_filename: str) -> int:
    """One-shot heal — unconditional allowlist scrub (version-gated by Copier)."""
    answers_path = _answers_path(project_root, answers_filename)
    if not answers_path.exists():
        return 0

    answers = _load_yaml(answers_path)

    changed_fields: list[str] = []
    for field, legacy_value in LEGACY_ALLOWLIST.items():
        current = answers.get(field)
        if current == legacy_value:
            answers[field] = ""
            changed_fields.append(field)

    # Informational only — AC5 says migration does NOT invent command values.
    # Recorded here for traceability; does not alter answers.
    _ = _detect_unambiguous_stack(project_root)

    if not changed_fields:
        return 0

    # Backup original state before any mutation. Create only if absent so that
    # repeated migration runs do not overwrite the pristine pre-294 snapshot.
    backup_path = answers_path.with_suffix(answers_path.suffix + ".pre-294.bak")
    if not backup_path.exists():
        shutil.copy2(answers_path, backup_path)

    _atomic_write_yaml(answers_path, answers)
    _ensure_gitignore_entry(project_root)

    print(
        f"migrated: {len(changed_fields)} field(s) scrubbed — "
        f"{', '.join(changed_fields)}; backup at {backup_path.name}"
    )
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        _fail("usage: scrub_answers.py <scrub|migrate> [src_path]")
    mode = sys.argv[1]
    try:
        project_root, src_path, answers_filename = _determine_paths()
        if mode == "scrub":
            return run_scrub(project_root, src_path, answers_filename)
        if mode == "migrate":
            return run_migrate(project_root, src_path, answers_filename)
        _fail(f"unknown mode: {mode!r} (expected 'scrub' or 'migrate')")
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 — deliberate catch-all at entry point
        _fail(f"unexpected error: {exc.__class__.__name__}: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

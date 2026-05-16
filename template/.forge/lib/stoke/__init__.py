"""FORGE stoke package.

Spec 431 — refactor of monolithic stoke.py into a package with submodules.

Submodules:
  manifest      — ~/.claude/.forge-installed.json read/write with atomic write
                  + advisory lock + schema_version (Req 1, 1a, 1b).
  catalog       — template/.forge/data/legacy-signatures.yaml load + per-entry
                  hash-pin + catalog_sha256 self-hash verification (Req 3, 4).
  legacy_detect — manifest-orphan, catalog-signature-match, and project-orphan
                  detection (Reqs 2, 3, 10).
  backup        — $TMPDIR/forge-stoke-legacy-cleanup-<ISO8601>-<PID>/ snapshot
                  with O_NOFOLLOW + O_EXCL + mode 0700 (Req 6).
  cleanup       — consent-gated deletion with realpath canonicalization,
                  symlink refusal, manifest-attested CLAUDE.md section removal
                  (Reqs 5, 7, 8, 1b).
  reporter      — grouped output (manifest-orphan / legacy-signature-match /
                  project-orphan / review-manually) with backup + retention.

The legacy single-file CLI in stoke.py is preserved as the entry point for
existing subcommands (direct-apply, audit, parse-sections, backup-create,
cleanup-old-backups, safe-stage, audit-commit, list-tasks, audit-gitignore).
New subcommands (detect-legacy, cleanup-legacy) dispatch into this package.
"""

__all__ = [
    "manifest",
    "catalog",
    "legacy_detect",
    "backup",
    "cleanup",
    "reporter",
]

# Spec 442 — Re-export legacy CLI callables from sibling stoke.py.
#
# Python's import resolution prefers this package over the sibling stoke.py
# file (Spec 431 design — the CLI is invoked as `forge-py .forge/lib/stoke.py`,
# bypassing import resolution at runtime). Test code that does
# `import stoke; stoke.cmd_safe_stage(...)` would otherwise see the package
# instead of the module and find no `cmd_*` attributes. This block loads
# stoke.py explicitly via importlib and promotes its `cmd_*` + `main`
# callables into the package namespace, restoring the pre-431 import API.
#
# The legacy file's `if __name__ == "__main__":` guard is not triggered here
# because importlib assigns the module name `stoke._cli`, not `__main__`.
import importlib.util as _ilu_util
from pathlib import Path as _Path

_legacy_path = _Path(__file__).parent.parent / "stoke.py"
if _legacy_path.is_file():
    _spec = _ilu_util.spec_from_file_location("stoke._cli", _legacy_path)
    _cli = _ilu_util.module_from_spec(_spec)
    _spec.loader.exec_module(_cli)
    # Re-export all top-level callables AND module-level values from the
    # legacy file. Tests reach into stoke for both public command entry points
    # (`cmd_*`) and module-private helpers (`_path_matches_patterns`,
    # `_normalize_to_gitignore_rule`, `_load_exclusion_catalog`, etc.).
    # Excluded names:
    #   - dunder names (`__name__`, `__file__`, etc. — already package-owned)
    #   - names already in this package's namespace (don't shadow submodules)
    #   - stdlib re-imports that may have leaked into stoke.py's namespace
    #     (filtered by checking that the value was defined IN stoke.py via
    #     `getattr(value, '__module__', None) == 'stoke._cli'` for functions,
    #     OR by always-allowing non-callable scalars used as constants).
    for _name in dir(_cli):
        if _name.startswith("__"):
            continue
        if _name in globals():
            continue
        _val = getattr(_cli, _name)
        # Always promote module-private helpers (start with `_`), `cmd_*`,
        # `main`, and module-level constants. Don't promote re-imported
        # stdlib modules / classes (e.g. `argparse`, `os`, `Path`).
        if callable(_val):
            _mod = getattr(_val, "__module__", "")
            if _mod and _mod != "stoke._cli":
                continue  # skip imported callables (argparse.ArgumentParser, etc.)
        globals()[_name] = _val
    # Locals may not all be bound if the loop never set _val / _mod (empty
    # legacy file edge case); use a tolerant cleanup.
    for _local in ("_val", "_mod", "_name", "_spec", "_cli"):
        globals().pop(_local, None)
    del _local
del _legacy_path, _ilu_util, _Path

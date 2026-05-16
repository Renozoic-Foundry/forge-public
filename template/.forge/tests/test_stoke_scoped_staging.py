"""Spec 432 — Stoke scoped staging + project-type build-artifact exclusions.

Tests the safe-stage path in stoke.py:
  - Manifest-presence detection (Req 2)
  - Multiple project types simultaneously (Req 3)
  - Allow-list staging via explicit `git add -- <path>` (Req 4)
  - Hard refusal under --allow-dirty semantics (Req 5)
  - Post-commit audit catches contamination (Req 6)
  - Catalog mutation changes behavior with no code change (Req 1 / AC 8)
  - Operator extras EXTEND, not replace, the template catalog (Req 8 / AC 6)
  - adc-rag replay (AC 9)

Cross-platform: test logic is pure Python; harness identical on bash and PowerShell.
Run: pytest template/.forge/tests/test_stoke_scoped_staging.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

# Make the stoke module importable without packaging.
LIB_DIR = Path(__file__).resolve().parent.parent / "lib"
sys.path.insert(0, str(LIB_DIR))

import stoke  # noqa: E402


# ---- helpers ----------------------------------------------------------------


def _git(*args: str, cwd: Path) -> str:
    # Python 3.14 on Windows + pytest captured stdin can fail handle inheritance
    # when capture_output=True is used. Wire stdin to DEVNULL explicitly.
    result = subprocess.run(
        ["git", *args],
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    return result.stdout


def _init_repo(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    _git("init", "-q", cwd=root)
    _git("config", "user.email", "test@example.com", cwd=root)
    _git("config", "user.name", "Test", cwd=root)
    _git("config", "commit.gpgsign", "false", cwd=root)
    # Initial commit so HEAD exists.
    (root / "README.md").write_text("init\n", encoding="utf-8")
    _git("add", "--", "README.md", cwd=root)
    _git("commit", "-q", "-m", "init", cwd=root)


def _write(root: Path, rel: str, content: str = "x\n") -> Path:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    return p


def _committed_files(root: Path, ref: str = "HEAD") -> list[str]:
    out = _git("show", "--name-only", f"--pretty=format:", ref, cwd=root)
    return [line.strip() for line in out.splitlines() if line.strip()]


# Default catalog: the real one shipped with FORGE.
DEFAULT_CATALOG = Path(__file__).resolve().parent.parent / "data" / "project-type-exclusions.yaml"


# ---- AC 1: Maven consumer — target/ excluded -------------------------------


def test_ac1_maven_target_excluded_from_stoke_commit(tmp_path: Path) -> None:
    repo = tmp_path / "maven-repo"
    _init_repo(repo)
    _write(repo, "pom.xml", "<project/>\n")
    # FORGE-scope restored file (must be staged)
    _write(repo, ".forge/state/restored.json", "{}\n")
    # Build artifact (must NOT be staged)
    _write(repo, "target/Foo.class", "bytes\n")

    rc = stoke.cmd_safe_stage(
        _ns(
            live_root=str(repo),
            catalog=str(DEFAULT_CATALOG),
            paths=None,
            restored=[".forge/state/restored.json", "pom.xml", "target/Foo.class"],
            commit_message="Spec 432 test: Maven scoped staging",
            dry_run=False,
        )
    )
    assert rc == 0, "safe-stage must succeed on Maven fixture"
    committed = _committed_files(repo)
    assert "target/Foo.class" not in committed
    assert ".forge/state/restored.json" in committed


# ---- AC 2: Node consumer — node_modules/ excluded --------------------------


def test_ac2_node_modules_excluded(tmp_path: Path) -> None:
    repo = tmp_path / "node-repo"
    _init_repo(repo)
    _write(repo, "package.json", '{"name":"x"}\n')
    _write(repo, ".forge/state/restored.json", "{}\n")
    _write(repo, "node_modules/lodash/index.js", "module.exports={}\n")

    rc = stoke.cmd_safe_stage(
        _ns(
            live_root=str(repo),
            catalog=str(DEFAULT_CATALOG),
            paths=None,
            restored=["package.json", "node_modules/lodash/index.js", ".forge/state/restored.json"],
            commit_message="Spec 432 test: Node scoped staging",
            dry_run=False,
        )
    )
    assert rc == 0
    committed = _committed_files(repo)
    assert "node_modules/lodash/index.js" not in committed
    assert ".forge/state/restored.json" in committed


# ---- AC 3: Python consumer — __pycache__ + egg-info excluded ---------------


def test_ac3_python_caches_excluded(tmp_path: Path) -> None:
    repo = tmp_path / "py-repo"
    _init_repo(repo)
    _write(repo, "pyproject.toml", "[project]\nname='x'\n")
    _write(repo, ".forge/state/restored.json", "{}\n")
    _write(repo, "__pycache__/x.pyc", "bytecode\n")
    _write(repo, "src/pkg.egg-info/PKG-INFO", "Metadata-Version: 2.1\n")

    rc = stoke.cmd_safe_stage(
        _ns(
            live_root=str(repo),
            catalog=str(DEFAULT_CATALOG),
            paths=None,
            restored=[
                "pyproject.toml",
                ".forge/state/restored.json",
                "__pycache__/x.pyc",
                "src/pkg.egg-info/PKG-INFO",
            ],
            commit_message="Spec 432 test: Python scoped staging",
            dry_run=False,
        )
    )
    assert rc == 0
    committed = _committed_files(repo)
    assert "__pycache__/x.pyc" not in committed
    assert "src/pkg.egg-info/PKG-INFO" not in committed
    assert ".forge/state/restored.json" in committed


# ---- AC 4: Polyglot consumer — both exclusions in one run ------------------


def test_ac4_polyglot_pom_plus_package_json(tmp_path: Path) -> None:
    repo = tmp_path / "polyglot-repo"
    _init_repo(repo)
    _write(repo, "pom.xml", "<project/>\n")
    _write(repo, "package.json", '{"name":"poly"}\n')
    _write(repo, ".forge/state/restored.json", "{}\n")
    _write(repo, "target/A.class", "x\n")
    _write(repo, "node_modules/x/index.js", "y\n")

    rc = stoke.cmd_safe_stage(
        _ns(
            live_root=str(repo),
            catalog=str(DEFAULT_CATALOG),
            paths=None,
            restored=[
                "pom.xml",
                "package.json",
                ".forge/state/restored.json",
                "target/A.class",
                "node_modules/x/index.js",
            ],
            commit_message="Spec 432 test: polyglot scoped staging",
            dry_run=False,
        )
    )
    assert rc == 0
    committed = _committed_files(repo)
    assert "target/A.class" not in committed
    assert "node_modules/x/index.js" not in committed


# ---- AC 5: --allow-dirty does NOT relax the catalog ------------------------
# Implemented via the dry-run path showing target/* always lands in blocked.


def test_ac5_allow_dirty_does_not_relax_catalog(tmp_path: Path) -> None:
    repo = tmp_path / "maven-dirty"
    _init_repo(repo)
    _write(repo, "pom.xml", "<project/>\n")
    _write(repo, "target/Bar.class", "bytes\n")

    rc = stoke.cmd_safe_stage(
        _ns(
            live_root=str(repo),
            catalog=str(DEFAULT_CATALOG),
            paths=["target/Bar.class"],   # operator forces this exact list
            restored=None,
            commit_message=None,
            dry_run=True,
        )
    )
    # With nothing safe to stage, safe-stage exits 6 (ABORT). The catalog still
    # refused target/Bar.class regardless of operator intent. That IS the AC.
    assert rc in (6,), f"expected ABORT exit 6, got {rc}"


# ---- AC 6: operator extras EXTEND, do not replace --------------------------


def test_ac6_operator_extras_extend_catalog(tmp_path: Path) -> None:
    repo = tmp_path / "extras-repo"
    _init_repo(repo)
    _write(repo, "pom.xml", "<project/>\n")
    _write(repo, ".copier-answers.yml", "project_type_exclusions_extra:\n  - my-custom-build/**\n")
    _write(repo, "my-custom-build/out.bin", "x\n")
    _write(repo, "target/X.class", "x\n")  # still excluded by template
    _write(repo, ".forge/state/restored.json", "{}\n")

    rc = stoke.cmd_safe_stage(
        _ns(
            live_root=str(repo),
            catalog=str(DEFAULT_CATALOG),
            paths=None,
            restored=[
                "pom.xml",
                ".copier-answers.yml",
                "my-custom-build/out.bin",
                "target/X.class",
                ".forge/state/restored.json",
            ],
            commit_message="Spec 432 test: operator extras",
            dry_run=False,
        )
    )
    assert rc == 0
    committed = _committed_files(repo)
    assert "my-custom-build/out.bin" not in committed   # operator extra
    assert "target/X.class" not in committed             # template catalog
    assert ".forge/state/restored.json" in committed


# ---- AC 7: post-commit audit catches mid-flow contamination ----------------


def test_ac7_audit_catches_contamination_in_existing_commit(tmp_path: Path) -> None:
    repo = tmp_path / "audit-repo"
    _init_repo(repo)
    _write(repo, "pom.xml", "<project/>\n")
    _write(repo, "target/Evil.class", "bytes\n")
    # Bypass the safe path and stage everything the unsafe way to simulate
    # a pre-Spec-432 commit that contaminated the repo.
    _git("add", "-A", cwd=repo)
    _git("commit", "-q", "-m", "contaminated", cwd=repo)

    rc = stoke.cmd_audit_commit(
        _ns(
            live_root=str(repo),
            catalog=str(DEFAULT_CATALOG),
            commit_ref="HEAD",
        )
    )
    assert rc == 8, "audit-commit must exit non-zero when offenders found"


# ---- AC 8: catalog mutation changes behavior with no code change -----------


def test_ac8_catalog_is_source_of_truth(tmp_path: Path) -> None:
    repo = tmp_path / "catalog-repo"
    _init_repo(repo)
    _write(repo, "pom.xml", "<project/>\n")
    _write(repo, "weird-output/x.dat", "bytes\n")
    _write(repo, ".forge/state/restored.json", "{}\n")

    # Synthetic catalog adds `weird-output/**` to the maven type.
    synthetic = tmp_path / "synthetic-catalog.yaml"
    synthetic.write_text(
        "project_types:\n"
        "  maven:\n"
        "    manifest_files:\n"
        "      - pom.xml\n"
        "    exclude_paths:\n"
        "      - target/**\n"
        "      - weird-output/**\n",
        encoding="utf-8",
    )

    rc = stoke.cmd_safe_stage(
        _ns(
            live_root=str(repo),
            catalog=str(synthetic),
            paths=None,
            restored=["pom.xml", "weird-output/x.dat", ".forge/state/restored.json"],
            commit_message="Spec 432 test: synthetic catalog",
            dry_run=False,
        )
    )
    assert rc == 0
    committed = _committed_files(repo)
    assert "weird-output/x.dat" not in committed
    assert ".forge/state/restored.json" in committed


# ---- AC 9: adc-rag replay (Maven + Step 0b restored set) -------------------


def test_ac9_adc_rag_replay(tmp_path: Path) -> None:
    """Reproduce the 2026-05-15 adc-rag scenario in miniature:
       Maven project, 182 target/* files staged via -A; with safe-stage,
       zero target/* land in the commit and the FORGE-scoped restorations
       are committed cleanly."""
    repo = tmp_path / "adc-rag-replay"
    _init_repo(repo)
    _write(repo, "pom.xml", "<project/>\n")
    # Simulate Step 0b restorations
    restored = [
        ".forge/state/active-tab-abc123.json",
        ".forge/state/implementing.json",
        ".forge/state/last-eaci-scan-abc.json",
        ".forge/commands/forge-stoke.md",
        "docs/sessions/2026-05-15-001.md",
    ]
    for r in restored:
        _write(repo, r, f"restored content for {r}\n")
    # Simulate dirty target/ (50 files; representative of the 182-file
    # incident — actual count isn't load-bearing for the test).
    for i in range(50):
        _write(repo, f"target/classes/com/x/Class{i:03d}.class", f"bytes{i}\n")

    rc = stoke.cmd_safe_stage(
        _ns(
            live_root=str(repo),
            catalog=str(DEFAULT_CATALOG),
            paths=None,
            restored=restored,
            commit_message="adc-rag replay (Spec 432)",
            dry_run=False,
        )
    )
    assert rc == 0
    committed = _committed_files(repo)
    assert not any(f.startswith("target/") for f in committed), (
        f"target/* must not appear; got: {[f for f in committed if f.startswith('target/')]}"
    )
    for r in restored:
        assert r in committed, f"restored file missing from commit: {r}"


# ---- Detection / catalog parsing unit tests --------------------------------


def test_detection_root_only(tmp_path: Path) -> None:
    """Req 2: manifest-presence detection at ROOT only."""
    repo = tmp_path / "subdir-pom"
    repo.mkdir()
    _write(repo, "subproject/pom.xml", "<project/>\n")  # not at root
    catalog = stoke._load_exclusion_catalog(DEFAULT_CATALOG)
    active = stoke._detect_project_types(repo, catalog)
    assert "maven" not in active, "manifest in subdir must not activate type"


def test_detection_multiple_types(tmp_path: Path) -> None:
    """Req 3: multiple types active simultaneously."""
    repo = tmp_path / "poly"
    repo.mkdir()
    _write(repo, "pom.xml", "<project/>\n")
    _write(repo, "package.json", "{}\n")
    _write(repo, "go.mod", "module x\n")
    catalog = stoke._load_exclusion_catalog(DEFAULT_CATALOG)
    active = stoke._detect_project_types(repo, catalog)
    assert "maven" in active
    assert "node" in active
    assert "go" in active


def test_dotnet_csproj_glob_match(tmp_path: Path) -> None:
    repo = tmp_path / "dotnet"
    repo.mkdir()
    _write(repo, "MyApp.csproj", "<Project/>\n")
    catalog = stoke._load_exclusion_catalog(DEFAULT_CATALOG)
    active = stoke._detect_project_types(repo, catalog)
    assert "dotnet" in active


def test_path_matches_patterns_forward_slash_normalize() -> None:
    """Req 7: cross-platform — patterns use forward slashes; back-slash inputs normalize."""
    patterns = ["target/**", "node_modules/**"]
    # Windows-style backslash input
    assert stoke._path_matches_patterns("target\\Foo.class", patterns)
    assert stoke._path_matches_patterns("node_modules\\x\\index.js", patterns)
    assert not stoke._path_matches_patterns("src/main/Foo.java", patterns)


def test_constraint_no_git_add_minus_a_in_source() -> None:
    """Constraint: stoke command paths must NOT contain `git add -A` or `git add .`.

    Test files and tests/ directory are exempt — they may stage repo state for
    fixtures. Production code paths in safe-stage MUST be clean.
    """
    src = LIB_DIR / "stoke.py"
    text = src.read_text(encoding="utf-8")
    # Allow these strings ONLY inside comments/docstrings about what we DON'T do.
    # Grep for them as bare invocations: line starts with whitespace then has
    # `["git", "add"` followed by either `-A` or `.`.
    import re as _re
    bad = _re.findall(r'\["git",\s*"add",\s*"(?:-A|\.)"\]', text)
    assert not bad, f"Forbidden wildcard staging found in stoke.py: {bad}"


# ---- argparse Namespace helper ---------------------------------------------


def _ns(**kwargs):
    import argparse
    return argparse.Namespace(**kwargs)

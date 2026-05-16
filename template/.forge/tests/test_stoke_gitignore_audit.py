"""Spec 433 — Stoke consumer .gitignore audit + assisted update.

Tests the audit-gitignore subcommand:
  - Maven missing target/ → report + apply (AC 1)
  - Node containing node_modules → OK (AC 2)
  - Polyglot missing both (AC 3)
  - Decline path: no-apply leaves .gitignore unchanged (AC 4 — caller-side
    consent simulated by omitting --apply)
  - --no-gitignore-audit flag short-circuits (AC 5)
  - No-file: create with full required set (AC 6)
  - Catalog mutation changes report (AC 7)
  - Byte-equality: existing lines unchanged after append (AC 8)
  - Comment/negation lines NOT counted as satisfying a rule (DA W-1)
  - CRLF preservation (DA W-3)
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

LIB_DIR = Path(__file__).resolve().parent.parent / "lib"
sys.path.insert(0, str(LIB_DIR))

import stoke  # noqa: E402

DEFAULT_CATALOG = Path(__file__).resolve().parent.parent / "data" / "project-type-exclusions.yaml"


# ---- helpers ----------------------------------------------------------------


def _ns(**kw):
    import argparse
    return argparse.Namespace(**kw)


def _write_bytes(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


# ---- AC 1: Maven missing target/ -------------------------------------------


def test_ac1_maven_missing_target_reports_and_applies(tmp_path: Path) -> None:
    repo = tmp_path / "maven"
    repo.mkdir()
    (repo / "pom.xml").write_text("<project/>\n")
    (repo / ".gitignore").write_text("# existing\n*.log\n")

    rc = stoke.cmd_audit_gitignore(
        _ns(
            live_root=str(repo),
            catalog=str(DEFAULT_CATALOG),
            apply=True,
            no_gitignore_audit=False,
        )
    )
    assert rc == 0
    final = (repo / ".gitignore").read_text()
    assert "target/" in final
    assert "Added by /forge stoke" in final
    # Existing content preserved.
    assert "*.log" in final
    assert "# existing" in final


# ---- AC 2: Node with node_modules already present → OK ---------------------


def test_ac2_node_modules_present_reports_ok(tmp_path: Path) -> None:
    repo = tmp_path / "node"
    repo.mkdir()
    (repo / "package.json").write_text('{"name":"x"}\n')
    original = "node_modules\ndist/\n"
    (repo / ".gitignore").write_text(original)

    rc = stoke.cmd_audit_gitignore(
        _ns(
            live_root=str(repo),
            catalog=str(DEFAULT_CATALOG),
            apply=False,
            no_gitignore_audit=False,
        )
    )
    assert rc == 0
    # Unchanged on no-apply.
    assert (repo / ".gitignore").read_text() == original


# ---- AC 3: Polyglot missing both --------------------------------------------


def test_ac3_polyglot_missing_both_applied(tmp_path: Path) -> None:
    repo = tmp_path / "poly"
    repo.mkdir()
    (repo / "pom.xml").write_text("<project/>\n")
    (repo / "package.json").write_text("{}\n")
    (repo / ".gitignore").write_text("# ph\n")

    rc = stoke.cmd_audit_gitignore(
        _ns(live_root=str(repo), catalog=str(DEFAULT_CATALOG), apply=True, no_gitignore_audit=False)
    )
    assert rc == 0
    final = (repo / ".gitignore").read_text()
    assert "target/" in final
    assert "node_modules" in final


# ---- AC 4: --no-apply does not modify .gitignore ---------------------------


def test_ac4_no_apply_leaves_file_unchanged(tmp_path: Path) -> None:
    repo = tmp_path / "decline"
    repo.mkdir()
    (repo / "pom.xml").write_text("<project/>\n")
    original = "# operator content\nspecific.file\n"
    (repo / ".gitignore").write_text(original)

    rc = stoke.cmd_audit_gitignore(
        _ns(live_root=str(repo), catalog=str(DEFAULT_CATALOG), apply=False, no_gitignore_audit=False)
    )
    assert rc == 0
    assert (repo / ".gitignore").read_text() == original


# ---- AC 5: --no-gitignore-audit short-circuits -----------------------------


def test_ac5_no_gitignore_audit_flag_skips(tmp_path: Path, capsys: pytest.CaptureFixture) -> None:
    repo = tmp_path / "skip"
    repo.mkdir()
    (repo / "pom.xml").write_text("<project/>\n")
    # No .gitignore — audit would normally fire create-new path.

    rc = stoke.cmd_audit_gitignore(
        _ns(live_root=str(repo), catalog=str(DEFAULT_CATALOG), apply=True, no_gitignore_audit=True)
    )
    assert rc == 0
    captured = capsys.readouterr()
    assert "skipped" in captured.out.lower() or "skipped" in captured.err.lower()
    # No file created.
    assert not (repo / ".gitignore").exists()


# ---- AC 6: No .gitignore → create with full required set -------------------


def test_ac6_no_gitignore_create_with_required_set(tmp_path: Path) -> None:
    repo = tmp_path / "nofile"
    repo.mkdir()
    (repo / "pom.xml").write_text("<project/>\n")

    assert not (repo / ".gitignore").exists()

    rc = stoke.cmd_audit_gitignore(
        _ns(live_root=str(repo), catalog=str(DEFAULT_CATALOG), apply=True, no_gitignore_audit=False)
    )
    assert rc == 0
    assert (repo / ".gitignore").is_file()
    final = (repo / ".gitignore").read_text()
    assert "target/" in final
    assert "Added by /forge stoke" in final


# ---- AC 7: catalog mutation changes report (no code change) ----------------


def test_ac7_catalog_is_source_of_truth(tmp_path: Path) -> None:
    repo = tmp_path / "mut"
    repo.mkdir()
    (repo / "pom.xml").write_text("<project/>\n")
    (repo / ".gitignore").write_text("# nothing\n")

    synthetic = tmp_path / "synthetic.yaml"
    synthetic.write_text(
        "project_types:\n"
        "  maven:\n"
        "    manifest_files:\n"
        "      - pom.xml\n"
        "    exclude_paths:\n"
        "      - weird-output/**\n",
        encoding="utf-8",
    )

    rc = stoke.cmd_audit_gitignore(
        _ns(live_root=str(repo), catalog=str(synthetic), apply=True, no_gitignore_audit=False)
    )
    assert rc == 0
    final = (repo / ".gitignore").read_text()
    assert "weird-output/" in final
    assert "target/" not in final, "catalog mutation must replace defaults"


# ---- AC 8: Byte-equality of unchanged content ------------------------------


def test_ac8_byte_equality_of_preexisting_lines(tmp_path: Path) -> None:
    repo = tmp_path / "byteq"
    repo.mkdir()
    (repo / "pom.xml").write_text("<project/>\n")
    # Construct content with mixed indentation, blank lines, comments.
    original = "# my header\n  \n*.log\nspecific/path/\n!important.log\n"
    (repo / ".gitignore").write_text(original)

    rc = stoke.cmd_audit_gitignore(
        _ns(live_root=str(repo), catalog=str(DEFAULT_CATALOG), apply=True, no_gitignore_audit=False)
    )
    assert rc == 0
    final = (repo / ".gitignore").read_text()
    # All original lines (including blanks/comments/negation) preserved.
    for line in original.split("\n"):
        if line:
            assert line in final, f"original line missing: {line!r}"


# ---- DA W-1: comment-stripping eliminates false positives ------------------


def test_da_w1_commented_rule_is_not_satisfying(tmp_path: Path) -> None:
    repo = tmp_path / "comment"
    repo.mkdir()
    (repo / "pom.xml").write_text("<project/>\n")
    # `# target/` is a COMMENT not a rule; audit should still flag missing.
    (repo / ".gitignore").write_text("# target/   <-- commented out, not active\n*.log\n")

    rc = stoke.cmd_audit_gitignore(
        _ns(live_root=str(repo), catalog=str(DEFAULT_CATALOG), apply=False, no_gitignore_audit=False)
    )
    assert rc == 0
    # Must NOT have written the file, but the audit MUST have classified
    # target/ as missing. Re-run with apply to confirm.
    rc = stoke.cmd_audit_gitignore(
        _ns(live_root=str(repo), catalog=str(DEFAULT_CATALOG), apply=True, no_gitignore_audit=False)
    )
    final = (repo / ".gitignore").read_text()
    # Two `target/` references now: the original comment and the appended active rule.
    assert final.count("target/") >= 2
    # The comment is preserved.
    assert "# target/" in final


def test_da_w1_negation_rule_is_not_satisfying(tmp_path: Path) -> None:
    repo = tmp_path / "negate"
    repo.mkdir()
    (repo / "pom.xml").write_text("<project/>\n")
    # `!target/keep.txt` is a NEGATION, not a rule that ignores target/.
    (repo / ".gitignore").write_text("!target/keep.txt\n")

    rc = stoke.cmd_audit_gitignore(
        _ns(live_root=str(repo), catalog=str(DEFAULT_CATALOG), apply=True, no_gitignore_audit=False)
    )
    assert rc == 0
    final = (repo / ".gitignore").read_text()
    # Original negation preserved.
    assert "!target/keep.txt" in final
    # Active target/ rule now also present.
    lines = final.split("\n")
    assert any(line.strip() == "target/" for line in lines), (
        "target/ active rule must be appended; only negation was present"
    )


# ---- DA W-3: CRLF preservation ---------------------------------------------


def test_da_w3_crlf_preserved_on_append(tmp_path: Path) -> None:
    repo = tmp_path / "crlf"
    repo.mkdir()
    (repo / "pom.xml").write_text("<project/>\n")
    # Write CRLF .gitignore (Windows convention).
    _write_bytes(repo / ".gitignore", b"# header\r\n*.log\r\n")

    rc = stoke.cmd_audit_gitignore(
        _ns(live_root=str(repo), catalog=str(DEFAULT_CATALOG), apply=True, no_gitignore_audit=False)
    )
    assert rc == 0
    raw = (repo / ".gitignore").read_bytes()
    # CRLF terminator preserved across the entire file.
    assert b"\r\n" in raw
    # No bare LF lines were introduced.
    assert b"\n" in raw  # trivially true; check explicitly:
    # Verify every line ends with CRLF (no orphan LF).
    text = raw.decode()
    # Reconstruct by splitting on CRLF; should yield clean tokens.
    parts = text.split("\r\n")
    # No part should contain a bare LF (which would indicate mixed terminators).
    for part in parts:
        assert "\n" not in part, f"orphan LF in part: {part!r}"


def test_da_w3_lf_preserved_on_append(tmp_path: Path) -> None:
    repo = tmp_path / "lf"
    repo.mkdir()
    (repo / "pom.xml").write_text("<project/>\n")
    _write_bytes(repo / ".gitignore", b"# header\n*.log\n")

    rc = stoke.cmd_audit_gitignore(
        _ns(live_root=str(repo), catalog=str(DEFAULT_CATALOG), apply=True, no_gitignore_audit=False)
    )
    assert rc == 0
    raw = (repo / ".gitignore").read_bytes()
    # LF-only file should NOT have grown CRLF.
    assert b"\r\n" not in raw


# ---- Catalog parsing / normalization unit ----------------------------------


def test_normalize_to_gitignore_rule_collapses_globs() -> None:
    assert stoke._normalize_to_gitignore_rule("target/**") == "target/"
    assert stoke._normalize_to_gitignore_rule("target/") == "target/"
    assert stoke._normalize_to_gitignore_rule("**/__pycache__/**") == "__pycache__/"
    assert stoke._normalize_to_gitignore_rule("*.pyc") == "*.pyc"


def test_satisfies_rule_trailing_slash_equivalence() -> None:
    assert stoke._gitignore_satisfies_rule(["target/"], "target/") is True
    assert stoke._gitignore_satisfies_rule(["target"], "target/") is True
    assert stoke._gitignore_satisfies_rule(["**/target/"], "target/") is True
    assert stoke._gitignore_satisfies_rule(["/target/"], "target/") is True
    assert stoke._gitignore_satisfies_rule([], "target/") is False
    assert stoke._gitignore_satisfies_rule(["src/main"], "target/") is False

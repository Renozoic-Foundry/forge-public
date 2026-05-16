"""Spec 431 — tests for legacy artifact detection + cleanup + manifest.

Covers the critical ACs:
  AC 1, AC 17, AC 20    — manifest write + schema_version refusal
  AC 2                  — manifest-orphan detection
  AC 3, AC 4            — hash-pinned catalog match/mismatch
  AC 6                  — consent gate + dry-run
  AC 7                  — backup snapshot, mode 0700 (POSIX only)
  AC 8                  — non-matching files never reported
  AC 9                  — broken catalog self-hash → skipped + manifest still runs
  AC 10, AC 11          — symlink refusal, canonical path containment
  AC 12, AC 13          — CLAUDE.md section-level cleanup; no delimiter → no touch
  AC 14                 — --ack mechanism
  AC 15                 — --skip-legacy-scan
  AC 16                 — offline source fallback
  AC 21                 — manifest atomic-write (concurrent serialization)
  AC 22                 — manifest-attested delimiters (unattested → refused)
  AC 23                 — catalog deprecation warning

Run:
    pytest .forge/tests/test_stoke_431_legacy_detect.py -v

The tests import the stoke package directly from template/.forge/lib/stoke/.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import threading
from pathlib import Path

import pytest

_THIS = Path(__file__).resolve()
# Two layouts:
#   1. FORGE repo itself: .forge/tests/test_*.py with stoke at template/.forge/lib/stoke
#   2. Consumer post-bootstrap: .forge/tests/test_*.py with stoke at .forge/lib/stoke
for candidate in (
    _THIS.parents[2] / "template" / ".forge" / "lib",
    _THIS.parents[1] / "lib",
):
    if (candidate / "stoke" / "__init__.py").is_file():
        if str(candidate) not in sys.path:
            sys.path.insert(0, str(candidate))
        break
else:
    raise RuntimeError("Could not locate stoke package in either FORGE-repo or consumer layout")

from stoke import catalog as catalog_mod
from stoke import cleanup as cleanup_mod
from stoke import legacy_detect as detect_mod
from stoke import manifest as manifest_mod


# ---------------------------------------------------------------------------
# Helpers


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@pytest.fixture
def home(tmp_path: Path) -> Path:
    """Synthetic ~/ for the test: returns the home dir with .claude/ created."""
    h = tmp_path / "home"
    (h / ".claude").mkdir(parents=True)
    return h


@pytest.fixture
def template_root(tmp_path: Path) -> Path:
    """Synthetic template tree with a .claude/ subset that defines the
    'current template surface' for manifest-orphan detection."""
    t = tmp_path / "template"
    (t / ".claude" / "commands").mkdir(parents=True)
    (t / ".claude" / "commands" / "forge.md").write_text("forge cmd v2", encoding="utf-8")
    (t / ".claude" / "commands" / "current.md").write_text("current cmd", encoding="utf-8")
    return t


@pytest.fixture
def project_root(tmp_path: Path) -> Path:
    p = tmp_path / "project"
    p.mkdir()
    return p


# ---------------------------------------------------------------------------
# AC 1 + AC 17 + AC 20 — manifest write + schema version


def test_ac1_manifest_write_lists_files_with_hashes(home: Path, template_root: Path):
    target = home / ".claude" / "commands" / "forge.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("forge cmd v2", encoding="utf-8")
    expected_hash = _sha256_bytes(b"forge cmd v2")
    manifest_mod.write_install(
        src_path="gh:Renozoic-Foundry/forge-public",
        commit="abc123",
        files=[
            {"rel_path": "commands/forge.md", "sha256": expected_hash, "spec_id": "431"},
        ],
        mpath=manifest_mod.manifest_path(home),
    )
    data = manifest_mod.read(manifest_mod.manifest_path(home))
    assert data["schema_version"] == 1
    install = data["installs"]["gh:Renozoic-Foundry/forge-public"]
    assert install["commit"] == "abc123"
    assert len(install["files"]) == 1
    assert install["files"][0]["sha256"] == expected_hash


def test_ac20_schema_version_refuses_newer(home: Path):
    mpath = manifest_mod.manifest_path(home)
    mpath.parent.mkdir(parents=True, exist_ok=True)
    mpath.write_text(json.dumps({"schema_version": 999, "installs": {}}), encoding="utf-8")
    with pytest.raises(manifest_mod.ManifestSchemaUnsupported):
        manifest_mod.read(mpath)


def test_ac17_package_skeleton_exists():
    import stoke

    pkg = Path(stoke.__file__).resolve().parent
    for mod in (
        "__init__.py",
        "catalog.py",
        "manifest.py",
        "legacy_detect.py",
        "backup.py",
        "reporter.py",
        "cleanup.py",
    ):
        assert (pkg / mod).is_file(), f"missing stoke submodule: {mod}"


# ---------------------------------------------------------------------------
# AC 2 — manifest-orphan


def test_ac2_manifest_orphan_detected(home: Path, template_root: Path, project_root: Path):
    removed_path = home / ".claude" / "commands" / "removed.md"
    removed_path.parent.mkdir(parents=True, exist_ok=True)
    removed_path.write_text("legacy content", encoding="utf-8")
    h = _sha256_bytes(b"legacy content")
    manifest_mod.write_install(
        src_path="gh:Renozoic-Foundry/forge-public",
        commit="abc123",
        files=[
            {"rel_path": "commands/removed.md", "sha256": h, "spec_id": "431"},
        ],
        mpath=manifest_mod.manifest_path(home),
    )
    current = {"commands/forge.md", "commands/current.md"}
    findings, diags = detect_mod.detect_manifest_orphans(
        src_path="gh:Renozoic-Foundry/forge-public",
        home=home,
        current_template_files=current,
    )
    rel_paths = {f.rel_path for f in findings}
    assert "commands/removed.md" in rel_paths
    cats = {f.category for f in findings}
    assert "manifest-orphan" in cats


# ---------------------------------------------------------------------------
# AC 3 + AC 4 — hash-pinned catalog match/mismatch


def _write_catalog(catalog_path: Path, entries_yaml: str = ""):
    catalog_path.parent.mkdir(parents=True, exist_ok=True)
    body = (
        'catalog_sha256: "0000000000000000000000000000000000000000000000000000000000000000"\n'
        "entries:\n" + entries_yaml
    )
    catalog_path.write_text(body, encoding="utf-8")
    text = catalog_path.read_text(encoding="utf-8")
    h = catalog_mod.compute_catalog_self_hash(text, current_value="0" * 64)
    catalog_path.write_text(text.replace("0" * 64, h, 1), encoding="utf-8")


def test_ac3_catalog_match_hashpinned(home: Path, tmp_path: Path):
    seeded = home / ".claude" / "commands" / "forge.md"
    seeded.parent.mkdir(parents=True, exist_ok=True)
    content = b"pre-spec-431 legacy forge.md content"
    seeded.write_bytes(content)
    h = _sha256_bytes(content)
    catalog_path = tmp_path / "legacy-signatures.yaml"
    _write_catalog(
        catalog_path,
        entries_yaml=(
            "  - name: 'legacy-forge'\n"
            "    rel_path: 'commands/forge.md'\n"
            f"    expected_sha256: '{h}'\n"
            "    deprecation_date: '2099-01-01'\n"
        ),
    )
    findings, diags = detect_mod.detect_signature_matches(home=home, catalog_path=catalog_path)
    assert any(f.category == "legacy-signature-match" for f in findings)


def test_ac4_catalog_mismatch_not_reported(home: Path, tmp_path: Path):
    seeded = home / ".claude" / "commands" / "forge.md"
    seeded.parent.mkdir(parents=True, exist_ok=True)
    seeded.write_bytes(b"modified by one byte X")
    catalog_path = tmp_path / "legacy-signatures.yaml"
    _write_catalog(
        catalog_path,
        entries_yaml=(
            "  - name: 'legacy-forge'\n"
            "    rel_path: 'commands/forge.md'\n"
            f"    expected_sha256: '{_sha256_bytes(b'different content')}'\n"
            "    deprecation_date: '2099-01-01'\n"
        ),
    )
    findings, diags = detect_mod.detect_signature_matches(home=home, catalog_path=catalog_path)
    assert findings == []


# ---------------------------------------------------------------------------
# AC 6 — consent gate + dry-run


def test_ac6_consent_required_for_deletion(home: Path, project_root: Path):
    target = home / ".claude" / "commands" / "stale.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("stale", encoding="utf-8")
    f = detect_mod.Finding(
        artifact_id="manifest:src:commands/stale.md",
        category="manifest-orphan",
        rel_path="commands/stale.md",
        abs_path=target,
    )
    outcome = cleanup_mod.cleanup(
        findings=[f],
        home=home,
        project_root=project_root,
        src_path="src",
        consent=False,
        dry_run=False,
    )
    assert target.exists(), "consent=False must leave files untouched"
    assert outcome.deleted == []


def test_ac6_dry_run_no_deletion_no_backup(home: Path, project_root: Path):
    target = home / ".claude" / "commands" / "stale.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("stale", encoding="utf-8")
    f = detect_mod.Finding(
        artifact_id="manifest:src:commands/stale.md",
        category="manifest-orphan",
        rel_path="commands/stale.md",
        abs_path=target,
    )
    outcome = cleanup_mod.cleanup(
        findings=[f],
        home=home,
        project_root=project_root,
        src_path="src",
        consent=False,
        dry_run=True,
    )
    assert target.exists(), "dry-run must not delete"
    assert outcome.backup_dir is None, "dry-run must not write a backup"
    assert any(d.rel_path == "commands/stale.md" for d in outcome.deleted), (
        "dry-run should still surface intent under 'deleted' for reporting"
    )


# ---------------------------------------------------------------------------
# AC 7 — backup snapshot mode 0700 (POSIX) + retention warning


@pytest.mark.skipif(os.name == "nt", reason="POSIX mode bits not portable to Windows")
def test_ac7_backup_dir_mode_0700_posix(home: Path, project_root: Path, tmp_path):
    target = home / ".claude" / "commands" / "stale.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("stale", encoding="utf-8")
    f = detect_mod.Finding(
        artifact_id="manifest:src:commands/stale.md",
        category="manifest-orphan",
        rel_path="commands/stale.md",
        abs_path=target,
    )
    outcome = cleanup_mod.cleanup(
        findings=[f],
        home=home,
        project_root=project_root,
        src_path="src",
        consent=True,
        dry_run=False,
        backup_dir_override=tmp_path / "backup-parent",
    )
    assert outcome.backup_dir is not None
    mode = outcome.backup_dir.stat().st_mode & 0o777
    assert mode == 0o700, f"backup dir mode is {oct(mode)}, expected 0o700"
    assert not target.exists()
    report = "\n".join(outcome.report_lines())
    assert "30 days" in report or "retention" in report.lower()


# ---------------------------------------------------------------------------
# AC 8 — files not matching manifest/catalog never reported


def test_ac8_unmatched_files_silent(home: Path, tmp_path: Path):
    untracked = home / ".claude" / "my-custom.md"
    untracked.parent.mkdir(parents=True, exist_ok=True)
    untracked.write_text("operator notes", encoding="utf-8")
    catalog_path = tmp_path / "legacy-signatures.yaml"
    _write_catalog(catalog_path, entries_yaml="")
    findings, diags = detect_mod.detect_signature_matches(home=home, catalog_path=catalog_path)
    assert findings == []


# ---------------------------------------------------------------------------
# AC 9 — broken catalog self-hash → skipped


def test_ac9_broken_catalog_self_hash_skipped(home: Path, tmp_path: Path):
    catalog_path = tmp_path / "legacy-signatures.yaml"
    catalog_path.write_text(
        'catalog_sha256: "deadbeef000000000000000000000000000000000000000000000000deadbeef"\n'
        "entries: []\n",
        encoding="utf-8",
    )
    result = catalog_mod.load(catalog_path)
    assert not result.valid
    assert any("self-hash" in d for d in result.diagnostics)


# ---------------------------------------------------------------------------
# AC 10 + AC 11 — symlink + path canonicalization refusal


@pytest.mark.skipif(os.name == "nt", reason="symlinks require admin/dev-mode on Windows")
def test_ac10_symlink_refused(home: Path, project_root: Path):
    target_dir = home / ".claude" / "commands"
    target_dir.mkdir(parents=True, exist_ok=True)
    real = target_dir / "real.md"
    real.write_text("real", encoding="utf-8")
    link = target_dir / "linked.md"
    link.symlink_to(real)
    f = detect_mod.Finding(
        artifact_id="manifest:src:commands/linked.md",
        category="manifest-orphan",
        rel_path="commands/linked.md",
        abs_path=link,
    )
    outcome = cleanup_mod.cleanup(
        findings=[f],
        home=home,
        project_root=project_root,
        src_path="src",
        consent=True,
        dry_run=False,
    )
    assert link.is_symlink(), "symlink must NOT be deleted"
    assert real.exists(), "symlink target must NOT be deleted"
    assert any("symlink" in reason for _, reason in outcome.refused)


def test_ac11_canonical_path_outside_scope_refused(home: Path, project_root: Path, tmp_path):
    outside = tmp_path / "etc-poison.txt"
    outside.write_text("/etc/passwd content", encoding="utf-8")
    f = detect_mod.Finding(
        artifact_id="poisoned",
        category="manifest-orphan",
        rel_path="commands/poisoned.md",
        abs_path=outside,
    )
    outcome = cleanup_mod.cleanup(
        findings=[f],
        home=home,
        project_root=project_root,
        src_path="src",
        consent=True,
        dry_run=False,
    )
    assert outside.exists()
    assert any("escapes" in reason or "outside" in reason for _, reason in outcome.refused)


# ---------------------------------------------------------------------------
# AC 12 + AC 13 + AC 22 — CLAUDE.md section-level cleanup


def test_ac12_22_section_cleanup_only_attested(home: Path):
    src = "gh:test/template"
    claude_md = home / ".claude" / "CLAUDE.md"
    claude_md.write_text(
        "# User authored top\n\n"
        "<!-- FORGE:BEGIN attested -->\n"
        "forge content attested\n"
        "<!-- FORGE:END attested -->\n\n"
        "<!-- FORGE:BEGIN forged -->\n"
        "forge content forged-id (not in manifest)\n"
        "<!-- FORGE:END forged -->\n\n"
        "## User authored bottom\n",
        encoding="utf-8",
    )
    section_bytes = (
        "<!-- FORGE:BEGIN attested -->\n"
        "forge content attested\n"
        "<!-- FORGE:END attested -->\n"
    ).encode("utf-8")
    manifest_mod.write_install(
        src_path=src,
        commit="abc",
        files=[],
        claude_md_sections=[
            {
                "section_id": "attested",
                "content_sha256": _sha256_bytes(section_bytes),
                "spec_id": "431",
            },
        ],
        mpath=manifest_mod.manifest_path(home),
    )
    outcome = cleanup_mod.cleanup_claude_md_sections(
        home=home,
        src_path=src,
        section_ids=["attested", "forged"],
    )
    remaining = claude_md.read_text(encoding="utf-8")
    assert "forge content attested" not in remaining
    assert "forge content forged-id" in remaining
    assert "# User authored top" in remaining and "## User authored bottom" in remaining
    refused_ids = [sid for sid, _, _ in outcome.sections_refused]
    assert "forged" in refused_ids


def test_ac13_no_delimiters_no_modification(home: Path):
    claude_md = home / ".claude" / "CLAUDE.md"
    original = "Pure user authored content. No FORGE delimiters.\nMore content.\n"
    claude_md.write_text(original, encoding="utf-8")
    outcome = cleanup_mod.cleanup_claude_md_sections(
        home=home,
        src_path="any-src",
        section_ids=["whatever"],
    )
    assert claude_md.read_text(encoding="utf-8") == original
    assert outcome.sections_removed == []


# ---------------------------------------------------------------------------
# AC 14 — --ack mechanism


def test_ac14_ack_suppresses_reporting(home: Path):
    target = home / ".claude" / "commands" / "stale.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("stale", encoding="utf-8")
    manifest_mod.write_install(
        src_path="src",
        commit="abc",
        files=[
            {
                "rel_path": "commands/stale.md",
                "sha256": _sha256_bytes(b"stale"),
                "spec_id": "431",
            },
        ],
        mpath=manifest_mod.manifest_path(home),
    )
    current = {"commands/other.md"}
    artifact_id = "manifest:src:commands/stale.md"
    findings_before, _ = detect_mod.detect_manifest_orphans(
        src_path="src", home=home, current_template_files=current
    )
    findings_after, _ = detect_mod.detect_manifest_orphans(
        src_path="src", home=home, current_template_files=current, acks={artifact_id}
    )
    assert any(f.artifact_id == artifact_id for f in findings_before)
    assert not any(f.artifact_id == artifact_id for f in findings_after)


# ---------------------------------------------------------------------------
# AC 15 — --skip-legacy-scan (verified at CLI level; report-only here)
# AC 16 — offline source fallback


def test_ac16_offline_source_falls_back_to_manifest_only(home: Path):
    target = home / ".claude" / "commands" / "stale.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("stale", encoding="utf-8")
    manifest_mod.write_install(
        src_path="src",
        commit="abc",
        files=[
            {
                "rel_path": "commands/stale.md",
                "sha256": _sha256_bytes(b"stale"),
                "spec_id": "431",
            },
        ],
        mpath=manifest_mod.manifest_path(home),
    )
    findings, diags = detect_mod.detect_manifest_orphans(
        src_path="src",
        home=home,
        current_template_files=None,
    )
    cats = {f.category for f in findings}
    assert "manifest-orphan-offline" in cats


# ---------------------------------------------------------------------------
# AC 21 — atomic-write under serialized concurrent calls


def test_ac21_atomic_write_concurrent_serialization(home: Path):
    mp = manifest_mod.manifest_path(home)
    errors: list[Exception] = []

    def writer(idx: int):
        try:
            manifest_mod.write_install(
                src_path=f"src-{idx}",
                commit=f"commit-{idx}",
                files=[
                    {
                        "rel_path": f"commands/cmd-{idx}.md",
                        "sha256": _sha256_bytes(f"content-{idx}".encode()),
                        "spec_id": "431",
                    },
                ],
                mpath=mp,
            )
        except Exception as e:
            errors.append(e)

    threads = [threading.Thread(target=writer, args=(i,)) for i in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=60)
    assert errors == [], f"concurrent writes raised: {errors}"
    data = manifest_mod.read(mp)
    assert len(data["installs"]) == 4, f"expected 4 installs, got {len(data['installs'])}"


# ---------------------------------------------------------------------------
# AC 23 — catalog entry deprecation warning


def test_ac23_deprecation_warning_emitted(tmp_path: Path):
    catalog_path = tmp_path / "legacy-signatures.yaml"
    _write_catalog(
        catalog_path,
        entries_yaml=(
            "  - name: 'past-deprecation'\n"
            "    rel_path: 'commands/forge.md'\n"
            f"    expected_sha256: '{'a' * 64}'\n"
            "    deprecation_date: '2020-01-01'\n"
        ),
    )
    result = catalog_mod.load(catalog_path)
    assert result.valid
    assert any("catalog-entry-deprecated" in d for d in result.diagnostics)
    assert len(result.entries) == 1

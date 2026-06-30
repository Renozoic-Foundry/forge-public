"""Spec 431 — legacy artifact detection.

Three detection classes:

  manifest-orphan (Req 2)
    - Files recorded in ~/.claude/.forge-installed.json for a given src_path
      but no longer shipped by the current template version.
    - Authoritative: a file in the manifest IS provably FORGE-placed.

  legacy-signature-match (Req 3, AC 3, AC 4)
    - Migration shim for pre-manifest installs. Per-entry exact sha256 match
      against the hash-pinned catalog. No fuzzy match — mismatch is NOT
      reported.

  project-orphan (Req 10)
    - Files in the project tree that the current template version no longer
      ships. Step 6.0 of /implement 431 verified copier update --pretend does
      NOT report orphans (additive update only), so this scope stays in.

Offline-source fallback (Req 13):
  - If the current template (_src_path) is unreachable, manifest-orphan
    detection cannot run reliably (we don't know what the current template
    ships). Detection falls back to manifest-only mode with an explicit
    diagnostic naming the unreachable source. No silent failure.

Acknowledgement (Req 11):
  - Operators suppress re-reporting via --ack <artifact-id>. Ack is stored in
    .copier-answers.yml::_acknowledged_legacy_artifacts (project-local). Ack
    does NOT enable cleanup.
"""
from __future__ import annotations

import hashlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import catalog as catalog_mod
from . import manifest as manifest_mod


@dataclass
class Finding:
    """A single detection finding."""

    artifact_id: str
    category: str
    rel_path: str
    abs_path: Path
    detail: str = ""
    actionable: bool = True


@dataclass
class DetectionReport:
    manifest_orphans: list[Finding] = field(default_factory=list)
    signature_matches: list[Finding] = field(default_factory=list)
    project_orphans: list[Finding] = field(default_factory=list)
    review_manually: list[Finding] = field(default_factory=list)
    diagnostics: list[str] = field(default_factory=list)

    @property
    def is_empty(self) -> bool:
        return not (
            self.manifest_orphans
            or self.signature_matches
            or self.project_orphans
            or self.review_manually
        )

    def total(self) -> int:
        return (
            len(self.manifest_orphans)
            + len(self.signature_matches)
            + len(self.project_orphans)
            + len(self.review_manually)
        )


def _sha256_file(path: Path) -> str | None:
    try:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return None


def detect_manifest_orphans(
    src_path: str,
    home: Path,
    current_template_files: set[str] | None,
    acks: set[str] | None = None,
) -> tuple[list[Finding], list[str]]:
    """Compare manifest entries against the current template surface.

    current_template_files: set of rel_paths the current template version ships
    under ~/.claude/. None = offline fallback (manifest-only mode; Req 13).

    Returns (findings, diagnostics).
    """
    findings: list[Finding] = []
    diags: list[str] = []
    acks = acks or set()

    try:
        manifest = manifest_mod.read(manifest_mod.manifest_path(home))
    except manifest_mod.ManifestSchemaUnsupported as e:
        diags.append(str(e))
        return [], diags
    except RuntimeError as e:
        diags.append(f"manifest-read-failed: {e}")
        return [], diags

    install = manifest["installs"].get(src_path)
    if not install:
        return [], diags

    for entry in install.get("files", []):
        rel = entry["rel_path"]
        artifact_id = f"manifest:{src_path}:{rel}"
        if artifact_id in acks:
            continue
        abs_path = home / ".claude" / rel
        if not abs_path.exists():
            continue
        if current_template_files is None:
            findings.append(
                Finding(
                    artifact_id=artifact_id,
                    category="manifest-orphan-offline",
                    rel_path=rel,
                    abs_path=abs_path,
                    detail=(
                        "Source template unreachable; cannot confirm orphan "
                        "status. Reported under offline-fallback mode."
                    ),
                )
            )
            continue
        if rel not in current_template_files:
            findings.append(
                Finding(
                    artifact_id=artifact_id,
                    category="manifest-orphan",
                    rel_path=rel,
                    abs_path=abs_path,
                    detail=(
                        "Recorded in install manifest but no longer shipped "
                        "by current template — candidate for cleanup."
                    ),
                )
            )

    return findings, diags


def detect_signature_matches(
    home: Path,
    catalog_path: Path | None,
    acks: set[str] | None = None,
) -> tuple[list[Finding], list[str]]:
    """Hash-pinned catalog detection (Req 3, AC 3, AC 4).

    No fuzzy match. Mismatches are NOT reported.
    """
    findings: list[Finding] = []
    diags: list[str] = []
    acks = acks or set()

    if catalog_path is None or not catalog_path.exists():
        return [], diags

    result = catalog_mod.load(catalog_path)
    diags.extend(result.diagnostics)
    if not result.valid:
        return [], diags

    for entry in result.entries:
        artifact_id = f"signature:{entry.name}"
        if artifact_id in acks:
            continue
        matched, abs_path = catalog_mod.match_file(home, entry)
        if matched and abs_path is not None:
            findings.append(
                Finding(
                    artifact_id=artifact_id,
                    category="legacy-signature-match",
                    rel_path=entry.rel_path,
                    abs_path=abs_path,
                    detail=(
                        f"Hash-pinned legacy signature '{entry.name}' "
                        f"(deprecates {entry.deprecation_date})."
                    ),
                )
            )
        elif abs_path is not None and abs_path.is_symlink():
            findings.append(
                Finding(
                    artifact_id=f"signature-symlink:{entry.name}",
                    category="review-manually",
                    rel_path=entry.rel_path,
                    abs_path=abs_path,
                    detail=(
                        f"Path matches catalog entry '{entry.name}' but is a "
                        f"symlink — refused (Req 7)."
                    ),
                    actionable=False,
                )
            )

    return findings, diags


def detect_project_orphans(
    project_root: Path,
    manifest_files: set[str] | None,
    current_template_files: set[str] | None,
    acks: set[str] | None = None,
) -> tuple[list[Finding], list[str]]:
    """Project-orphan: files in the project tree present at some prior template
    version but absent from the current one (Req 10, AC 5).

    manifest_files: set of project-tree rel_paths the install manifest recorded
    for this project (if FORGE manifests project-tree files for this src_path).

    current_template_files: rel_paths the current template version ships.
    None = offline fallback.
    """
    findings: list[Finding] = []
    diags: list[str] = []
    acks = acks or set()

    if manifest_files is None or current_template_files is None:
        return [], diags

    orphans = manifest_files - current_template_files
    for rel in sorted(orphans):
        artifact_id = f"project-orphan:{rel}"
        if artifact_id in acks:
            continue
        abs_path = project_root / rel
        if not abs_path.exists():
            continue
        findings.append(
            Finding(
                artifact_id=artifact_id,
                category="project-orphan",
                rel_path=rel,
                abs_path=abs_path,
                detail=(
                    "Project-tree file present in install manifest but no "
                    "longer shipped by current template."
                ),
            )
        )

    return findings, diags


def detect_all(
    src_path: str,
    project_root: Path,
    home: Path,
    current_template_user_files: set[str] | None,
    current_template_project_files: set[str] | None,
    catalog_path: Path | None,
    manifest_project_files: set[str] | None = None,
    acks: set[str] | None = None,
) -> DetectionReport:
    """Run all three detection classes; aggregate into a DetectionReport."""
    report = DetectionReport()

    mf, mdiag = detect_manifest_orphans(
        src_path=src_path,
        home=home,
        current_template_files=current_template_user_files,
        acks=acks,
    )
    report.manifest_orphans.extend(
        f for f in mf if f.category == "manifest-orphan" or f.category == "manifest-orphan-offline"
    )
    report.diagnostics.extend(mdiag)

    sf, sdiag = detect_signature_matches(home=home, catalog_path=catalog_path, acks=acks)
    for f in sf:
        if f.category == "review-manually":
            report.review_manually.append(f)
        else:
            report.signature_matches.append(f)
    report.diagnostics.extend(sdiag)

    pf, pdiag = detect_project_orphans(
        project_root=project_root,
        manifest_files=manifest_project_files,
        current_template_files=current_template_project_files,
        acks=acks,
    )
    report.project_orphans.extend(pf)
    report.diagnostics.extend(pdiag)

    return report

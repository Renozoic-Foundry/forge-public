"""Spec 431 — formatted detection report.

Groups findings into the four classes the spec defines and surfaces
diagnostics from manifest + catalog loading. Output is plain-text intended
for terminal display via the /forge-stoke command surface.
"""
from __future__ import annotations

from .legacy_detect import DetectionReport, Finding


def _format_finding(f: Finding) -> str:
    line = f"  - [{f.artifact_id}] {f.rel_path}"
    if f.detail:
        line += f" — {f.detail}"
    return line


def format_report(report: DetectionReport) -> str:
    """Render a DetectionReport for terminal output.

    Empty report → single 'clean' line. Non-empty → grouped sections with
    counts, plus a trailing diagnostics block when present.
    """
    if report.is_empty and not report.diagnostics:
        return "Legacy detection: no orphan or signature-matched artifacts found."

    sections: list[str] = []

    if report.manifest_orphans:
        sections.append(
            f"## Manifest-orphan candidates ({len(report.manifest_orphans)})"
        )
        sections.append(
            "Files previously installed by FORGE under ~/.claude/ that the "
            "current template no longer ships. Provably FORGE-placed."
        )
        for f in report.manifest_orphans:
            sections.append(_format_finding(f))
        sections.append("")

    if report.signature_matches:
        sections.append(
            f"## Legacy-signature matches ({len(report.signature_matches)})"
        )
        sections.append(
            "Pre-manifest artifacts matching the hash-pinned legacy catalog "
            "(exact sha256 only; mismatches are not reported)."
        )
        for f in report.signature_matches:
            sections.append(_format_finding(f))
        sections.append("")

    if report.project_orphans:
        sections.append(
            f"## Project-orphan candidates ({len(report.project_orphans)})"
        )
        sections.append(
            "Files in the project tree present in the install manifest but "
            "no longer shipped by the current template."
        )
        for f in report.project_orphans:
            sections.append(_format_finding(f))
        sections.append("")

    if report.review_manually:
        sections.append(
            f"## Review manually ({len(report.review_manually)})"
        )
        sections.append(
            "Findings that match policy refusals (symlinks, unattested "
            "FORGE delimiters). Cleanup never acts on these."
        )
        for f in report.review_manually:
            sections.append(_format_finding(f))
        sections.append("")

    if report.diagnostics:
        sections.append(f"## Diagnostics ({len(report.diagnostics)})")
        for d in report.diagnostics:
            sections.append(f"  - {d}")
        sections.append("")

    sections.append(
        "Next: run `python -m forge_stoke cleanup-legacy --dry-run` to "
        "preview, then `--consent` to act. Suppress a stable artifact with "
        "`--ack <artifact-id>`. Bypass detection entirely with "
        "`--skip-legacy-scan`."
    )
    return "\n".join(sections)

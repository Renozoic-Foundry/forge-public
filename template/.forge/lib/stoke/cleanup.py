"""Spec 431 — consent-gated legacy artifact cleanup.

Hard contracts (Constraints section + Reqs 5, 6, 7, 8):

  - Per-invocation consent only. No env var, no persistent consent, no
    flag-file. Absence of consent → all detected files untouched (AC 6).
  - --dry-run prints intent + would-write backup path but performs neither
    deletion nor backup write (AC 6, Req 15).
  - Every deletion target is canonicalized (realpath) and MUST resolve to a
    path strictly within ~/.claude/ OR the project tree (Req 7, AC 11).
  - Symlinks are refused — the symlink itself is reported as
    "review manually" and skipped (Req 7, AC 10).
  - ~/.claude/CLAUDE.md is never deleted. Cleanup removes ONLY content
    between <!-- FORGE:BEGIN <id> --> and <!-- FORGE:END <id> --> markers
    AND only when <id> is manifest-attested for the corresponding src_path
    (Req 8, Req 1b, AC 22, AC 12, AC 13).
  - Acknowledgement (--ack) does NOT enable cleanup. Suppress-acknowledged is
    a separate axis from consent (Req 11, AC 14).
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from . import backup as backup_mod
from . import manifest as manifest_mod
from .legacy_detect import Finding

CLAUDE_MD_REL = "CLAUDE.md"
DELIMITER_BEGIN_RE = re.compile(
    r"^<!--\s*FORGE:BEGIN\s+([A-Za-z0-9_\-./]+)\s*-->\s*$", re.MULTILINE
)
DELIMITER_END_TEMPLATE = "<!-- FORGE:END {section_id} -->"


@dataclass
class CleanupOutcome:
    deleted: list[Finding] = field(default_factory=list)
    refused: list[tuple[Finding, str]] = field(default_factory=list)
    sections_removed: list[tuple[str, Path]] = field(default_factory=list)
    sections_refused: list[tuple[str, Path, str]] = field(default_factory=list)
    backup_dir: Path | None = None
    dry_run: bool = False

    def report_lines(self) -> list[str]:
        lines: list[str] = []
        if self.dry_run:
            lines.append("DRY-RUN — no files deleted, no backup written.")
        if self.backup_dir is not None and not self.dry_run:
            lines.append(f"Backup snapshot: {self.backup_dir}")
            lines.append(backup_mod.retention_warning(self.backup_dir))
        if self.deleted:
            lines.append(f"Deleted {len(self.deleted)} artifact(s):")
            for f in self.deleted:
                lines.append(f"  - [{f.category}] {f.rel_path}")
        if self.refused:
            lines.append(f"Refused {len(self.refused)} artifact(s):")
            for f, reason in self.refused:
                lines.append(f"  - [{f.category}] {f.rel_path}: {reason}")
        if self.sections_removed:
            lines.append(f"CLAUDE.md sections removed: {len(self.sections_removed)}")
            for sid, path in self.sections_removed:
                lines.append(f"  - {sid} in {path}")
        if self.sections_refused:
            lines.append(
                f"CLAUDE.md sections refused (unattested or out-of-scope): "
                f"{len(self.sections_refused)}"
            )
            for sid, path, reason in self.sections_refused:
                lines.append(f"  - {sid} in {path}: {reason}")
        if not lines:
            lines.append("No cleanup actions performed.")
        return lines


def _is_within(target: Path, allowed_roots: Iterable[Path]) -> bool:
    """Canonical-path containment: target.resolve() must be strictly within
    one of allowed_roots (also canonicalized)."""
    try:
        rt = target.resolve(strict=False)
    except OSError:
        return False
    for root in allowed_roots:
        try:
            rt.relative_to(root.resolve(strict=False))
            return True
        except ValueError:
            continue
    return False


def _classify_finding_for_delete(
    finding: Finding,
    home: Path,
    project_root: Path,
) -> tuple[bool, str]:
    """Return (allowed_to_delete, reason_if_not).

    Refusal reasons (Reqs 7, 8, AC 10, AC 11):
      - symlink refused
      - target outside ~/.claude/ AND outside project_root
      - target is CLAUDE.md (section-level handled separately)
      - finding not actionable (already flagged as review-manually)
    """
    if not finding.actionable:
        return False, "finding flagged review-manually"
    if finding.category not in ("manifest-orphan", "legacy-signature-match", "project-orphan"):
        return False, f"category '{finding.category}' is not deletable"

    abs_path = finding.abs_path
    if not abs_path.exists():
        return False, "target missing at cleanup time"
    if abs_path.is_symlink():
        return False, "target is a symlink — refused per Req 7"
    if abs_path.name == CLAUDE_MD_REL:
        return False, "CLAUDE.md is handled via section-level cleanup, not deletion"

    home_claude = home / ".claude"
    allowed = [home_claude, project_root]
    if not _is_within(abs_path, allowed):
        return False, (
            f"canonicalized path escapes ~/.claude/ and project tree "
            f"(realpath={abs_path.resolve(strict=False)})"
        )

    return True, ""


def _find_forge_sections(text: str) -> list[tuple[str, int, int]]:
    """Locate <!-- FORGE:BEGIN <id> --> ... <!-- FORGE:END <id> --> spans.

    Returns list of (section_id, span_start, span_end). span_end is exclusive
    and includes the END marker line + its trailing newline if present.
    """
    spans: list[tuple[str, int, int]] = []
    for m in DELIMITER_BEGIN_RE.finditer(text):
        section_id = m.group(1)
        end_marker = DELIMITER_END_TEMPLATE.format(section_id=section_id)
        end_idx = text.find(end_marker, m.end())
        if end_idx == -1:
            continue
        end_line_end = text.find("\n", end_idx)
        if end_line_end == -1:
            end_line_end = len(text)
        else:
            end_line_end += 1
        spans.append((section_id, m.start(), end_line_end))
    return spans


def cleanup_claude_md_sections(
    home: Path,
    src_path: str,
    section_ids: Iterable[str],
    dry_run: bool = False,
    outcome: CleanupOutcome | None = None,
) -> CleanupOutcome:
    """Section-level cleanup of ~/.claude/CLAUDE.md (Req 8, AC 12, AC 13, AC 22).

    For each section_id:
      - Refuse if the id is NOT manifest-attested for src_path (unattested
        FORGE delimiter / forgery defense per Req 1b).
      - Otherwise remove the span between FORGE:BEGIN/END markers.

    The file itself is NEVER deleted, even when all sections are removed.
    Files without FORGE delimiters are NEVER modified.
    """
    outcome = outcome or CleanupOutcome(dry_run=dry_run)
    cmd_path = home / ".claude" / CLAUDE_MD_REL
    if not cmd_path.is_file() or cmd_path.is_symlink():
        return outcome

    text = cmd_path.read_text(encoding="utf-8")
    spans = _find_forge_sections(text)
    if not spans:
        return outcome

    span_index = {sid: (start, end) for sid, start, end in spans}
    keep_text = text
    removals: list[tuple[str, int, int]] = []

    for sid in section_ids:
        if sid not in span_index:
            outcome.sections_refused.append(
                (sid, cmd_path, "FORGE:BEGIN delimiter not found")
            )
            continue
        if not manifest_mod.is_attested(src_path, sid, mpath=manifest_mod.manifest_path(home)):
            outcome.sections_refused.append(
                (
                    sid,
                    cmd_path,
                    "review manually — unattested FORGE delimiter (not in manifest)",
                )
            )
            continue
        removals.append((sid, *span_index[sid]))

    if not removals:
        return outcome

    removals.sort(key=lambda r: r[1], reverse=True)
    if not dry_run:
        for sid, start, end in removals:
            keep_text = keep_text[:start] + keep_text[end:]
        cmd_path.write_text(keep_text, encoding="utf-8")

    for sid, _start, _end in removals:
        outcome.sections_removed.append((sid, cmd_path))
    return outcome


def cleanup(
    findings: list[Finding],
    home: Path,
    project_root: Path,
    src_path: str,
    consent: bool,
    dry_run: bool = False,
    backup_dir_override: Path | None = None,
    claude_md_section_ids: Iterable[str] | None = None,
) -> CleanupOutcome:
    """Run cleanup over the findings list (Reqs 5, 6, 7, 8, 15).

    Hard policy gates BEFORE any disk write:
      - consent=False → returns CleanupOutcome with nothing deleted (AC 6).
      - dry_run=True → walks the policy, fills outcome.refused / .deleted
        (as "would delete"), reports backup target, but writes nothing.

    On consent + not-dry_run:
      1. Backup snapshot created via backup.create_backup_dir().
      2. Per-finding policy check.
      3. Allowed finding → copy_file_into_backup; then unlink.
      4. CLAUDE.md sections handled separately via cleanup_claude_md_sections.
    """
    outcome = CleanupOutcome(dry_run=dry_run)

    if not consent and not dry_run:
        outcome.refused = [(f, "no operator consent (Req 5)") for f in findings]
        return outcome

    if not dry_run:
        outcome.backup_dir = backup_mod.create_backup_dir(backup_dir_override)

    for finding in findings:
        allowed, reason = _classify_finding_for_delete(finding, home, project_root)
        if not allowed:
            outcome.refused.append((finding, reason))
            continue
        if dry_run:
            outcome.deleted.append(finding)
            continue
        assert outcome.backup_dir is not None
        rel_label = finding.rel_path.replace("/", "_").replace("\\", "_")
        try:
            backup_mod.copy_file_into_backup(finding.abs_path, outcome.backup_dir, rel_label)
        except RuntimeError as e:
            outcome.refused.append((finding, f"backup-refused: {e}"))
            continue
        try:
            finding.abs_path.unlink()
        except OSError as e:
            outcome.refused.append((finding, f"unlink-failed: {e}"))
            continue
        outcome.deleted.append(finding)

    if claude_md_section_ids:
        cleanup_claude_md_sections(
            home=home,
            src_path=src_path,
            section_ids=claude_md_section_ids,
            dry_run=dry_run,
            outcome=outcome,
        )

    return outcome

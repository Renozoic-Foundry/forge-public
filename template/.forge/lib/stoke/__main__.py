"""Spec 431 — stoke package CLI entry point for new subcommands.

Existing stoke subcommands (direct-apply, audit, parse-sections, backup-create,
cleanup-old-backups, safe-stage, audit-commit, list-tasks, audit-gitignore)
continue to be served by the legacy single-file CLI at ../stoke.py — which
remains the binary invoked by forge-py / stoke.sh / stoke.ps1 wrappers.

New subcommands shipped by Spec 431 and dispatched from here OR from stoke.py:

  detect-legacy        Report-only legacy artifact detection. Honors
                       --skip-legacy-scan and --ack <id>.
  cleanup-legacy       Consent-gated cleanup. Requires --consent OR --dry-run
                       (mutually exclusive).
  manifest-init        Write the install manifest for the current project +
                       template (used by /forge-bootstrap and /forge-stoke
                       to record provenance).
  manifest-verify      Verify the manifest is readable + schema-version
                       compatible (used by /forge-stoke pre-flight).
  catalog-self-hash    Print the catalog_sha256 value for a catalog file
                       (CODEOWNERS-gated maintenance tool).

The legacy stoke.py forwards the new subcommands here so a single
forge-py stoke.py <new-subcommand> invocation works without changing the
binary path operators have memorized.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# When run as `python -m stoke` from the parent dir, package-relative imports
# work. When run as `python stoke/__main__.py`, set up sys.path.
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from stoke import catalog as catalog_mod  # type: ignore
    from stoke import cleanup as cleanup_mod  # type: ignore
    from stoke import legacy_detect as detect_mod  # type: ignore
    from stoke import manifest as manifest_mod  # type: ignore
    from stoke import reporter as reporter_mod  # type: ignore
else:
    from . import catalog as catalog_mod
    from . import cleanup as cleanup_mod
    from . import legacy_detect as detect_mod
    from . import manifest as manifest_mod
    from . import reporter as reporter_mod


def _read_copier_answers(project_root: Path) -> dict | None:
    """Read .copier-answers.yml from the project root. Returns None on missing
    or unreadable. Minimal parser — values are str/bool/list of str."""
    answers = project_root / ".copier-answers.yml"
    if not answers.is_file():
        return None
    try:
        text = answers.read_text(encoding="utf-8")
    except OSError:
        return None
    out: dict = {}
    current_list_key: str | None = None
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if line.startswith("  - ") and current_list_key is not None:
            value = line[4:].strip().strip('"').strip("'")
            out[current_list_key].append(value)
            continue
        if ":" in line and not line.startswith(" "):
            k, v = line.split(":", 1)
            k = k.strip()
            v = v.strip()
            if v == "":
                out[k] = []
                current_list_key = k
            else:
                current_list_key = None
                vstr = v.strip('"').strip("'")
                if vstr.lower() == "true":
                    out[k] = True
                elif vstr.lower() == "false":
                    out[k] = False
                else:
                    out[k] = vstr
    return out


def _load_acks(project_root: Path) -> set[str]:
    answers = _read_copier_answers(project_root)
    if not answers:
        return set()
    raw = answers.get("_acknowledged_legacy_artifacts") or []
    if isinstance(raw, list):
        return {str(x) for x in raw}
    return set()


def _persist_ack(project_root: Path, artifact_id: str) -> bool:
    """Append artifact_id to _acknowledged_legacy_artifacts in .copier-answers.yml.

    Idempotent. Returns True if the file was modified, False otherwise."""
    answers_path = project_root / ".copier-answers.yml"
    if not answers_path.is_file():
        return False
    text = answers_path.read_text(encoding="utf-8")
    existing = _load_acks(project_root)
    if artifact_id in existing:
        return False
    if "_acknowledged_legacy_artifacts:" in text:
        lines = text.splitlines()
        new_lines: list[str] = []
        inserted = False
        in_block = False
        for line in lines:
            new_lines.append(line)
            if line.strip().startswith("_acknowledged_legacy_artifacts:") and not inserted:
                in_block = True
                continue
            if in_block and not inserted:
                if line.startswith("  - "):
                    continue
                new_lines.insert(-1, f'  - "{artifact_id}"')
                inserted = True
                in_block = False
        if not inserted:
            new_lines.append(f'  - "{artifact_id}"')
        new_text = "\n".join(new_lines)
        if not new_text.endswith("\n"):
            new_text += "\n"
        answers_path.write_text(new_text, encoding="utf-8")
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += f'_acknowledged_legacy_artifacts:\n  - "{artifact_id}"\n'
        answers_path.write_text(text, encoding="utf-8")
    return True


def _enumerate_template_user_files(template_root: Path) -> set[str]:
    """List rel_paths the current template ships under ~/.claude/.

    Heuristic: template/.claude/ subtree mirrors what bootstrap installs under
    ~/.claude/. Returns rel_paths relative to .claude/.
    """
    base = template_root / ".claude"
    if not base.is_dir():
        return set()
    out: set[str] = set()
    for path in base.rglob("*"):
        if path.is_file():
            rel = path.relative_to(base).as_posix()
            out.add(rel)
    return out


def _src_path_from_answers(project_root: Path) -> str | None:
    answers = _read_copier_answers(project_root)
    if not answers:
        return None
    return answers.get("_src_path")


def cmd_detect_legacy(args: argparse.Namespace) -> int:
    if args.skip_legacy_scan:
        return 0
    project_root = Path(args.project_root).resolve()
    home = Path(args.home).resolve() if args.home else Path.home()
    template_root = Path(args.template_root).resolve() if args.template_root else None

    src_path = args.src_path or _src_path_from_answers(project_root) or ""
    acks = _load_acks(project_root) | set(args.ack or [])
    catalog_path = (
        Path(args.catalog).resolve()
        if args.catalog
        else (template_root / ".forge" / "data" / "legacy-signatures.yaml" if template_root else None)
    )

    current_user_files: set[str] | None
    if template_root and template_root.is_dir():
        current_user_files = _enumerate_template_user_files(template_root)
    else:
        current_user_files = None
        if template_root:
            print(
                f"WARN: template_root {template_root} unreachable — "
                f"falling back to manifest-only mode (Req 13).",
                file=sys.stderr,
            )

    report = detect_mod.detect_all(
        src_path=src_path,
        project_root=project_root,
        home=home,
        current_template_user_files=current_user_files,
        current_template_project_files=None,
        catalog_path=catalog_path,
        manifest_project_files=None,
        acks=acks,
    )

    if args.json:
        json.dump(
            {
                "manifest_orphans": [_finding_json(f) for f in report.manifest_orphans],
                "signature_matches": [_finding_json(f) for f in report.signature_matches],
                "project_orphans": [_finding_json(f) for f in report.project_orphans],
                "review_manually": [_finding_json(f) for f in report.review_manually],
                "diagnostics": report.diagnostics,
            },
            sys.stdout,
            indent=2,
            sort_keys=True,
        )
        print()
    else:
        print(reporter_mod.format_report(report))
    return 0


def _finding_json(f: detect_mod.Finding) -> dict:
    return {
        "artifact_id": f.artifact_id,
        "category": f.category,
        "rel_path": f.rel_path,
        "abs_path": str(f.abs_path),
        "detail": f.detail,
        "actionable": f.actionable,
    }


def cmd_cleanup_legacy(args: argparse.Namespace) -> int:
    if args.consent and args.dry_run:
        print("ERROR: --consent and --dry-run are mutually exclusive.", file=sys.stderr)
        return 2
    if not args.consent and not args.dry_run:
        print(
            "ERROR: cleanup-legacy requires --dry-run (preview) or --consent "
            "(perform deletion). No deletion happens without one of these.",
            file=sys.stderr,
        )
        return 2

    project_root = Path(args.project_root).resolve()
    home = Path(args.home).resolve() if args.home else Path.home()
    template_root = Path(args.template_root).resolve() if args.template_root else None
    src_path = args.src_path or _src_path_from_answers(project_root) or ""
    acks = _load_acks(project_root) | set(args.ack or [])
    catalog_path = (
        Path(args.catalog).resolve()
        if args.catalog
        else (template_root / ".forge" / "data" / "legacy-signatures.yaml" if template_root else None)
    )

    current_user_files: set[str] | None
    if template_root and template_root.is_dir():
        current_user_files = _enumerate_template_user_files(template_root)
    else:
        current_user_files = None

    report = detect_mod.detect_all(
        src_path=src_path,
        project_root=project_root,
        home=home,
        current_template_user_files=current_user_files,
        current_template_project_files=None,
        catalog_path=catalog_path,
        manifest_project_files=None,
        acks=acks,
    )

    findings = report.manifest_orphans + report.signature_matches + report.project_orphans
    backup_override = Path(args.backup_dir).resolve() if args.backup_dir else None

    outcome = cleanup_mod.cleanup(
        findings=findings,
        home=home,
        project_root=project_root,
        src_path=src_path,
        consent=bool(args.consent),
        dry_run=bool(args.dry_run),
        backup_dir_override=backup_override,
        claude_md_section_ids=args.claude_md_section or [],
    )

    for line in outcome.report_lines():
        print(line)
    return 0


def cmd_manifest_init(args: argparse.Namespace) -> int:
    """Write an install manifest entry for a project + template.

    Used by /forge-bootstrap (post-render) and /forge-stoke (post-apply).
    """
    project_root = Path(args.project_root).resolve()
    home = Path(args.home).resolve() if args.home else Path.home()
    src_path = args.src_path or _src_path_from_answers(project_root)
    if not src_path:
        print(
            "ERROR: --src-path required (or .copier-answers.yml must contain _src_path).",
            file=sys.stderr,
        )
        return 2

    template_root = Path(args.template_root).resolve() if args.template_root else None
    commit = args.commit or ""
    spec_id = args.spec_id or ""

    user_files: list[dict] = []
    user_base = home / ".claude"
    if template_root and template_root.is_dir() and user_base.is_dir():
        for rel in _enumerate_template_user_files(template_root):
            candidate = user_base / rel
            if candidate.is_file() and not candidate.is_symlink():
                user_files.append(
                    {
                        "rel_path": rel,
                        "sha256": manifest_mod.sha256_file(candidate),
                        "spec_id": spec_id,
                    }
                )

    sections: list[dict] = []
    claude_md = user_base / "CLAUDE.md"
    if claude_md.is_file() and not claude_md.is_symlink():
        text = claude_md.read_text(encoding="utf-8")
        for section_id, start, end in cleanup_mod._find_forge_sections(text):
            sections.append(
                {
                    "section_id": section_id,
                    "content_sha256": manifest_mod.sha256_bytes(
                        text[start:end].encode("utf-8")
                    ),
                    "spec_id": spec_id,
                }
            )

    mp = manifest_mod.write_install(
        src_path=src_path,
        commit=commit,
        files=user_files,
        claude_md_sections=sections,
        spec_id=spec_id,
    )
    print(
        f"Manifest updated: {mp} (src_path={src_path}, files={len(user_files)}, "
        f"sections={len(sections)})"
    )
    return 0


def cmd_manifest_verify(args: argparse.Namespace) -> int:
    home = Path(args.home).resolve() if args.home else Path.home()
    try:
        data = manifest_mod.read(manifest_mod.manifest_path(home))
    except manifest_mod.ManifestSchemaUnsupported as e:
        manifest_mod.report_unsupported_schema(e)
        return 1
    except RuntimeError as e:
        print(f"ERROR (manifest): {e}", file=sys.stderr)
        return 1
    print(
        f"Manifest OK: schema_version={data['schema_version']}, "
        f"installs={len(data['installs'])}"
    )
    return 0


def cmd_catalog_self_hash(args: argparse.Namespace) -> int:
    """Compute and optionally write the catalog_sha256 field.

    Modes:
      --print  → compute and print to stdout (default).
      --write  → rewrite the catalog file with the computed value substituted
                 in place of the current value (CODEOWNERS-gated maintenance).
    """
    path = Path(args.catalog).resolve()
    if not path.is_file():
        print(f"ERROR: catalog not found at {path}", file=sys.stderr)
        return 2
    text = path.read_text(encoding="utf-8")

    current = ""
    for line in text.splitlines():
        if line.strip().startswith("catalog_sha256:"):
            current = line.split(":", 1)[1].strip().strip('"').strip("'")
            break
    new_hash = catalog_mod.compute_catalog_self_hash(text, current_value=current)

    if args.write:
        if current:
            text = text.replace(current, new_hash, 1)
        else:
            text = f'catalog_sha256: "{new_hash}"\n' + text
        path.write_text(text, encoding="utf-8")
        print(f"Wrote catalog_sha256: {new_hash[:8]}... to {path}")
    else:
        print(new_hash)
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="stoke", description="Spec 431 stoke package CLI")
    sub = p.add_subparsers(dest="command", required=True)

    d = sub.add_parser("detect-legacy", help="Report-only legacy artifact detection")
    d.add_argument("--project-root", default=".")
    d.add_argument("--home", default="")
    d.add_argument("--template-root", default="")
    d.add_argument("--src-path", default="")
    d.add_argument("--catalog", default="")
    d.add_argument("--ack", action="append", default=[])
    d.add_argument("--skip-legacy-scan", action="store_true")
    d.add_argument("--json", action="store_true")
    d.set_defaults(func=cmd_detect_legacy)

    c = sub.add_parser("cleanup-legacy", help="Consent-gated legacy cleanup")
    c.add_argument("--project-root", default=".")
    c.add_argument("--home", default="")
    c.add_argument("--template-root", default="")
    c.add_argument("--src-path", default="")
    c.add_argument("--catalog", default="")
    c.add_argument("--ack", action="append", default=[])
    c.add_argument("--consent", action="store_true")
    c.add_argument("--dry-run", action="store_true")
    c.add_argument("--backup-dir", default="")
    c.add_argument("--claude-md-section", action="append", default=[])
    c.set_defaults(func=cmd_cleanup_legacy)

    m = sub.add_parser("manifest-init", help="Write install manifest for project + template")
    m.add_argument("--project-root", default=".")
    m.add_argument("--home", default="")
    m.add_argument("--template-root", default="")
    m.add_argument("--src-path", default="")
    m.add_argument("--commit", default="")
    m.add_argument("--spec-id", default="")
    m.set_defaults(func=cmd_manifest_init)

    v = sub.add_parser("manifest-verify", help="Verify manifest schema compatibility")
    v.add_argument("--home", default="")
    v.set_defaults(func=cmd_manifest_verify)

    s = sub.add_parser(
        "catalog-self-hash",
        help="Compute (or rewrite) catalog_sha256 field for legacy-signatures.yaml",
    )
    s.add_argument("catalog")
    s.add_argument("--write", action="store_true")
    s.set_defaults(func=cmd_catalog_self_hash)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

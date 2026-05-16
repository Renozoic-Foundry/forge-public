"""Spec 431 — legacy signature catalog (migration shim, hash-pinned).

The catalog covers ONLY pre-manifest legacy artifacts (files placed under
~/.claude/ before the install manifest was introduced). It is a bounded
migration shim — not a perpetual heuristic. Each entry carries a wall-clock
deprecation_date enforced by a future retirement spec regardless of pilot
completeness (Req 16, AC 23).

Catalog schema (template/.forge/data/legacy-signatures.yaml):

    # FORGE legacy signature catalog.
    # CODEOWNERS-gated; changes require @forge-template-owners review.
    # See ADR-431 for the maintenance model.

    catalog_sha256: "<64-char hex; self-hash with this field zeroed>"
    entries:
      - name: "claude-commands-forge-old"
        rel_path: ".claude/commands/forge.md"
        expected_sha256: "<64-char hex>"
        deprecation_date: "2026-11-15"
        notes: "Pre-Spec-431 forge.md placed by early-pilot bootstrap"

Detection contract (Req 3, 4; AC 3, 4, 9):
  - Self-hash MUST verify before any entry is consulted.
  - Per-entry match is exact-sha256 only. Mismatches are NOT reported.
  - Self-hash invalid → catalog skipped with diagnostic; manifest detection
    continues.
  - Entries past deprecation_date emit catalog-entry-deprecated warning and
    still function (until a future spec removes them, per ADR-431).
"""
from __future__ import annotations

import hashlib
import io
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any

ZERO_HASH = "0" * 64


@dataclass
class CatalogEntry:
    name: str
    rel_path: str
    expected_sha256: str
    deprecation_date: str
    notes: str = ""


@dataclass
class CatalogLoadResult:
    entries: list[CatalogEntry]
    diagnostics: list[str]
    valid: bool


def default_catalog_path(template_root: Path) -> Path:
    """Path to the catalog inside the template tree."""
    return template_root / ".forge" / "data" / "legacy-signatures.yaml"


def _load_yaml(text: str) -> dict[str, Any]:
    """Load YAML. Prefer PyYAML; fall back to a minimal hand parser sufficient
    for this catalog's flat key:value structure + entries list."""
    try:
        import yaml  # type: ignore

        return yaml.safe_load(text) or {}
    except ImportError:
        return _minimal_yaml_parse(text)


def _minimal_yaml_parse(text: str) -> dict[str, Any]:
    """Tiny parser for the catalog's exact shape.

    Handles:
      catalog_sha256: "<hex>"
      entries:
        - name: "..."
          rel_path: "..."
          expected_sha256: "..."
          deprecation_date: "..."
          notes: "..."
    """
    out: dict[str, Any] = {"entries": []}
    current_entry: dict[str, Any] | None = None
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if indent == 0 and stripped.startswith("catalog_sha256:"):
            value = stripped.split(":", 1)[1].strip().strip('"').strip("'")
            out["catalog_sha256"] = value
        elif indent == 0 and stripped.startswith("entries:"):
            out["entries"] = []
        elif stripped.startswith("- "):
            if current_entry is not None:
                out["entries"].append(current_entry)
            current_entry = {}
            kv = stripped[2:]
            if ":" in kv:
                k, v = kv.split(":", 1)
                current_entry[k.strip()] = v.strip().strip('"').strip("'")
        elif ":" in stripped and current_entry is not None:
            k, v = stripped.split(":", 1)
            current_entry[k.strip()] = v.strip().strip('"').strip("'")
    if current_entry is not None:
        out["entries"].append(current_entry)
    return out


def _compute_self_hash(text: str) -> str:
    """Compute sha256 of catalog with catalog_sha256 value replaced by 64 zeros.

    Self-hash policy: substitute the value, not the field, so the field's
    presence does not affect the hash. Operators regenerate by running:

        canonical = text.replace(stored_hash, ZERO_HASH)
        new_hash = sha256(canonical)
    """
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _canonicalize_for_self_hash(text: str, stored_hash: str) -> str:
    """Return text with the stored hash value replaced by 64 zeros.

    Self-hash is computed over this canonical form so that updating the hash
    field after a content change does not change the hash recursively.
    """
    if not stored_hash or stored_hash == ZERO_HASH:
        return text
    return text.replace(stored_hash, ZERO_HASH, 1)


def compute_catalog_self_hash(text: str, current_value: str = "") -> str:
    """Public helper for tooling that regenerates the catalog_sha256 field.

    Operators editing the catalog set catalog_sha256: "<64 zeros>", compute
    this function on the resulting text, then write the result back.
    """
    canonical = _canonicalize_for_self_hash(text, current_value or ZERO_HASH)
    return _compute_self_hash(canonical)


def load(catalog_path: Path) -> CatalogLoadResult:
    """Load + verify the catalog. Always returns a result; .valid signals
    whether entries should be consulted.

    Failure modes (Req 4, AC 9):
      - File missing: valid=True, entries=[] (no catalog = no migration shim)
      - Parse error: valid=False, diagnostic
      - Self-hash mismatch: valid=False, diagnostic — entries NOT consulted
      - Malformed entry (missing required field): entry dropped, diagnostic,
        rest of catalog still loaded
    """
    diagnostics: list[str] = []

    if not catalog_path.exists():
        return CatalogLoadResult(entries=[], diagnostics=[], valid=True)

    try:
        text = catalog_path.read_text(encoding="utf-8")
    except OSError as e:
        return CatalogLoadResult(
            entries=[],
            diagnostics=[f"catalog-read-failed: {catalog_path}: {e}"],
            valid=False,
        )

    try:
        data = _load_yaml(text)
    except Exception as e:
        return CatalogLoadResult(
            entries=[],
            diagnostics=[f"catalog-parse-failed: {catalog_path}: {e}"],
            valid=False,
        )

    stored_hash = (data.get("catalog_sha256") or "").lower().strip()
    if not stored_hash:
        diagnostics.append(
            f"catalog-self-hash-missing: {catalog_path} has no catalog_sha256 "
            f"field — catalog skipped (CODEOWNERS gate bypassed?)"
        )
        return CatalogLoadResult(entries=[], diagnostics=diagnostics, valid=False)

    canonical = _canonicalize_for_self_hash(text, stored_hash)
    computed = _compute_self_hash(canonical)
    if computed != stored_hash:
        diagnostics.append(
            f"catalog-self-hash-mismatch: {catalog_path} catalog_sha256 stored="
            f"{stored_hash[:8]}... computed={computed[:8]}... — catalog skipped"
        )
        return CatalogLoadResult(entries=[], diagnostics=diagnostics, valid=False)

    raw_entries = data.get("entries") or []
    today = date.today().isoformat()
    entries: list[CatalogEntry] = []
    for raw in raw_entries:
        try:
            entry = CatalogEntry(
                name=str(raw["name"]),
                rel_path=str(raw["rel_path"]),
                expected_sha256=str(raw["expected_sha256"]).lower(),
                deprecation_date=str(raw["deprecation_date"]),
                notes=str(raw.get("notes", "")),
            )
        except (KeyError, TypeError) as e:
            diagnostics.append(f"catalog-entry-malformed: {raw!r}: {e}")
            continue
        if len(entry.expected_sha256) != 64:
            diagnostics.append(
                f"catalog-entry-bad-hash: {entry.name}: "
                f"expected_sha256 must be 64-char hex"
            )
            continue
        if entry.deprecation_date < today:
            diagnostics.append(
                f"catalog-entry-deprecated: {entry.name} "
                f"(deprecation_date={entry.deprecation_date}, today={today}) — "
                f"entry still functions; remove via future retirement spec"
            )
        entries.append(entry)

    return CatalogLoadResult(entries=entries, diagnostics=diagnostics, valid=True)


def match_file(home: Path, entry: CatalogEntry) -> tuple[bool, Path | None]:
    """Check whether ~/.claude/<entry.rel_path> exists and matches the entry's
    expected_sha256 exactly (Req 3, AC 3, AC 4).

    Returns (matched, absolute_path). On any error → (False, path).
    """
    target = home / ".claude" / entry.rel_path
    if not target.is_file():
        return False, target
    if target.is_symlink():
        return False, target
    try:
        h = hashlib.sha256()
        with open(target, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return h.hexdigest() == entry.expected_sha256, target
    except OSError:
        return False, target


def emit_diagnostics(diags: list[str], stream=sys.stderr) -> None:
    for d in diags:
        print(f"WARN (catalog): {d}", file=stream)

#!/usr/bin/env python3
"""FORGE consumer doctrine delivery — managed-section generator (Spec 640, ADR-640).

Delivers FORGE's authorization core (Priority ordering, Requires Confirmation,
Authorization-required commands, Prohibited) to a consumer's AGENTS.md/CLAUDE.md as a
delimited, version-stamped, regenerable block — extracted live from the canonical
`D:\\forge` AGENTS.md at generation time (Req 5: no second hand-maintained copy).

Marker format (a single managed block, identified by `id`):

    <!-- FORGE:DOCTRINE-BEGIN id=<id> version=<X> sha256=<64-hex> -->
    ...generated content...
    <!-- FORGE:DOCTRINE-END id=<id> -->

`version` is the FORGE plugin version the block was generated from (e.g. from
`.claude-plugin/plugin.json`). `sha256` hashes the content between the marker lines
*as generated* — comparing it against the LIVE content at the next generation is how
a hand-edit inside the markers is detected (Req 3 / AC3) without a second copy of the
"expected" text anywhere.

First-time placement uses an anchor comment the target file already carries:

    <!-- FORGE:DOCTRINE-ANCHOR id=<id> -->

which is replaced in-place by the full BEGIN/content/END block. Everything outside the
matched span (anchor or existing block) is left byte-identical (Req 2 / AC2) because the
splice is a single `re.sub` over the exact matched region — nothing else in the string is
touched.

Subcommands:
    generate       Render the block from --source and splice it into --target.
    check          Report NONE / OK / DRIFT / CONFLICT for a target's block (no writes).
    parity-check   AC1b gate — diff --upstream's authorization surface (Requires
                   Confirmation, Authorization-required commands, Prohibited, Priority
                   ordering) against --downstream's full text; FAIL on anything missing.

Stdlib only (ADR-359).
"""
from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

DEFAULT_ID = "authorization-core"

# --- section headers in the canonical AGENTS.md (Boundaries + Priority ordering) -------
_HEADERS = {
    "priority": r"^Priority ordering \(read first",
    "requires_confirmation": r"^Requires Confirmation$",
    "authorization_required": r"^Authorization-required commands$",
    "prohibited": r"^Prohibited$",
}
# _HEADERS values are matched against the header TEXT with leading '#'s and whitespace
# already stripped (see _section_body) — e.g. "### Requires Confirmation" -> "Requires Confirmation".


class DoctrineError(Exception):
    """Extraction or splice failure — always fails closed (no partial/guessed output)."""


def _section_body(text: str, header_pattern: str) -> str:
    """Lines between a markdown header matching header_pattern and the next header.
    header_pattern is matched against the header TEXT ONLY (leading '#'s and the
    whitespace after them stripped) so patterns need not account for heading level."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        hm = re.match(r"^#{1,6}\s+(.*)$", line)
        if hm and re.search(header_pattern, hm.group(1)):
            start = i + 1
            break
    if start is None:
        raise DoctrineError(f"canonical header not found: {header_pattern!r}")
    end = len(lines)
    for j in range(start, len(lines)):
        if re.match(r"^#{1,6}\s", lines[j]):
            end = j
            break
    return "\n".join(lines[start:end])


def _bullets(body: str) -> list[str]:
    """Top-level '- ' bullets, joining indented continuation lines; stops at the first
    column-0 non-bullet paragraph encountered AFTER at least one bullet was collected."""
    items: list[str] = []
    cur: list[str] | None = None
    for raw in body.splitlines():
        if raw.startswith("- "):
            if cur is not None:
                items.append(" ".join(cur))
            cur = [raw[2:].strip()]
        elif raw.startswith("  ") and cur is not None and raw.strip():
            cur.append(raw.strip())
        elif raw.strip() == "":
            continue
        else:
            if cur is not None:
                items.append(" ".join(cur))
                cur = None
            if items:
                break
    if cur is not None:
        items.append(" ".join(cur))
    return items


def extract_authorization_surface(agents_md_text: str) -> dict:
    """Extract the four authorization-surface lists (Req 1b's parity scope) from a
    canonical AGENTS.md text. Raises DoctrineError if any expected list is empty or a
    header is missing — fails closed rather than emitting a silently-incomplete block."""
    priority_body = _section_body(agents_md_text, _HEADERS["priority"])
    priority_items = _bullets(priority_body)
    closer_match = re.search(r'^"Ship fast".*$', priority_body, re.MULTILINE)
    closer = closer_match.group(0).strip() if closer_match else ""

    result = {
        "priority": priority_items,
        "priority_closer": closer,
        "requires_confirmation": _bullets(_section_body(agents_md_text, _HEADERS["requires_confirmation"])),
        "authorization_required": _bullets(_section_body(agents_md_text, _HEADERS["authorization_required"])),
        "prohibited": _bullets(_section_body(agents_md_text, _HEADERS["prohibited"])),
    }
    for key in ("priority", "requires_confirmation", "authorization_required", "prohibited"):
        if not result[key]:
            raise DoctrineError(f"extracted list '{key}' is empty — canonical AGENTS.md structure changed")
    return result


AUTONOMY_ID = "autonomy-config"


def extract_autonomy_surface(agents_md_text: str) -> dict:
    """Extract the autonomy OPERATING config (Spec 649 AC2a) from a canonical AGENTS.md.

    This is the second managed block. It is deliberately NOT the authorization surface:
    `authorization-core` carries what an agent may not do; this carries the L0-L4 ladder and
    the `auto_progression` chain table that `/implement` Step 9f reads to decide whether to
    offer a chain. A consumer that declares an autonomy level but receives no operating config
    has a level that cannot mean anything — Step 9f matches against an absent block and the
    chain is never offered (measured: a clean HEAD render carried 0 of both).

    Fails closed like its sibling: a missing table or block raises rather than emitting a
    partial config, because a half-present `auto_progression` is worse than none (it would
    match some levels and silently not others).
    """
    lines = agents_md_text.splitlines()

    # L0-L4 table rows: markdown rows whose first cell is **L<n>**.
    table_rows = [ln for ln in lines if re.match(r"^\|\s*\*\*L[0-4]\*\*\s*\|", ln)]

    # The auto_progression YAML block: from its key line to the end of that fenced block.
    auto_block, in_auto, fence = [], False, False
    for ln in lines:
        if not in_auto and re.match(r"^auto_progression:", ln):
            in_auto = True
            auto_block.append(ln)
            continue
        if in_auto:
            if ln.startswith("```"):
                fence = True
                break
            auto_block.append(ln)
    _ = fence

    cur = ""
    m = re.search(r"^Current autonomy level: \*\*(L[0-4])\*\*", agents_md_text, re.MULTILINE)
    if m:
        cur = m.group(1)

    result = {"table_rows": table_rows, "auto_progression": auto_block, "current_level": cur}
    if not table_rows:
        raise DoctrineError("no L0-L4 autonomy table rows found — canonical AGENTS.md structure changed")
    if not auto_block:
        raise DoctrineError("no auto_progression block found — canonical AGENTS.md structure changed")
    return result


def render_autonomy_config(surface: dict) -> str:
    """Consumer-facing autonomy operating config (Spec 649 AC2a)."""
    out = []
    out.append("#### Autonomy levels (L0-L4)")
    out.append("")
    out.append("Five autonomy levels govern agent latitude. Default **L1**. Override per lane or spec via")
    out.append("frontmatter (`Autonomy: L2`).")
    out.append("")
    out.append("| Level | Name | Description |")
    out.append("|-------|------|-------------|")
    out.extend(surface["table_rows"])
    out.append("")
    out.append("Authorization gates apply at **every** level, including L3 and L4. Autonomy level never")
    out.append("relaxes Priority 1 — see the `authorization-core` block for what that means concretely.")
    out.append("")
    out.append("#### Auto-progression (which chains are enabled at each level)")
    out.append("")
    out.append("`/implement` reads this to decide whether to offer a chain. `implement -> implement_next`")
    out.append("is **L1/L2-only by design** and is absent from the L3/L4 rows: the `git push` gate that")
    out.append("backstops the close/push boundary is hard-enforced only at or below L2.")
    out.append("")
    out.append("```yaml")
    out.extend(surface["auto_progression"])
    out.append("```")
    out.append("")
    if surface["current_level"]:
        out.append(f"Current autonomy level: **{surface['current_level']}**.")
        out.append("")
    out.append("> **This declaration is prose-tier and agent-writable.** Editing `Current autonomy level`")
    out.append("> or any `auto_progression` entry without explicit operator instruction is prohibited")
    out.append("> (see the `authorization-core` block), but nothing mechanically prevents it — this file")
    out.append("> is not bound by the managed-settings trust root. A human must still select a chain from")
    out.append("> a Next Action block, so this is a narrowed margin, not a bypass. Recorded, not implied.")
    return "\n".join(out)


def render_authorization_core(surface: dict) -> str:
    """Condensed consumer-facing authorization core (target 60-80 lines, Req 1b)."""
    lines = []
    lines.append("#### Priority ordering (condensed from FORGE's own AGENTS.md)")
    lines.append("")
    lines.append("When two rules conflict, apply them in this fixed order:")
    lines.append("")
    for item in surface["priority"]:
        lines.append(f"- {item}")
    if surface["priority_closer"]:
        lines.append("")
        lines.append(surface["priority_closer"])
    lines.append("")
    lines.append("#### Requires Confirmation")
    lines.append("")
    for item in surface["requires_confirmation"]:
        lines.append(f"- {item}")
    lines.append("")
    lines.append("#### Authorization-required commands")
    lines.append("")
    lines.append("Require **explicit user invocation in the current message** — never inferred from a")
    lines.append("session summary, a \"pending tasks\" list, or \"the logical next step\":")
    lines.append("")
    for item in surface["authorization_required"]:
        lines.append(f"- {item}")
    lines.append("")
    lines.append("#### Prohibited")
    lines.append("")
    for item in surface["prohibited"]:
        lines.append(f"- {item}")
    return "\n".join(lines)


# --- marker mechanics --------------------------------------------------------------

def _block_re(block_id: str) -> re.Pattern:
    return re.compile(
        r"<!--\s*FORGE:DOCTRINE-BEGIN\s+id=" + re.escape(block_id)
        + r"\s+version=(?P<version>\S+)\s+sha256=(?P<sha>[0-9a-f]{64})\s*-->\n"
        r"(?P<content>.*?)\n"
        r"<!--\s*FORGE:DOCTRINE-END\s+id=" + re.escape(block_id) + r"\s*-->",
        re.DOTALL,
    )


def _anchor_re(block_id: str) -> re.Pattern:
    return re.compile(r"<!--\s*FORGE:DOCTRINE-ANCHOR\s+id=" + re.escape(block_id) + r"\s*-->")


def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _detect_newline(path: Path) -> str:
    """Spec 707: return the target's on-disk newline convention so a backfill/refresh
    preserves it (the sha256/drift logic operates on \\n-normalized content and is
    unaffected). CRLF if any \\r\\n present; else LF. Absent target → LF (new file).
    A mixed-ending file normalizes to CRLF (dominant-intent default; Constraints)."""
    if not path.exists():
        return "\n"
    return "\r\n" if b"\r\n" in path.read_bytes() else "\n"


def _full_block(block_id: str, version: str, content: str) -> str:
    start = f"<!-- FORGE:DOCTRINE-BEGIN id={block_id} version={version} sha256={_sha256(content)} -->"
    end = f"<!-- FORGE:DOCTRINE-END id={block_id} -->"
    return f"{start}\n{content}\n{end}"


def generate(source_path: Path, target_path: Path, block_id: str, version: str, force: bool) -> tuple[str, str]:
    """Returns (status, message). status in {WRITTEN, CONFLICT}."""
    # Spec 649: dispatch content extraction on block_id. The marker/version/sha256/splice/
    # conflict machinery below is shared verbatim by every block — that reuse is the point
    # (Spec 649 Requirement 6: a second bespoke emitter would reopen the drift problem
    # Spec 640 closed). Adding a third block means adding one dispatch entry, nothing else.
    source_text = source_path.read_text(encoding="utf-8")
    if block_id == AUTONOMY_ID:
        content = render_autonomy_config(extract_autonomy_surface(source_text))
    else:
        content = render_authorization_core(extract_authorization_surface(source_text))
    new_block = _full_block(block_id, version, content)

    target_text = target_path.read_text(encoding="utf-8") if target_path.exists() else ""
    nl = _detect_newline(target_path)  # Spec 707: preserve the target's newline convention
    block_re = _block_re(block_id)
    m = block_re.search(target_text)

    if m:
        live_content = m.group("content")
        recorded_sha = m.group("sha")
        live_sha = _sha256(live_content)
        if live_sha != recorded_sha and not force:
            return "CONFLICT", (
                f"hand-edit detected inside managed block id={block_id} in {target_path} "
                f"(live sha256={live_sha} != recorded sha256={recorded_sha}). "
                "Not overwritten — resolve manually or re-run with --force."
            )
        new_text = target_text[: m.start()] + new_block + target_text[m.end():]
        target_path.write_text(new_text, encoding="utf-8", newline=nl)
        return "WRITTEN", f"regenerated managed block id={block_id} in {target_path} (version={version})"

    anchor_re = _anchor_re(block_id)
    am = anchor_re.search(target_text)
    if am:
        new_text = target_text[: am.start()] + new_block + target_text[am.end():]
        target_path.write_text(new_text, encoding="utf-8", newline=nl)
        return "WRITTEN", f"placed managed block id={block_id} in {target_path} at anchor (version={version})"

    sep = "" if (not target_text or target_text.endswith("\n\n")) else ("\n" if target_text.endswith("\n") else "\n\n")
    new_text = target_text + sep + new_block + "\n"
    target_path.write_text(new_text, encoding="utf-8", newline=nl)
    return "WRITTEN", f"appended managed block id={block_id} to {target_path} (version={version})"


def check(target_path: Path, block_id: str, installed_version: str) -> tuple[str, str]:
    """Returns (status, detail). status in {NONE, OK, DRIFT, CONFLICT}. Never writes."""
    if not target_path.exists():
        return "NONE", f"{target_path} does not exist"
    text = target_path.read_text(encoding="utf-8")
    m = _block_re(block_id).search(text)
    if not m:
        return "NONE", f"no managed doctrine block id={block_id} found in {target_path}"
    live_sha = _sha256(m.group("content"))
    if live_sha != m.group("sha"):
        return "CONFLICT", f"managed block id={block_id} in {target_path} was hand-edited since generation"
    marker_version = m.group("version")
    if _version_lt(marker_version, installed_version):
        return "DRIFT", f"managed block id={block_id} in {target_path} is version {marker_version}; installed plugin is {installed_version}"
    return "OK", f"managed block id={block_id} in {target_path} is current (version {marker_version})"


def _version_tuple(v: str) -> tuple:
    parts = re.split(r"[.\-]", v)
    out = []
    for p in parts:
        out.append(int(p)) if p.isdigit() else out.append(p)
    return tuple(out)


def _version_lt(a: str, b: str) -> bool:
    try:
        ta, tb = _version_tuple(a), _version_tuple(b)
        # Compare element-wise as far as both sides agree in type; fall back to string compare on mismatch.
        for x, y in zip(ta, tb):
            if type(x) is type(y):
                if x != y:
                    return x < y
            else:
                return str(a) < str(b)
        return len(ta) < len(tb)
    except (ValueError, TypeError):
        return a < b


# --- AC1b authorization-parity gate --------------------------------------------------

def _normalize(s: str) -> str:
    s = re.sub(r"[`*]", "", s)
    s = re.sub(r"\s+", " ", s).strip().lower()
    return s


def parity_check(upstream_text: str, downstream_text: str) -> tuple[bool, list[str]]:
    surface = extract_authorization_surface(upstream_text)
    norm_downstream = _normalize(downstream_text)
    missing = []
    for category in ("priority", "requires_confirmation", "authorization_required", "prohibited"):
        for item in surface[category]:
            if _normalize(item) not in norm_downstream:
                missing.append(f"{category}: {item}")
    return (len(missing) == 0), missing


# --- CLI ------------------------------------------------------------------------------

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="FORGE consumer doctrine delivery (Spec 640)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("generate", help="render + splice the managed block into a target file")
    g.add_argument("--source", required=True, type=Path, help="canonical AGENTS.md path")
    g.add_argument("--target", required=True, type=Path, help="consumer file to write")
    g.add_argument("--id", default=DEFAULT_ID)
    g.add_argument("--version", required=True, help="FORGE version this block is generated from")
    g.add_argument("--force", action="store_true", help="overwrite even if a hand-edit is detected")

    c = sub.add_parser("check", help="report drift/conflict status without writing")
    c.add_argument("--target", required=True, type=Path)
    c.add_argument("--id", default=DEFAULT_ID)
    c.add_argument("--installed-version", required=True)

    p = sub.add_parser("parity-check", help="AC1b — diff upstream authorization surface vs a generated file")
    p.add_argument("--upstream", required=True, type=Path)
    p.add_argument("--downstream", required=True, type=Path)

    args = ap.parse_args(argv)

    try:
        if args.cmd == "generate":
            status, msg = generate(args.source, args.target, args.id, args.version, args.force)
            print(f"{status} {msg}")
            return 0 if status == "WRITTEN" else 3
        if args.cmd == "check":
            status, msg = check(args.target, args.id, args.installed_version)
            print(f"{status} {msg}")
            return 0
        if args.cmd == "parity-check":
            ok, missing = parity_check(
                args.upstream.read_text(encoding="utf-8"),
                args.downstream.read_text(encoding="utf-8"),
            )
            if ok:
                print("PASS — every upstream authorization item is present downstream")
                return 0
            print(f"FAIL — {len(missing)} upstream authorization item(s) missing downstream:")
            for item in missing:
                print(f"  - {item}")
            return 1
    except DoctrineError as e:
        print(f"ERROR {e}", file=sys.stderr)
        return 2
    return 2


if __name__ == "__main__":
    sys.exit(main())

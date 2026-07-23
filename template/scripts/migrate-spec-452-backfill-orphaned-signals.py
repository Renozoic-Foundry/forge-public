#!/usr/bin/env python3
"""Spec 452 — backfill orphaned session-log EA/CI entries into persistent logs.

Scans session logs (docs/sessions/YYYY-MM-DD-NNN.md) for `## Error autopsies`
and `## Chat insights` sections, extracts `### EA-NNN` / `### CI-NNN` blocks,
and propagates any entry missing from the persistent logs:

  EA-NNN -> docs/sessions/error-log.md    (verbatim block + `- Session:` line)
  CI-NNN -> docs/sessions/insights-log.md (verbatim block + `- Session:` line)
  both   -> docs/sessions/signals.md      (one-line SIG-<spec>-EA/CI-<ID> stub)

This script is both the one-shot backfill (Spec 452 Req 3/4) and the
propagation engine invoked by /close Step 5d (`--apply --session-only=<id>
--spec=<closing spec>`) — a single parser implementation keeps the close-time
path and the migration path from drifting.

Propagation invariant: every EA/CI entry in a session log MUST also exist in
the matching persistent log. See docs/process-kit/signal-capture-conventions.md.

Stdlib-only (Spec 401 wrapper invariant). Default mode is --dry-run.

Exit codes: 0 = success; 1 = write error; 2 = parse/malformed-block error.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SESSION_LOG_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-\d{3}\.md$")
SESSION_DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-\d{3}$")  # filename-date prefix
SINCE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
SECTION_RE = re.compile(r"^##\s+(Error autopsies|Chat insights)\b(.*)$")
# IDs are preserved verbatim, including spec-scoped sub-ID forms like
# CI-429-A or EA-423-01 (the no-renumbering constraint). Separators observed
# in the wild: ':', em/en dash, '-', '|'.
ENTRY_RE = re.compile(r"^###\s+((EA|CI)-\d+(?:-[A-Za-z0-9]+)*)\s*[:—–|-]\s*(.+)$")
ATTEMPT_RE = re.compile(r"^###\s+(EA|CI)-")
FIELD_RE = re.compile(r"^\s*-\s+\S")

# Spec 472 — structured classification fields copied verbatim onto the
# signals.md stub so /evolve Step 8 can cluster on them. Order is the stub's
# emission order; matching against a source block is case-insensitive on the
# label but the copied line is preserved byte-for-byte. `Type` is the Spec 267
# signal axis; the three classification fields are the Spec 267 retrieval axes.
STUB_FIELD_LABELS = (
    "Type",
    "Root-cause category",
    "Wrong assumption",
    "Evidence-gate coverage",
)
# A body line is a candidate stub field when it is a `- <Label>:` bullet whose
# label matches one of STUB_FIELD_LABELS (case-insensitive, surrounding space
# tolerant). Captures the whole line for verbatim copy.
STUB_FIELD_RE = re.compile(
    r"^\s*-\s+(" + "|".join(re.escape(lbl) for lbl in STUB_FIELD_LABELS) + r")\s*:",
    re.IGNORECASE,
)

ERROR_LOG = "error-log.md"
INSIGHTS_LOG = "insights-log.md"
SIGNALS_LOG = "signals.md"

LOG_HEADERS = {
    ERROR_LOG: "# Error Log\n\nPersistent log of all error autopsies across sessions. Format: EA-NNN.\n",
    INSIGHTS_LOG: "# Insights Log\n\nPersistent log of all chat insights across sessions. Format: CI-NNN.\n",
    SIGNALS_LOG: "# Signals Log\n\nAll signals captured via /close, /note, and session retrospectives.\n",
}


class MalformedBlockError(Exception):
    """A block inside an EA/CI section violates the entry contract."""


def stub_fields(block: list[str]) -> list[str]:
    """Extract the Spec 472 structured stub fields from a source block, verbatim.

    Returns the matching `- <Label>: <value>` lines (left-stripped to a single
    leading bullet) in STUB_FIELD_LABELS order, deduplicated by label so a block
    that repeats a label contributes only its first occurrence. Pre-Spec-267
    blocks that carry none of these fields yield [] — the caller then emits the
    historical one-line stub (graceful degradation; never invents values).
    """
    found: dict[str, str] = {}
    for raw in block[1:]:
        m = STUB_FIELD_RE.match(raw)
        if not m:
            continue
        label_key = m.group(1).lower()
        if label_key in found:
            continue  # first occurrence wins; preserve source order via labels
        # Normalize only the leading indentation/bullet so the copied line is a
        # clean top-level bullet under the stub heading; value is byte-verbatim.
        found[label_key] = "- " + raw.lstrip().lstrip("-").lstrip()
    return [found[lbl.lower()] for lbl in STUB_FIELD_LABELS if lbl.lower() in found]


def parse_session_log(path: Path) -> list[dict]:
    """Extract EA/CI entry blocks from one session log.

    Returns a list of {kind, id, title, block, session} dicts. Raises
    MalformedBlockError (named diagnostic) on contract violations so /close
    Step 5d can FAIL before the status transition (Spec 452 Req 1f / AC 10).
    """
    lines = path.read_text(encoding="utf-8").splitlines()
    session_id = path.stem
    entries: list[dict] = []
    section = None  # None | "EA" | "CI"
    in_fence = in_comment = False
    i = 0
    while i < len(lines):
        line = lines[i]
        # Template examples live inside code fences and HTML comments —
        # never parse those as entries (e.g. a pasted '### EA-NNN: <title>').
        if in_comment:
            if "-->" in line:
                in_comment = False
            i += 1
            continue
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            i += 1
            continue
        if in_fence:
            i += 1
            continue
        if line.lstrip().startswith("<!--") and "-->" not in line:
            in_comment = True
            i += 1
            continue
        m = SECTION_RE.match(line)
        if m:
            section = "EA" if m.group(1) == "Error autopsies" else "CI"
            i += 1
            continue
        if line.startswith("## "):
            section = None
            i += 1
            continue
        if section and ATTEMPT_RE.match(line):
            em = ENTRY_RE.match(line)
            if not em:
                # An EA-/CI-prefixed heading that fails the entry contract is a
                # propagation hazard — FAIL so /close blocks the status
                # transition (Req 1f / AC 10). Foreign headings (e.g. a
                # '### Spec NNN — closed' record appended into the section by
                # a later command) are skipped below, not malformed.
                raise MalformedBlockError(
                    f"MALFORMED-BLOCK | {path.name} | heading {line.strip()!r} inside "
                    f"{'Error autopsies' if section == 'EA' else 'Chat insights'} section "
                    f"does not match '### EA-NNN: <title>' / '### CI-NNN: <title>'"
                )
            # The entry's own ID kind routes the target log — historical logs
            # interleave EA/CI blocks across section boundaries.
            entry_id, kind, title = em.group(1), em.group(2), em.group(3).strip()
            block = [line]
            i += 1
            while i < len(lines) and not lines[i].startswith(("## ", "### ")):
                nxt = lines[i]
                # Spec 600: stop (without consuming) at a fence toggle or a multi-line
                # comment open — the SAME conditions the outer loop's state machine
                # reacts to. Otherwise a comment immediately following this entry's
                # fields gets swallowed into `block`, the comment-open line never sets
                # in_comment in the outer loop, and the next real heading inside the
                # comment (e.g. a template placeholder) gets misparsed as malformed.
                if nxt.lstrip().startswith("```"):
                    break
                if nxt.lstrip().startswith("<!--") and "-->" not in nxt:
                    break
                block.append(nxt)
                i += 1
            if not any(FIELD_RE.match(b) for b in block[1:]):
                raise MalformedBlockError(
                    f"MALFORMED-BLOCK | {path.name} | {entry_id} has no field lines "
                    f"('- <field>: <value>') under its heading"
                )
            while block and not block[-1].strip():
                block.pop()
            entries.append(
                {
                    "kind": kind,
                    "id": entry_id,
                    "title": title,
                    "block": block,
                    "session": session_id,
                    "stub_fields": stub_fields(block),  # Spec 472
                }
            )
            continue
        i += 1
    return entries


def stub_heading(stub_id: str, title: str, session_id: str, kind: str) -> str:
    """The one-line SIG stub heading shared by the original and enriched forms."""
    detail = ERROR_LOG if kind == "EA" else INSIGHTS_LOG
    return (f"### {stub_id} — {title} (propagated from session "
            f"{session_id}; detail: {detail})")


def build_stub(stub_id: str, entry: dict) -> list[str]:
    """Assemble a signals.md stub block for one propagated entry (Spec 472).

    Heading line + any structured fields copied verbatim from the source block.
    A pre-Spec-267 entry with no structured fields degrades to the historical
    one-line form (heading only) — identical bytes to the Spec 452 output.
    """
    lines = [stub_heading(stub_id, entry["title"], entry["session"], entry["kind"])]
    lines.extend(entry.get("stub_fields", []))
    return lines


def id_present(log_text: str, entry_id: str) -> bool:
    # (?![A-Za-z0-9-]) instead of \b: 'CI-429' must not match 'CI-429-A'.
    return re.search(rf"^###\s+{re.escape(entry_id)}(?![A-Za-z0-9-])", log_text, re.MULTILINE) is not None


def stub_present(signals_text: str, entry_id: str) -> bool:
    return re.search(rf"^###\s+SIG-\d+-{re.escape(entry_id)}(?![A-Za-z0-9-])", signals_text, re.MULTILINE) is not None


def with_session_line(block: list[str], session_id: str) -> list[str]:
    """Insert `- Session:` after the heading unless the block already has one."""
    if any(re.match(r"^\s*-\s+Session:", b) for b in block):
        return block
    return [block[0], f"- Session: {session_id}", *block[1:]]


def load_log(sessions_dir: Path, name: str) -> str:
    p = sessions_dir / name
    return p.read_text(encoding="utf-8") if p.exists() else ""


STUB_HEADING_RE = re.compile(
    r"^###\s+SIG-\d+-((?:EA|CI)-\d+(?:-[A-Za-z0-9]+)*)(?![A-Za-z0-9-])"
)


def enrich_stubs(sessions_dir: Path, apply_mode: bool) -> int:
    """Spec 472 — upgrade existing one-line SIG-*-EA/CI-* stubs in place.

    Re-reads every session log to recover each entry's structured fields, then
    rewrites signals.md so any one-line stub whose source block carries fields
    gains those field lines beneath its heading. Idempotent: a stub that already
    carries any of the structured fields, or whose source has none, is left
    byte-for-byte unchanged. Read-only on the session logs and persistent logs.
    """
    signals_path = sessions_dir / SIGNALS_LOG
    if not signals_path.exists():
        print(f"SKIP | no {SIGNALS_LOG} in {sessions_dir} — nothing to enrich")
        return 0

    # entry_id -> structured field lines, from the session logs (source of truth).
    field_map: dict[str, list[str]] = {}
    for log_path in sorted(p for p in sessions_dir.iterdir() if SESSION_LOG_RE.match(p.name)):
        try:
            entries = parse_session_log(log_path)
        except MalformedBlockError as exc:
            print(f"ERROR | {exc}", file=sys.stderr)
            return 2
        for e in entries:
            # First session that defines the entry wins (IDs are unique anyway).
            field_map.setdefault(e["id"], e["stub_fields"])

    lines = signals_path.read_text(encoding="utf-8").splitlines()
    out: list[str] = []
    n_enriched = n_skip = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = STUB_HEADING_RE.match(line)
        if not m:
            i += 1
            continue
        entry_id = m.group(1)
        # Gather the existing body of this stub (until the next heading / EOF).
        body: list[str] = []
        j = i + 1
        while j < len(lines) and not lines[j].startswith(("### ", "#### ", "## ")):
            body.append(lines[j])
            j += 1
        already_enriched = any(STUB_FIELD_RE.match(b) for b in body)
        fields = field_map.get(entry_id, [])
        if already_enriched:
            # Idempotent: a second run finds the fields and leaves the stub be.
            print(f"SKIP-ENRICHED | {entry_id} | stub already carries structured fields")
            n_skip += 1
        elif not fields:
            # Pre-Spec-267 source block, or source no longer present — keep the
            # one-line form. Never invent values.
            print(f"SKIP-NO-FIELDS | {entry_id} | no structured fields in source block")
            n_skip += 1
        else:
            print(f"ENRICH | {entry_id} | +{len(fields)} structured field(s)")
            n_enriched += 1
            # Insert the field lines immediately after the heading, before any
            # pre-existing body (e.g. a blank line) the stub already had.
            out.extend(fields)
        out.extend(body)
        i = j

    if apply_mode and n_enriched:
        signals_path.write_text("\n".join(out) + "\n", encoding="utf-8")
        print(f"DONE | enrich applied: {n_enriched} stubs enriched, {n_skip} skipped")
    elif apply_mode:
        print(f"DONE | enrich applied: 0 stubs enriched, {n_skip} skipped")
    else:
        print(f"DONE | enrich dry-run: {n_enriched} would be enriched, {n_skip} skipped")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", default=True,
                      help="preview only (default)")
    mode.add_argument("--apply", action="store_true",
                      help="append missing entries to the persistent logs")
    ap.add_argument("--session-only", metavar="YYYY-MM-DD-NNN",
                    help="restrict the scan to one session log")
    ap.add_argument("--since", metavar="YYYY-MM-DD",
                    help="recency cap (Spec 473): skip session logs whose filename "
                         "date is strictly before this cutoff. Filter is on the "
                         "filename-derived date only — no file reads. Dedup against "
                         "the persistent logs is unaffected. Ignored (with a note) "
                         "when --session-only is given. Default behavior of bare "
                         "--dry-run / --apply is unchanged when --since is absent.")
    ap.add_argument("--spec", default="452",
                    help="spec number used in SIG-<spec>-EA/CI stubs (default 452; "
                         "/close Step 5d passes the closing spec)")
    ap.add_argument("--enrich-stubs", action="store_true",
                    help="Spec 472 re-enrichment mode: upgrade existing one-line "
                         "SIG-*-EA/CI-* stubs in signals.md in place by re-reading "
                         "the structured fields from the matching session-log block. "
                         "Idempotent; honors --dry-run (default) vs --apply. Never "
                         "rewrites a stub that already carries structured fields and "
                         "never invents values for pre-Spec-267 source blocks.")
    ap.add_argument("--sessions-dir", default="docs/sessions", type=Path,
                    help="directory holding session logs AND the persistent logs")
    args = ap.parse_args(argv)
    apply_mode = args.apply

    sessions_dir: Path = args.sessions_dir
    if not sessions_dir.is_dir():
        print(f"ERROR | sessions dir not found: {sessions_dir}", file=sys.stderr)
        return 2

    if args.enrich_stubs:
        # Spec 472 re-enrichment: a distinct pass that rewrites signals.md in
        # place rather than appending. Shares the parser so source fields are
        # read identically to the propagation path.
        return enrich_stubs(sessions_dir, apply_mode)

    logs = sorted(p for p in sessions_dir.iterdir() if SESSION_LOG_RE.match(p.name))
    if args.session_only:
        # --session-only is the narrowest scope and wins; --since is moot.
        if args.since:
            print(f"NOTE | --since={args.since} ignored: --session-only={args.session_only} "
                  f"already restricts the scan to a single session log")
        logs = [p for p in logs if p.stem == args.session_only]
        if not logs:
            # /close fresh-project tolerance: a missing session log is a skip,
            # not a failure (DA disposition 6) — there is nothing to propagate.
            print(f"SKIP | no session log named {args.session_only}.md in {sessions_dir}")
            return 0
    elif args.since:
        # Recency cap (Spec 473): drop session logs whose filename date is
        # strictly before the cutoff. Filename-derived date only — no file
        # reads. The persistent-log dedup targets below are unaffected, so an
        # --apply run still dedups against the FULL persistent logs.
        if not SINCE_RE.match(args.since):
            print(f"ERROR | --since must be YYYY-MM-DD (got: {args.since!r})", file=sys.stderr)
            return 2
        kept = []
        for p in logs:
            dm = SESSION_DATE_RE.match(p.stem)
            # Lexical compare is correct for zero-padded ISO YYYY-MM-DD dates.
            if dm and dm.group(1) >= args.since:
                kept.append(p)
        logs = kept

    targets = {
        ERROR_LOG: load_log(sessions_dir, ERROR_LOG),
        INSIGHTS_LOG: load_log(sessions_dir, INSIGHTS_LOG),
        SIGNALS_LOG: load_log(sessions_dir, SIGNALS_LOG),
    }
    pending: dict[str, list[str]] = {ERROR_LOG: [], INSIGHTS_LOG: [], SIGNALS_LOG: []}
    n_migrate = n_skip = 0

    for log_path in logs:
        try:
            entries = parse_session_log(log_path)
        except MalformedBlockError as exc:
            print(f"ERROR | {exc}", file=sys.stderr)
            return 2
        for e in entries:
            target = ERROR_LOG if e["kind"] == "EA" else INSIGHTS_LOG
            queued = "\n".join(pending[target])
            if id_present(targets[target], e["id"]) or id_present(queued, e["id"]):
                print(f"SKIP-DUPLICATE | {log_path.name} | {e['id']} | already in {target}")
                n_skip += 1
                # Entries already propagated keep their historical signals.md
                # state — stubs are only emitted alongside a fresh propagation
                # (Spec 452 AC 3 scopes stubs to the orphaned entries).
                continue
            print(f"MIGRATE | {log_path.name} | {e['id']} | -> {target}")
            pending[target].extend(["", *with_session_line(e["block"], e["session"])])
            n_migrate += 1
            stub_id = f"SIG-{args.spec}-{e['id']}"
            queued_sig = "\n".join(pending[SIGNALS_LOG])
            if stub_present(targets[SIGNALS_LOG], e["id"]) or stub_present(queued_sig, e["id"]):
                continue
            print(f"MIGRATE | {log_path.name} | {stub_id} | -> {SIGNALS_LOG}")
            # Spec 472: stub carries the structured classification fields copied
            # verbatim from the source block when present (graceful degradation
            # to the one-line form when absent — never invents values).
            pending[SIGNALS_LOG].extend(["", *build_stub(stub_id, e)])
            n_migrate += 1

    if apply_mode:
        for name, additions in pending.items():
            if not additions:
                continue
            path = sessions_dir / name
            try:
                base = targets[name] if path.exists() else LOG_HEADERS[name]
                text = base.rstrip("\n") + "\n" + "\n".join(additions) + "\n"
                path.write_text(text, encoding="utf-8")
            except OSError as exc:
                print(f"ERROR | write failed for {path}: {exc}", file=sys.stderr)
                return 1
        print(f"DONE | applied: {n_migrate} appended, {n_skip} skipped duplicates")
    else:
        print(f"DONE | dry-run: {n_migrate} would be appended, {n_skip} skipped duplicates")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""FORGE repro-provenance comparator (Spec 620).

Capture-and-compare provenance for spec `## Reproduction Commands` blocks.
The safety model is SETTLED (smiley1 Spec 358 consensus + operator ruling):
this module NEVER executes, resolves, or interprets spec text — string
comparison only. Structurally free of process-spawning code (AC 3): git
resolution lives in the separate repro_gitsha.py helper; callers resolve SHAs
there and pass the verified set in.

Subcommands (invoked via forge-py):
    append <spec-id> <exit-code> <shell> -- <command…>
        Append one repro-command event (delegates to events.py). The command is
        recorded byte-verbatim from the argv tail after `--`.
    compare <spec-file> <spec-id> [--valid-shas <file>] [--json]
        Classify each non-comment line of the spec's Reproduction Commands
        fenced block against captured events: verified / broken / unverifiable.
    generate <spec-id>
        Print a fenced, ready-to-paste Reproduction Commands block from the
        spec's captured exit-0 events (deduped, chronological, byte-verbatim).
        Writes no file.
    record-gate <spec-id> <verified> <broken> <unverifiable>
        Append a repro-gate outcome event (written by the /close gate; feeds
        the /evolve unverifiable-rate telemetry).
    rate [--window-days N]
        Aggregate repro-gate events across all specs within the window
        (default 90); print the unverifiable rate; >50% prints the hollowing
        warning (Req 6).

Normalization is pinned to exactly two transforms (Req 3): CRLF->LF and
trailing-whitespace strip. Nothing else. No shell introspection of spec text at
any depth (the structural fixture greps this module for invocation tokens).
"""

from __future__ import annotations

import json
import os
import re
import shlex
import stat
import sys
from pathlib import Path

_LIB_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_LIB_DIR))
import events  # noqa: E402  (shared append path — Spec 254 Approach D)

EVENT_TYPE = "repro-command"
SCHEMA_VERSION = 1
DEFAULT_REASON = "not captured via forge run (pre-adoption block)"
_SHA_SHAPE = re.compile(r"^[0-9a-f]{7,64}$")


def _normalize(line: str) -> str:
    """Pinned normalization (Req 3): CRLF->LF + trailing-whitespace strip. Nothing else."""
    return line.replace("\r\n", "\n").replace("\r", "").rstrip(" \t")


def _base_dir() -> Path:
    return Path(os.environ.get("FORGE_EVENTS_DIR", str(events.DEFAULT_BASE_DIR)))


def _harden_permissions(path: Path) -> None:
    """Req 16: owner-only mode bits, best-effort (Windows ACLs are a documented caveat)."""
    try:
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
    except OSError:
        pass


def cmd_append(argv: list[str]) -> int:
    if "--" not in argv:
        print("usage: repro_provenance.py append <spec-id> <exit-code> <shell> -- <command…>", file=sys.stderr)
        return 2
    sep = argv.index("--")
    head, cmd_parts = argv[:sep], argv[sep + 1:]
    if len(head) != 3 or not head[0].strip() or not cmd_parts:
        print("usage: repro_provenance.py append <spec-id> <exit-code> <shell> -- <command…>", file=sys.stderr)
        return 2
    spec_id, exit_code_raw, shell = head
    try:
        exit_code = int(exit_code_raw)
    except ValueError:
        print(f"repro_provenance: exit-code must be an integer (got {exit_code_raw!r})", file=sys.stderr)
        return 2
    git_sha = os.environ.get("FORGE_REPRO_GIT_SHA", "unknown")
    payload = {
        "schema_version": SCHEMA_VERSION,
        "spec_id": spec_id,
        # shlex-canonical re-quoting of the argv tail: deterministic across bash/pwsh
        # (AC 4 schema-identical), and byte-match is true by construction on the
        # documented generate-then-paste happy path (Req 13).
        "command": shlex.join(cmd_parts),
        "exit_code": exit_code,
        "iso_ts": events.iso_now(),
        "git_sha": git_sha,
        "shell": shell,
    }
    target = events.append_event(spec_id, EVENT_TYPE, payload, base_dir=_base_dir())
    _harden_permissions(target)
    return 0


def _load_captures(spec_id: str) -> list[dict]:
    path = _base_dir() / str(spec_id) / f"{EVENT_TYPE}.jsonl"
    captures: list[dict] = []
    if not path.is_file():
        return captures
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            rec = json.loads(raw)
        except json.JSONDecodeError:
            continue
        payload = rec.get("payload", {})
        if isinstance(payload, dict) and "command" in payload:
            captures.append(payload)
    return captures


def _extract_block(spec_text: str) -> list[str]:
    """Return non-comment, non-empty lines of the ## Reproduction Commands fenced block."""
    m = re.search(r"^## Reproduction Commands\s*$(.*?)(?=^## |\Z)", spec_text, re.M | re.S)
    if not m:
        return []
    fence = re.search(r"^```[a-zA-Z]*\s*$(.*?)^```\s*$", m.group(1), re.M | re.S)
    if not fence:
        return []
    lines = []
    for line in fence.group(1).splitlines():
        norm = _normalize(line)
        if not norm.strip() or norm.lstrip().startswith("#"):
            continue
        lines.append(norm)
    return lines


def cmd_compare(argv: list[str]) -> int:
    args = list(argv)
    as_json = "--json" in args
    if as_json:
        args.remove("--json")
    valid_shas: set[str] | None = None
    if "--valid-shas" in args:
        i = args.index("--valid-shas")
        try:
            sha_file = args[i + 1]
        except IndexError:
            print("repro_provenance: --valid-shas requires a file argument", file=sys.stderr)
            return 2
        valid_shas = {
            s.strip() for s in Path(sha_file).read_text(encoding="utf-8").splitlines() if s.strip()
        }
        del args[i:i + 2]
    if len(args) != 2:
        print("usage: repro_provenance.py compare <spec-file> <spec-id> [--valid-shas <file>] [--json]", file=sys.stderr)
        return 2
    spec_file, spec_id = args
    spec_text = Path(spec_file).read_text(encoding="utf-8", errors="replace")
    block_lines = _extract_block(spec_text)
    captures = _load_captures(spec_id)

    results = []
    for line in block_lines:
        matches = [c for c in captures if _normalize(str(c.get("command", ""))) == line]
        if not matches:
            outcome, sha = "unverifiable", None
        else:
            ok = [c for c in matches if c.get("exit_code") == 0]
            if ok:
                # Req 11: sha sanity — hex shape first (injection guard), then the
                # caller-resolved commit set when provided.
                sane = [
                    c for c in ok
                    if _SHA_SHAPE.match(str(c.get("git_sha", "")))
                    and (valid_shas is None or str(c.get("git_sha")) in valid_shas)
                ]
                if sane:
                    outcome, sha = "verified", str(sane[-1].get("git_sha"))
                else:
                    outcome, sha = "unverifiable", None  # foreign/fabricated/malformed provenance
            else:
                outcome, sha = "broken", None
        results.append({"line": line, "outcome": outcome, "git_sha": sha})

    if as_json:
        print(json.dumps({"spec_id": spec_id, "results": results}, indent=1))
    else:
        for r in results:
            suffix = f" (captured at {r['git_sha']})" if r["git_sha"] else ""
            print(f"{r['outcome']}: {r['line']}{suffix}")
        broken = sum(1 for r in results if r["outcome"] == "broken")
        unver = sum(1 for r in results if r["outcome"] == "unverifiable")
        print(f"repro-provenance: {len(results)} line(s) — "
              f"{sum(1 for r in results if r['outcome'] == 'verified')} verified, "
              f"{broken} broken, {unver} unverifiable")
        if broken or unver:
            print(f"remediation: forge repro-block {spec_id} regenerates a ready-to-paste block "
                  f"from captured exit-0 runs")
    return 1 if any(r["outcome"] == "broken" for r in results) else 0


def cmd_generate(argv: list[str]) -> int:
    if len(argv) != 1 or not argv[0].strip():
        print("usage: repro_provenance.py generate <spec-id>", file=sys.stderr)
        return 2
    spec_id = argv[0]
    captures = _load_captures(spec_id)
    seen: set[str] = set()
    ordered: list[str] = []
    for c in captures:  # file order == chronological (append-only)
        if c.get("exit_code") != 0:
            continue
        cmd = _normalize(str(c.get("command", "")))
        if not cmd or cmd in seen:
            continue
        seen.add(cmd)
        ordered.append(cmd)
    print("```bash")
    for cmd in ordered:
        print(cmd)
    print("```")
    return 0


def cmd_record_gate(argv: list[str]) -> int:
    if len(argv) != 4:
        print("usage: repro_provenance.py record-gate <spec-id> <verified> <broken> <unverifiable>", file=sys.stderr)
        return 2
    spec_id = argv[0]
    try:
        v, b, u = (int(x) for x in argv[1:4])
    except ValueError:
        print("repro_provenance: record-gate counts must be integers", file=sys.stderr)
        return 2
    events.append_event(spec_id, "repro-gate",
                        {"schema_version": SCHEMA_VERSION, "verified": v, "broken": b, "unverifiable": u},
                        base_dir=_base_dir())
    return 0


def cmd_rate(argv: list[str]) -> int:
    from datetime import datetime, timedelta, timezone
    window = 90
    if argv[:1] == ["--window-days"] and len(argv) >= 2:
        window = int(argv[1])
    cutoff = datetime.now(timezone.utc) - timedelta(days=window)
    v = u = closes = 0
    base = _base_dir()
    if base.is_dir():
        for gate_file in sorted(base.glob("*/repro-gate.jsonl")):
            for raw in gate_file.read_text(encoding="utf-8", errors="replace").splitlines():
                try:
                    rec = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                try:
                    ts = datetime.strptime(rec.get("timestamp", ""), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
                except ValueError:
                    continue
                if ts < cutoff:
                    continue
                p = rec.get("payload", {})
                v += int(p.get("verified", 0) or 0)
                u += int(p.get("unverifiable", 0) or 0)
                closes += 1
    total = v + u
    if total == 0:
        print(f"repro-provenance unverifiable rate: no gated lines in the last {window} days")
        return 0
    pct = 100.0 * u / total
    print(f"repro-provenance unverifiable rate: {pct:.0f}% ({v} verified / {u} unverifiable across {closes} gated close(s), last {window} days)")
    if pct > 50.0:
        # forge:path-literal-ok (display-only doc pointer in a warning string; classic-default guide location, never a filesystem access)
        print("warning: unverifiable rate above 50% over the window — the fallback is hollowing the gate; drive adoption via forge run (see docs/process-kit/repro-provenance-guide.md)")
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: repro_provenance.py {append|compare|generate|record-gate|rate} …", file=sys.stderr)
        return 2
    sub, rest = argv[0], argv[1:]
    if sub == "append":
        return cmd_append(rest)
    if sub == "compare":
        return cmd_compare(rest)
    if sub == "generate":
        return cmd_generate(rest)
    if sub == "record-gate":
        return cmd_record_gate(rest)
    if sub == "rate":
        return cmd_rate(rest)
    print(f"repro_provenance: unknown subcommand {sub!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

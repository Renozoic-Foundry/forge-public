#!/usr/bin/env python3
"""Spec 486 — git-history reconcile engine.

Classifies commits in a range into spec-linked / process / un-specced, clusters
un-specced commits by shared changed files (union-find), routes each cluster by
size to a stub spec (large) or a memory note (small), and — in --apply mode —
writes the artifacts and advances the scan-window marker.

Modes:
  --plan  (default)  Read-only. Emit the routing plan as JSON to stdout. No writes.
  --apply            Write stub specs + memory notes + advance the marker, then emit
                     a JSON result. The marker advances ONLY after every artifact is
                     written successfully (atomic / partial-failure-safe, Req 8).

Stdlib-only (ADR-359). Cross-platform via .forge/bin/forge-py. Commit-derived text is
untrusted (Req 11): it is never placed in stub-spec frontmatter (frontmatter carries
only literal/hex values), and raw commit messages are preserved inside a fenced block
in the `## Inferred Provenance` section — so a generated stub always parses as valid
FORGE frontmatter regardless of commit content.

Usage:
  forge-py .forge/lib/reconcile_classify.py [--plan|--apply] [options]

Options:
  --repo DIR              git work-tree to scan (default: cwd)
  --since REF             scan REF..HEAD (overrides the marker)
  --specs-dir DIR         spec directory (default: <repo>/docs/specs — forge:path-literal-ok
                          comment; actual default resolved via runtime_config)
  --marker PATH           scan marker (default: <repo>/.forge/state/reconcile-marker.json)
  --memory-dir DIR        operator memory dir for notes (required for notes in --apply)
  --memory-index PATH     MEMORY.md index to append pointers to (default: <memory-dir>/MEMORY.md)
  --stub-min-files N      cluster routes to stub at >= N distinct files (default: 3)
  --stub-min-lines N      ...or >= N total changed lines (default: 100)
  --window N              no-marker fallback: scan last N commits (default: 50)
  --today YYYY-MM-DD      date stamp override (deterministic tests; default: today)
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys

_LIB_DIR = os.path.dirname(os.path.abspath(__file__))
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
try:
    from runtime_config import resolve_path as _rc_resolve_path  # Spec 564 helper
except ImportError:
    _rc_resolve_path = None

SPEC_LINK_RE = re.compile(r"[Ss]pec[ -]?[0-9]+")
# Classic defaults — docs/digests/ has no forge.paths key (not part of the Spec 564
# path family), so it stays a literal prefix here regardless of repo config.
# forge:path-literal-ok (classic-default definitions — resolved via _process_markers(); docs/digests has no forge.paths key)
PROCESS_PREFIXES = ("docs/sessions/", "docs/specs/", "docs/digests/")
PROCESS_EXACT = ("docs/backlog.md",)


def _resolved_path_key(repo, key, default):
    """Resolve one forge.paths.<key> value via runtime_config, falling back to default."""
    if _rc_resolve_path is None:
        return default
    from pathlib import Path
    try:
        value, error = _rc_resolve_path(Path(repo), key)
    except Exception:
        return default
    return value if (not error and value) else default


def _process_markers(repo):
    """Resolve the process-path prefixes/exact-matches for this repo via runtime_config."""
    sessions = _resolved_path_key(repo, "sessions", "docs/sessions")
    specs = _resolved_path_key(repo, "specs", "docs/specs")
    backlog = _resolved_path_key(repo, "backlog", "docs/backlog.md")
    # docs/digests/ has no forge.paths key (not part of the Spec 564 family) — literal.
    prefixes = (f"{sessions}/", f"{specs}/", "docs/digests/")
    exact = (backlog,)
    return prefixes, exact
SPEC_FILE_RE = re.compile(r"^(\d{3,})-")
CAVEAT = ("Objective and rationale below are INFERRED from commit messages and diffs, "
          "not authored intent — verify before relying on them.")


def git(repo, *args):
    """Run a git command in repo, return stdout (text). Raises on non-zero."""
    out = subprocess.run(
        ["git", "-C", repo, *args],
        capture_output=True, text=True, check=True,
    )
    return out.stdout


def resolve_shas(repo, since, marker_path, window):
    """Return (range_label, [shas newest-first]) for the scan window."""
    if since:
        label = f"{since}..HEAD"
        out = git(repo, "rev-list", f"{since}..HEAD")
    else:
        marker_sha = read_marker(marker_path)
        if marker_sha:
            label = f"{marker_sha[:8]}..HEAD"
            out = git(repo, "rev-list", f"{marker_sha}..HEAD")
        else:
            label = f"last {window} commits"
            out = git(repo, "rev-list", f"--max-count={window}", "HEAD")
    shas = [s for s in out.split() if s]
    return label, shas


def commit_info(repo, sha):
    """Return dict: sha, author, date, subject, body, files[], lines."""
    meta = git(repo, "show", "-s", "--format=%H%x1f%an%x1f%aI%x1f%s", sha).strip("\n")
    h, author, date, subject = (meta.split("\x1f", 3) + ["", "", "", ""])[:4]
    body = git(repo, "show", "-s", "--format=%b", sha).strip("\n")
    files = [f for f in git(repo, "diff-tree", "--no-commit-id",
                            "--name-only", "-r", sha).split("\n") if f]
    lines = 0
    numstat = git(repo, "diff-tree", "--no-commit-id", "--numstat", "-r", sha)
    for ln in numstat.splitlines():
        parts = ln.split("\t")
        if len(parts) >= 2:
            for n in parts[:2]:
                if n.isdigit():
                    lines += int(n)
    return {"sha": h or sha, "author": author, "date": date,
            "subject": subject, "body": body, "files": files, "lines": lines}


def classify(info, prefixes=PROCESS_PREFIXES, exact=PROCESS_EXACT):
    """Return 'spec-linked' | 'process' | 'un-specced' for one commit."""
    text = f"{info['subject']} {info['body']}"
    if SPEC_LINK_RE.search(text):
        return "spec-linked"
    files = info["files"]
    if not files:
        return "process"  # merges / empty diffs: skip (out of scope, Verification (b))
    is_process = all(
        f.startswith(prefixes) or f in exact for f in files
    )
    return "process" if is_process else "un-specced"


def cluster(commits):
    """Union-find over commits sharing any changed file. Returns list of clusters
    (each a list of commit dicts)."""
    n = len(commits)
    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    file_to_first = {}
    for i, c in enumerate(commits):
        for f in c["files"]:
            if f in file_to_first:
                union(file_to_first[f], i)
            else:
                file_to_first[f] = i

    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(commits[i])
    # Stable ordering: by earliest (last in newest-first list) appearance.
    return [groups[k] for k in sorted(groups, key=lambda k: min(
        commits.index(c) for c in groups[k]))]


def cluster_stats(group):
    files = sorted({f for c in group for f in c["files"]})
    lines = sum(c["lines"] for c in group)
    return files, lines


def route(group, min_files, min_lines):
    files, lines = cluster_stats(group)
    return "stub" if (len(files) >= min_files or lines >= min_lines) else "note"


def slugify(text, maxlen=48):
    s = re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-")
    s = re.sub(r"-+", "-", s)
    return (s[:maxlen].strip("-") or "untitled")


def next_spec_number(specs_dir):
    mx = 0
    if os.path.isdir(specs_dir):
        for name in os.listdir(specs_dir):
            m = SPEC_FILE_RE.match(name)
            if m:
                mx = max(mx, int(m.group(1)))
    return mx + 1


def read_marker(marker_path):
    try:
        with open(marker_path, encoding="utf-8") as fh:
            return (json.load(fh) or {}).get("sha")
    except (OSError, ValueError):
        return None


def write_marker(marker_path, sha, now_iso):
    os.makedirs(os.path.dirname(marker_path), exist_ok=True)
    with open(marker_path, "w", encoding="utf-8") as fh:
        json.dump({"sha": sha, "updated": now_iso}, fh, indent=2)
        fh.write("\n")


def fenced(text):
    """Preserve untrusted multi-line text inside a fence that its own content
    cannot break (Req 11) — widen the fence past any backtick run in the body."""
    longest = max((len(m) for m in re.findall(r"`+", text or "")), default=0)
    fence = "`" * max(3, longest + 1)
    return f"{fence}\n{text}\n{fence}"


def render_stub(num, group, files, lines, today, valid_until):
    shas = [c["sha"][:8] for c in group]
    title = f"Reconciled — {group[0]['subject'][:60]}".strip()
    title = re.sub(r"\s+", " ", title).replace("\n", " ")
    slug = f"reconciled-{slugify(group[0]['subject'])}"
    # Frontmatter carries ONLY literal/hex values — never raw commit text (Req 11).
    fm = [
        "# Framework: FORGE",
        f"# Spec {num} - {slugify(title).replace('-', ' ')}",
        "",
        "- Status: draft",
        "- Change-Lane: `retroactive`",
        "- Retroactive: true",
        f"- Reconciled-From: {','.join(shas)}",
        "- Trigger: reconcile",
        "- Owner: operator",
        "- Author: reconcile",
        f"- Last updated: {today}",
        f"- valid-until: {valid_until}",
        "",
    ]
    prov = ["## Inferred Provenance", "",
            f"> {CAVEAT}", "",
            f"Reconstructed from {len(group)} un-specced commit(s) "
            f"touching {len(files)} file(s) / {lines} changed line(s).", ""]
    for c in group:
        prov += [f"### {c['sha'][:8]} — {c['author']} — {c['date']}",
                 "", "Commit message (verbatim, untrusted):", "",
                 fenced((c["subject"] + ("\n\n" + c["body"] if c["body"] else "")).strip()),
                 "", "Files:", ""]
        prov += [f"- `{f}`" for f in c["files"]] + [""]
    body = [
        "## Objective",
        "",
        "_INFERRED_ — this stub documents work that landed outside the FORGE spec "
        "loop. The objective below is reverse-engineered from the commit message(s) "
        "and diff; confirm before relying on it.",
        "",
        f"Reconstructed summary: {group[0]['subject'].strip() or '(no subject)'}",
        "",
        "## Scope",
        "",
        "In scope (inferred from changed files):",
        "",
    ] + [f"- `{f}`" for f in files] + [
        "",
        "## Requirements",
        "",
        "1. _Placeholder — not authored. A human must define requirements before this "
        "stub is implemented; reconcile never fabricates them._",
        "",
        "## Acceptance Criteria",
        "",
        "1. _Placeholder — not authored (see Requirements)._",
        "",
        "## Test Plan",
        "",
        "1. _Placeholder — not authored (see Requirements)._",
        "",
    ]
    log = ["## Revision Log", "",
           f"- {today}: Stub spec created by /reconcile (Spec 486) from un-specced "
           f"commits {', '.join(shas)}. Status terminal at `draft` — never "
           "auto-advanced. Objective/Scope INFERRED; Requirements/AC/Test-Plan are "
           "placeholders pending human authoring.", ""]
    return "\n".join(fm + prov + body + log)


def render_note(num, group, files, lines, today):
    shas = [c["sha"][:8] for c in group]
    slug = f"reconciled-{group[0]['sha'][:8]}"
    name = group[0]["subject"].strip() or "(no subject)"
    fm = [
        "---",
        f"name: {slug}",
        f"description: Un-specced change reconciled by /reconcile on {today} "
        f"({lines} lines / {len(files)} files)",
        "metadata:",
        "  type: project",
        "---",
        "",
        f"Code committed outside any FORGE spec, reconciled {today} (Spec 486). "
        f"Source commit(s): {', '.join(shas)}.",
        "",
        f"**Inferred summary:** {name}",
        "",
        "Files touched:",
    ] + [f"- `{f}`" for f in files] + [
        "",
        f"_Inferred from commit metadata, not authored intent — {CAVEAT}_",
    ]
    return slug, "\n".join(fm)


def build_plan(repo, args):
    marker_path = args.marker
    label, shas = resolve_shas(repo, args.since, marker_path, args.window)
    prefixes, exact = _process_markers(repo)
    buckets = {"spec-linked": 0, "process": 0, "un-specced": 0}
    unspecced = []
    for sha in shas:
        info = commit_info(repo, sha)
        kind = classify(info, prefixes, exact)
        buckets[kind] += 1
        if kind == "un-specced":
            unspecced.append(info)
    clusters = cluster(unspecced) if unspecced else []
    routed = []
    for grp in clusters:
        files, lines = cluster_stats(grp)
        dest = route(grp, args.stub_min_files, args.stub_min_lines)
        routed.append({"commits": [c["sha"][:8] for c in grp],
                       "files": files, "lines": lines, "route": dest})
    head = git(repo, "rev-parse", "HEAD").strip()
    return {"range": label, "head": head, "commits_scanned": len(shas),
            "buckets": buckets, "clusters": routed, "_groups": clusters}


def apply_plan(repo, args, plan, today):
    valid_until = (datetime.date.fromisoformat(today)
                   + datetime.timedelta(days=90)).isoformat()
    now_iso = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ")
    specs_dir = args.specs_dir
    created_specs, created_notes = [], []
    num = next_spec_number(specs_dir)
    for grp, routed in zip(plan["_groups"], plan["clusters"]):
        files, lines = routed["files"], routed["lines"]
        if routed["route"] == "stub":
            content = render_stub(num, grp, files, lines, today, valid_until)
            slug = f"reconciled-{slugify(grp[0]['subject'])}"
            path = os.path.join(specs_dir, f"{num:03d}-{slug}.md")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(content + "\n")
            created_specs.append({"number": num, "path": path,
                                  "commits": routed["commits"]})
            num += 1
        else:
            if not args.memory_dir:
                raise SystemExit("reconcile: --memory-dir required to write notes "
                                 "in --apply mode")
            os.makedirs(args.memory_dir, exist_ok=True)
            slug, content = render_note(num, grp, files, lines, today)
            note_path = os.path.join(args.memory_dir, f"{slug}.md")
            with open(note_path, "w", encoding="utf-8") as fh:
                fh.write(content + "\n")
            index = args.memory_index or os.path.join(args.memory_dir, "MEMORY.md")
            pointer = (f"- [{slug}]({slug}.md) — un-specced code reconciled {today} "
                       f"({lines} lines)\n")
            with open(index, "a", encoding="utf-8") as fh:
                fh.write(pointer)
            created_notes.append({"slug": slug, "path": note_path,
                                  "commits": routed["commits"]})
    # Atomic marker advance: ONLY after every artifact wrote successfully (Req 8).
    write_marker(args.marker, plan["head"], now_iso)
    return {"created_specs": created_specs, "created_notes": created_notes,
            "marker_advanced_to": plan["head"]}


def main(argv=None):
    p = argparse.ArgumentParser(description="Spec 486 git-history reconcile engine")
    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--plan", action="store_true", help="read-only plan (default)")
    mode.add_argument("--apply", action="store_true", help="write artifacts + marker")
    p.add_argument("--repo", default=".")
    p.add_argument("--since")
    p.add_argument("--specs-dir")
    p.add_argument("--marker")
    p.add_argument("--memory-dir")
    p.add_argument("--memory-index")
    p.add_argument("--stub-min-files", type=int, default=3)
    p.add_argument("--stub-min-lines", type=int, default=100)
    p.add_argument("--window", type=int, default=50)
    p.add_argument("--today")
    args = p.parse_args(argv)

    repo = os.path.abspath(args.repo)
    if not args.specs_dir:
        args.specs_dir = os.path.join(repo, _resolved_path_key(repo, "specs", "docs/specs"))
    if not args.marker:
        args.marker = os.path.join(repo, ".forge", "state", "reconcile-marker.json")
    today = args.today or datetime.date.today().isoformat()

    plan = build_plan(repo, args)
    if args.apply:
        result = apply_plan(repo, args, plan, today)
        out = {"mode": "apply", "range": plan["range"],
               "commits_scanned": plan["commits_scanned"],
               "buckets": plan["buckets"],
               "clusters": plan["clusters"], **result}
    else:
        out = {"mode": "plan", "range": plan["range"],
               "commits_scanned": plan["commits_scanned"],
               "buckets": plan["buckets"], "clusters": plan["clusters"],
               "would_create": {
                   "stub_specs": sum(1 for c in plan["clusters"] if c["route"] == "stub"),
                   "memory_notes": sum(1 for c in plan["clusters"] if c["route"] == "note"),
               }}
    # Drop internal key before serializing.
    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

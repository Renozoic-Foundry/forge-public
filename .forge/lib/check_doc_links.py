#!/usr/bin/env python3
"""check_doc_links.py — audience-scoped relative-link integrity checker (Spec 574).

Run via the cross-platform wrapper:
    .forge/bin/forge-py .forge/lib/check_doc_links.py --mode source|staging [--root DIR]

Ships in the plugin payload (Spec 588) so plugin-tier consumers can reach it; `scripts/
check-doc-links.py` remains as a thin delegating wrapper for FORGE-self CI. CONSUMER NOTE:
`source` is FORGE-self-repo-shaped (it reads `public-manifest.yaml`). The former
`distributed` mode (template/docs/ scan) was retired by Spec 558 with the Copier surface.
To check an arbitrary consumer project, use:
    .forge/bin/forge-py .forge/lib/check_doc_links.py --mode staging --root .

A relative markdown reference is broken when its target is absent from the file set
its AUDIENCE receives — not the private repo tree (Spec 574 R1):

  source       Scan the public-manifest file list in the private repo; resolve each
               relative link against the PUBLISHED set (manifest files + published
               directory globs). Catches links that resolve privately but 404 publicly.
  staging      Scan every .md in --root (a sync staging tree); resolve against the
               staging tree itself. Wired fail-closed into sync-to-public.sh --execute
               via validate-public-docs.sh --staging (Spec 574 R2, Spec 519 posture).

Allowlist: .forge/lib/doc-link-allowlist.yaml (resolved next to this file) — `path | link |
reason` rows; every entry requires a non-empty reason (Spec 574 DA finding #5 escape hatch).

Exit codes: 0 = clean, 1 = broken references, 2 = usage/config error.
"""

import argparse
import io
import os
import re
import sys

# Two levels up from .forge/lib/ (Spec 588 move — was one level up from scripts/).
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Markdown link/image targets: [text](target) — skip absolute URLs, mailto, pure anchors.
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
SCHEME_RE = re.compile(r"^[a-z][a-z0-9+.-]*:", re.IGNORECASE)


def load_allowlist():
    # Resolved next to this file so it travels with the payload copy (Spec 588 R4).
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "doc-link-allowlist.yaml")
    allow = set()
    if not os.path.isfile(path):
        return allow
    try:
        import yaml
        data = yaml.safe_load(io.open(path, encoding="utf-8")) or {}
    except Exception as exc:  # config error is fatal — a broken allowlist must not silently allow nothing
        print(f"ERROR: cannot parse {path}: {exc}", file=sys.stderr)
        sys.exit(2)
    for row in data.get("allow", []) or []:
        if not row.get("reason", "").strip():
            print(f"ERROR: allowlist entry missing reason: {row}", file=sys.stderr)
            sys.exit(2)
        allow.add((row.get("path", ""), row.get("link", "")))
    return allow


def manifest_file_set():
    """Published file set from public-manifest.yaml (Spec 512 restricted-YAML shape):
    files: (loose copies), mirror_dirs: (recursive), mirror_globs: ("dir|glob[,glob]"
    non-recursive), remove: (never ship). template/ mirrors recursively; the plugin
    payload dirs appended at runtime are not doc-link targets."""
    import fnmatch
    import yaml
    manifest_path = os.path.join(REPO_ROOT, "public-manifest.yaml")
    data = yaml.safe_load(io.open(manifest_path, encoding="utf-8"))
    files = set()
    for f in data.get("files", []) or []:
        files.add(str(f).replace("\\", "/"))
    dir_prefixes = [str(d).rstrip("/") + "/" for d in data.get("mirror_dirs", []) or []]
    glob_rules = []  # (dir_prefix, [globs]) — non-recursive
    for entry in data.get("mirror_globs", []) or []:
        d, _, globs = str(entry).partition("|")
        glob_rules.append((d.rstrip("/") + "/", [g.strip() for g in globs.split(",") if g.strip()]))
    removed = set()
    for r in data.get("remove", []) or []:
        removed.add(str(r).replace("\\", "/"))

    def matches_glob_rule(relpath):
        for prefix, globs in glob_rules:
            if relpath.startswith(prefix) and "/" not in relpath[len(prefix):]:
                name = relpath[len(prefix):]
                if any(fnmatch.fnmatch(name, g) for g in globs):
                    return True
        return False

    return files, dir_prefixes, removed, matches_glob_rule


def published(relpath, files, dir_prefixes, removed, matches_glob_rule):
    relpath = relpath.replace("\\", "/")
    if relpath in removed:
        return False
    if relpath in files:
        return True
    if any(relpath.startswith(p) for p in dir_prefixes):
        return True
    return matches_glob_rule(relpath)


def extract_links(md_path):
    text = io.open(md_path, encoding="utf-8", errors="replace").read()
    # Drop fenced code blocks — command examples are not navigable links.
    text = re.sub(r"```.*?```", "", text, flags=re.DOTALL)
    for m in LINK_RE.finditer(text):
        target = m.group(1)
        if SCHEME_RE.match(target) or target.startswith("#") or target.startswith("<"):
            continue
        yield target.split("#", 1)[0]  # strip anchor fragment


# Spec 584: command/skill BODIES resolve paths from the project root at execution time
# (Spec 575 paths-note convention) — their links get a root-relative RETRY after
# file-relative resolution fails. Scoped to exactly these path classes; ordinary docs
# keep pure file-relative semantics.
COMMAND_BODY_RE = re.compile(r"^(template/)?(\.forge|\.claude)/(commands|skills)/")


def _audience_root(base_dir, rel_display):
    """Mode-aware retry root (Spec 584): <base>/template when the file lives under
    template/ within the mode's base (pre-4.0 staging trees may retain the prefix),
    else <base>."""
    if rel_display.startswith("template/"):
        return os.path.join(base_dir, "template")
    return base_dir


def check_file(md_path, base_dir, exists_fn, allow, rel_display):
    broken = []
    is_command_body = bool(COMMAND_BODY_RE.match(rel_display))
    for target in extract_links(md_path):
        if not target:
            continue
        if (rel_display, target) in allow:
            continue
        resolved = os.path.normpath(os.path.join(os.path.dirname(md_path), target))
        rel = os.path.relpath(resolved, base_dir).replace(os.sep, "/")
        if not rel.startswith("..") and exists_fn(rel, resolved):
            continue
        if is_command_body:
            root = _audience_root(base_dir, rel_display)
            r2 = os.path.normpath(os.path.join(root, target))
            rel2 = os.path.relpath(r2, base_dir).replace(os.sep, "/")
            if not rel2.startswith("..") and exists_fn(rel2, r2):
                continue  # root-relative resolution succeeded (command-body convention)
        if rel.startswith(".."):
            broken.append((target, "escapes the audience root"))
        else:
            broken.append((target, "target absent from audience file set"))
    return broken


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", required=True, choices=["source", "staging"])
    ap.add_argument("--root", help="staging tree root (staging mode)")
    ap.add_argument("--evidence-out", help="staging mode: write the FULL broken list here (Spec 584; default <root>/../doc-link-broken.txt)")
    args = ap.parse_args()

    allow = load_allowlist()
    failures = 0
    checked = 0

    if args.mode == "source":
        files, dir_prefixes, removed, matches_glob_rule = manifest_file_set()
        md_files = [f for f in sorted(files) if f.endswith(".md")
                    and os.path.isfile(os.path.join(REPO_ROOT, f))]
        # Also scan published .md files inside mirrored/glob dirs — except template/,
        # which distributed mode owns (consumer-received resolution root differs).
        seen = set(md_files)
        for prefix in dir_prefixes:
            if prefix.startswith("template"):
                continue
            base = os.path.join(REPO_ROOT, prefix.rstrip("/"))
            for dirpath, _dirs, names in os.walk(base):
                for name in names:
                    if name.endswith(".md"):
                        rel = os.path.relpath(os.path.join(dirpath, name), REPO_ROOT).replace(os.sep, "/")
                        if rel not in seen and published(rel, files, dir_prefixes, removed, matches_glob_rule):
                            md_files.append(rel)
                            seen.add(rel)
        for relf in sorted(os.listdir(os.path.join(REPO_ROOT, "docs", "articles"))
                           ) if os.path.isdir(os.path.join(REPO_ROOT, "docs", "articles")) else []:
            rel = f"docs/articles/{relf}"
            if rel.endswith(".md") and rel not in seen and matches_glob_rule(rel):
                md_files.append(rel)
                seen.add(rel)
        md_files = sorted(md_files)

        def exists_fn(rel, resolved):
            # Published AND physically present in the private tree.
            return (published(rel, files, dir_prefixes, removed, matches_glob_rule)
                    and os.path.exists(resolved))

        for relf in md_files:
            full = os.path.join(REPO_ROOT, relf)
            broken = check_file(full, REPO_ROOT, exists_fn, allow, relf)
            checked += 1
            for target, why in broken:
                print(f"BROKEN [{relf}] -> {target} ({why})")
                failures += 1

    elif args.mode == "staging":
        root = os.path.abspath(args.root or "")
        if not root or not os.path.isdir(root):
            print("ERROR: --root <staging-dir> required for staging mode", file=sys.stderr)
            sys.exit(2)

        def exists_fn(rel, resolved):
            return os.path.exists(resolved)

        # Spec 584: staging runs write the COMPLETE broken list to an evidence file —
        # wrapper log truncation can no longer hide entries (the SIG-574-03 addendum-2
        # blind-iteration lesson). Default: <root>/../doc-link-broken.txt.
        evidence_path = args.evidence_out or os.path.join(os.path.dirname(root), "doc-link-broken.txt")
        all_broken_lines = []

        for dirpath, _dirs, names in os.walk(root):
            for name in names:
                if not name.endswith(".md"):
                    continue
                full = os.path.join(dirpath, name)
                relf = os.path.relpath(full, root).replace(os.sep, "/")
                broken = check_file(full, root, exists_fn, allow, relf)
                checked += 1
                for target, why in broken:
                    line = f"BROKEN [{relf}] -> {target} ({why})"
                    print(line)
                    all_broken_lines.append(line)
                    failures += 1
        try:
            with io.open(evidence_path, "w", encoding="utf-8", newline="\n") as ef:
                ef.write("\n".join(all_broken_lines) + ("\n" if all_broken_lines else ""))
            print(f"full broken-list evidence: {evidence_path} ({len(all_broken_lines)} line(s))")
        except OSError as exc:
            print(f"WARN: could not write evidence file {evidence_path}: {exc}", file=sys.stderr)

    print(f"check-doc-links [{args.mode}]: {checked} file(s) scanned, {failures} broken reference(s).")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()

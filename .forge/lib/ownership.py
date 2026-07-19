#!/usr/bin/env python3
"""ownership.py — FORGE-owned path partition from .forge/ownership.yaml (Spec 575).

Usage:
    forge-py .forge/lib/ownership.py --list [--class CLASS] [--dir DIR]
    forge-py .forge/lib/ownership.py --partition [--dir DIR]

--list       print each manifest entry as `<class>\t<path>` (optionally filtered).
--partition  expand the manifest against `git ls-files`: prints every tracked file
             prefixed `FORGE\t` or `SOLUTION\t` — the mechanical FORGE-vs-solution
             split consumed by the Spec 577 retrofit inventory and by tooling.

Exit codes: 0 ok; 2 manifest missing/unreadable/unsupported schema.
Stdlib only (ADR-359) — the manifest is a restricted YAML subset written by
scaffold.py (schema: 1; flow-mapping rows), parsed line-wise here by design.
"""
import argparse
import io
import os
import re
import subprocess
import sys

ROW = re.compile(r"^\s*-\s*\{path:\s*([^,}]+?)\s*,\s*class:\s*([a-z-]+)\s*\}\s*$")
CLASSES = {"process-data", "runtime-state", "config", "framework-doc"}


def load(manifest_path):
    if not os.path.isfile(manifest_path):
        print(f"ownership: manifest not found: {manifest_path}", file=sys.stderr)
        sys.exit(2)
    schema = None
    rows = []
    for line in io.open(manifest_path, encoding="utf-8"):
        m = re.match(r"^schema:\s*(\d+)\s*$", line)
        if m:
            schema = int(m.group(1))
        m = ROW.match(line)
        if m:
            path, cls = m.group(1), m.group(2)
            if cls not in CLASSES:
                print(f"ownership: unknown class '{cls}' for {path}", file=sys.stderr)
                sys.exit(2)
            rows.append((path, cls))
    if schema != 1:
        print(f"ownership: unsupported or missing schema (got {schema}, want 1)", file=sys.stderr)
        sys.exit(2)
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--partition", action="store_true")
    ap.add_argument("--class", dest="cls", default=None)
    ap.add_argument("--dir", default=".")
    args = ap.parse_args()

    rows = load(os.path.join(args.dir, ".forge", "ownership.yaml"))

    if args.partition:
        try:
            out = subprocess.run(["git", "ls-files"], cwd=args.dir, capture_output=True,
                                 text=True, encoding="utf-8", check=True).stdout
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            print(f"ownership: git ls-files failed: {exc}", file=sys.stderr)
            sys.exit(2)
        prefixes = [p for p, _ in rows if p.endswith("/")]
        exact = {p for p, _ in rows if not p.endswith("/")}
        for f in out.splitlines():
            owned = f in exact or any(f.startswith(pref) for pref in prefixes)
            print(f"{'FORGE' if owned else 'SOLUTION'}\t{f}")
        return

    for path, cls in rows:
        if args.cls and cls != args.cls:
            continue
        print(f"{cls}\t{path}")


if __name__ == "__main__":
    main()

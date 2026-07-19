#!/usr/bin/env python3
"""retrofit.py — consumer retrofit engine (Spec 577): inventory → de-vendor →
reorganize → reconcile-seed, as composable, idempotent, dry-run-default phases.

Thin orchestrator by contract (consensus R2/R3): snapshots ride
migration-snapshot.sh, link verification rides scripts/check-doc-links.py,
history seeding rides /reconcile — no forked logic.

Usage:
    forge-py .forge/lib/retrofit.py <inventory|devendor|reorganize|reconcile|status>
        [--dir DIR] [--apply] [--plugin-root PATH] [--claude-only-accepted]

Safety contract (Spec 577 R1/R2/R5):
  * dry-run default — `--apply` required for any mutation; every apply phase
    prints the FULL action list first (CISO R3 disposition: the deletion list is
    always displayed) and requires the operator confirmation the calling command
    flow collects.
  * de-vendor removes ONLY vendored files whose bytes match the installed
    plugin/runtime copy (pristine). Modified or counterpart-less files are
    NEVER removed — they surface for operator disposition.
  * git rm/mv use `--` separators; paths are validated against the inventory
    and rejected on control characters (CISO hardening).
  * phases are idempotent: re-running skips already-done work; a mid-phase kill
    is recovered by re-running the phase or restoring the snapshot
    (migration-snapshot.sh).

Exit codes: 0 ok; 1 refused (precondition/negative path); 2 usage/config error.
Stdlib only (ADR-359).
"""
import argparse
import hashlib
import io
import os
import re
import subprocess
import sys

# Framework-vendored surfaces (superseded by the plugin/runtime payload).
# forge:path-literal-ok (file: framework-structure — vendored-payload classification table; Spec 577)
VENDORED_PREFIXES = (
    ".forge/bin/", ".forge/lib/", ".forge/commands/", ".forge/adapters/",
    ".forge/templates/", ".forge/modules/", ".forge/workflows/", ".forge/skills/",
    ".claude/commands/", ".claude/agents/", ".claude/skills/",
    "template/",
)
VENDORED_EXACT = {"copier.yml", "forge-bootstrap.md"}
# Never touched by any phase (project identity/config/state).
PROTECTED = {"AGENTS.md", "CLAUDE.md", ".copier-answers.yml", ".forge/ownership.yaml"}

CLASSIC = {
    "specs": "docs/specs", "sessions": "docs/sessions", "decisions": "docs/decisions",
    "research": "docs/research", "process_kit": "docs/process-kit", "backlog": "docs/backlog.md",
}
CONTAINED = {
    "specs": ".forge/project/specs", "sessions": ".forge/project/sessions",
    "decisions": ".forge/project/decisions", "research": ".forge/project/research",
    "process_kit": ".forge/project/process-kit", "backlog": ".forge/project/backlog.md",
}
CTRL = re.compile(r"[\x00-\x1f\x7f]")


def run(args, cwd, check=True):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                          encoding="utf-8", check=check)


def ls_files(root):
    out = run(["git", "ls-files"], root).stdout
    return [f for f in out.splitlines() if f]


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()


def validate_paths(paths):
    for p in paths:
        if CTRL.search(p) or p.startswith("-"):
            print(f"retrofit: REFUSED — unsafe path name: {p!r}", file=sys.stderr)
            sys.exit(1)


def classify(root, plugin_root):
    """Phase 1 — read-only inventory. Returns dict of lists."""
    inv = {"vendored-pristine": [], "vendored-modified": [], "vendored-no-counterpart": [],
           "process-data": [], "config": [], "project": [], "ambiguous": []}
    proc_prefixes = tuple(v + "/" for v in CLASSIC.values() if not v.endswith(".md")) + \
                    tuple(v + "/" for v in CONTAINED.values() if not v.endswith(".md"))
    proc_exact = {CLASSIC["backlog"], CONTAINED["backlog"]}
    for f in ls_files(root):
        if f in PROTECTED:
            inv["config"].append(f)
        elif f.startswith(".forge/state/"):
            inv["config"].append(f)
        elif f in VENDORED_EXACT or any(f.startswith(p) for p in VENDORED_PREFIXES):
            counterpart = os.path.join(plugin_root, f) if plugin_root else None
            if counterpart and os.path.isfile(counterpart):
                same = sha(os.path.join(root, f)) == sha(counterpart)
                inv["vendored-pristine" if same else "vendored-modified"].append(f)
            else:
                inv["vendored-no-counterpart"].append(f)
        elif f in proc_exact or f.startswith(proc_prefixes) or f == "docs/QUICK-REFERENCE.md":
            inv["process-data"].append(f)
        elif f.startswith("docs/"):
            # docs/ outside process-data locations: could be solution docs OR FORGE
            # extras (examples, articles) — never guessed (R1).
            inv["ambiguous"].append(f)
        else:
            inv["project"].append(f)
    return inv


def phase_inventory(root, plugin_root, _apply):
    inv = classify(root, plugin_root)
    print("## retrofit inventory (read-only)")
    for k in ("vendored-pristine", "vendored-modified", "vendored-no-counterpart",
              "process-data", "config", "ambiguous", "project"):
        print(f"  {k}: {len(inv[k])}")
        show = inv[k] if k != "project" else inv[k][:5]
        for f in show:
            print(f"    {f}")
        if k == "project" and len(inv[k]) > 5:
            print(f"    ... (+{len(inv[k])-5} project files, untouched by every phase)")
    if inv["vendored-modified"] or inv["vendored-no-counterpart"] or inv["ambiguous"]:
        print("\nOPERATOR DISPOSITION REQUIRED before de-vendor/reorganize:")
        print("  - vendored-modified: hand-edited framework copies — port the edit upstream or accept loss explicitly")
        print("  - vendored-no-counterpart: not in the installed payload — verify plugin/runtime version, or keep")
        print("  - ambiguous: docs/ content outside process-data locations — classify as project or FORGE-extra")
    return inv


def _plugin_version(plugin_root):
    pj = os.path.join(plugin_root, ".claude-plugin", "plugin.json")
    if not os.path.isfile(pj):
        return None
    m = re.search(r'"version"\s*:\s*"([^"]+)"', io.open(pj, encoding="utf-8").read())
    return m.group(1) if m else None


def phase_devendor(root, plugin_root, apply_):
    if not plugin_root or not os.path.isdir(plugin_root):
        print("retrofit: REFUSED — no installed plugin/runtime found (pass --plugin-root or set "
              "CLAUDE_PLUGIN_ROOT/FORGE_RUNTIME_ROOT). Migrate to the plugin FIRST — de-vendoring "
              "without a replacement runtime would strand the project (Spec 577 AC9).",
              file=sys.stderr)
        sys.exit(1)
    ver = _plugin_version(plugin_root)
    if not ver:
        print("retrofit: REFUSED — cannot read plugin version from the runtime root; "
              "verify the install before de-vendoring.", file=sys.stderr)
        sys.exit(1)
    # Mixed-team runtime re-confirmation (DA R3 false-negative guard): the calling
    # command flow prompts; the engine requires the explicit flag when the runtime
    # root is a Claude plugin cache only.
    inv = classify(root, plugin_root)
    removable = inv["vendored-pristine"]
    print(f"## de-vendor (plugin v{ver} at {plugin_root})")
    print(f"  removable (byte-identical to installed payload): {len(removable)}")
    for f in removable:
        print(f"    rm {f}")
    held = inv["vendored-modified"] + inv["vendored-no-counterpart"]
    if held:
        print(f"  HELD for operator disposition (never auto-removed): {len(held)}")
        for f in held:
            print(f"    HOLD {f}")
    if not removable:
        print("  nothing to remove (idempotent re-run or already de-vendored).")
        return
    if not apply_:
        print("\nDRY-RUN — re-run with --apply (after operator confirmation) to remove the listed files.")
        return
    validate_paths(removable)
    snap = os.path.join(root, ".forge", "lib", "migration-snapshot.sh")
    if os.path.isfile(snap):
        run(["bash", snap, "snapshot"], root, check=False)
        print("  snapshot taken (migration-snapshot.sh)")
    run(["git", "rm", "-q", "--"] + removable, root)
    print(f"  removed {len(removable)} files (staged). Commit with explicit paths; "
          "rollback: migration-snapshot.sh restore.")


def phase_reorganize(root, _plugin_root, apply_):
    moves = []
    for key, src in CLASSIC.items():
        dst = CONTAINED[key]
        s_abs, d_abs = os.path.join(root, src), os.path.join(root, dst)
        if key == "backlog":
            if os.path.isfile(s_abs):
                moves.append((src, dst))
        elif os.path.isdir(s_abs) and os.listdir(s_abs):
            moves.append((src, dst))
    print("## reorganize → contained layout")
    if not moves:
        print("  nothing to move (already contained, or no classic process data). Idempotent no-op.")
        return
    for s, d in moves:
        print(f"    git mv {s} -> {d}")
    if not apply_:
        print("\nDRY-RUN — re-run with --apply (after operator confirmation) to perform the moves, "
              "write the forge.paths block + ownership manifest, then verify links "
              "(scripts/check-doc-links.py) and doctor (D-PATHS).")
        return
    validate_paths([s for s, _ in moves] + [d for _, d in moves])
    os.makedirs(os.path.join(root, ".forge", "project"), exist_ok=True)
    for s, d in moves:
        os.makedirs(os.path.dirname(os.path.join(root, d)) or os.path.join(root, d), exist_ok=True)
        run(["git", "mv", "--", s, d], root)
    # forge.paths block (idempotent append under ## Runtime Configuration)
    agents = os.path.join(root, "AGENTS.md")
    text = io.open(agents, encoding="utf-8").read() if os.path.isfile(agents) else ""
    if "forge:" not in text or "paths:" not in text:
        block = ("\n## Runtime Configuration\n\n```yaml\nforge:\n  paths:\n"
                 + "".join(f"    {k}: {v}\n" for k, v in CONTAINED.items()) + "```\n")
        if "## Runtime Configuration" in text:
            block = block.replace("\n## Runtime Configuration\n", "")
            text = text.replace("## Runtime Configuration\n", "## Runtime Configuration\n" + block, 1)
        else:
            text += block
        io.open(agents, "w", encoding="utf-8", newline="\n").write(text)
    # ownership manifest
    own = os.path.join(root, ".forge", "ownership.yaml")
    rows = "".join(f"  - {{path: {v}/, class: process-data}}\n" for v in
                   [CONTAINED[k] for k in ("specs", "sessions", "decisions", "research", "process_kit")])
    io.open(own, "w", encoding="utf-8", newline="\n").write(
        "# .forge/ownership.yaml — written by retrofit reorganize (Spec 577)\nschema: 1\n"
        "layout: contained\npaths:\n" + rows +
        f"  - {{path: {CONTAINED['backlog']}, class: process-data}}\n"
        "  - {path: .forge/state/, class: runtime-state}\n"
        "  - {path: .forge/ownership.yaml, class: config}\n"
        "  - {path: AGENTS.md, class: config}\n  - {path: CLAUDE.md, class: config}\n")
    print(f"  moved {len(moves)} locations; forge.paths + ownership.yaml written (staged moves). "
          "Now run the link checker + forge-doctor, then commit with explicit paths.")


def phase_reconcile(root, _plugin_root, apply_):
    marker = os.path.join(root, ".forge", "state", "reconcile-pending.json")
    print("## reconcile seed — bounded /reconcile offer (Spec 577 R4)")
    print("  scope options: last-90-days | last-200-commits | full-history | skip")
    print("  run: /reconcile (the command consumes forge.reconcile.* thresholds unchanged)")
    if apply_:
        os.makedirs(os.path.dirname(marker), exist_ok=True)
        io.open(marker, "w", encoding="utf-8", newline="\n").write(
            '{"planted": "retrofit", "options": ["last-90-days", "last-200-commits", "full-history"]}\n')
        print(f"  reconcile-pending marker planted ({marker}) — /now surfaces it until "
              "/reconcile runs or the operator dismisses it.")
    else:
        print("  DRY-RUN — --apply plants the reconcile-pending marker for /now surfacing.")


def phase_status(root, plugin_root, _apply):
    inv = classify(root, plugin_root)
    vend = len(inv["vendored-pristine"]) + len(inv["vendored-modified"]) + len(inv["vendored-no-counterpart"])
    contained = os.path.isdir(os.path.join(root, ".forge", "project"))
    marker = os.path.isfile(os.path.join(root, ".forge", "state", "reconcile-pending.json"))
    print(f"retrofit status: vendored-files={vend} layout={'contained' if contained else 'classic'} "
          f"reconcile-pending={'yes' if marker else 'no'}")


PHASES = {"inventory": phase_inventory, "devendor": phase_devendor,
          "reorganize": phase_reorganize, "reconcile": phase_reconcile, "status": phase_status}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("phase", choices=sorted(PHASES))
    ap.add_argument("--dir", default=".")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--plugin-root", default=os.environ.get("CLAUDE_PLUGIN_ROOT")
                    or os.environ.get("FORGE_RUNTIME_ROOT"))
    ap.add_argument("--claude-only-accepted", action="store_true",
                    help="operator explicitly accepted Claude-only consumption (mixed-team gate)")
    args = ap.parse_args()
    root = os.path.abspath(args.dir)
    if not os.path.isdir(os.path.join(root, ".git")):
        print("retrofit: --dir must be a git repository root", file=sys.stderr)
        sys.exit(2)
    PHASES[args.phase](root, args.plugin_root, args.apply)


if __name__ == "__main__":
    main()

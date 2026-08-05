#!/usr/bin/env bash
# FORGE /parallel worktree anti-forking audit (Spec 622) — advisory, never blocking.
#
# Detects worktrees created during a /parallel run that the orchestrator did not
# create (SIG-OVN-06: a subagent forked a sibling worktree and ran out-of-scope
# git restore). Classification per `git worktree list` entry (main excluded; main
# is identified by path comparison against `git rev-parse --show-toplevel`, never
# porcelain ordering):
#   - own allowlist `worktrees[]`            -> silent (orchestrator-created)
#   - own `preexisting[]`, recorded in ANY allowlist file (own/sibling,
#     preserved or in-progress)              -> silent (recorded pre-existing)
#   - own `preexisting[]`, recorded nowhere, under <main>/.worktrees/
#                                            -> persistent "unexplained pre-existing"
#                                               advisory (re-emitted EVERY run — never
#                                               silently grandfathered)
#   - own `preexisting[]`, recorded nowhere, outside the /parallel namespace
#                                            -> ONE aggregate line naming every path
#                                               (harness worktrees etc. — visible, not noisy)
#   - NOT preexisting, declared by a sibling allowlist file
#                                            -> "attributed:" line naming the batch —
#                                               ALWAYS PRINTED (attribution, never
#                                               exclusion: forged file content can relabel
#                                               a line, it can never buy silence)
#   - NOT preexisting, declared nowhere      -> "foreign worktree" advisory with the
#                                               inspect-then-remove next-action clause
#                                               (ANY namespace — a live violation never
#                                               lands in the quiet aggregate bucket)
#
# Allowlist file: .forge/state/parallel-created-worktrees-<batch-id>.json
#   {"batch_id","created_at","preexisting":[...],"worktrees":[...],"preserved":bool}
# Written by /parallel at bundle start (preexisting capture) + per worktree creation;
# removed at merge completion ONLY when every listed worktree was actually removed,
# else retained with "preserved": true (preservation-aware lifecycle).
#
# Usage: parallel-worktree-audit.sh <batch-id> [repo-root]
# Exit: ALWAYS 0 (advisory-only — Spec 622 AC 4). Degraded environments (no python)
# emit a warning and exit 0.
set -uo pipefail

BATCH_ID="${1:?usage: parallel-worktree-audit.sh <batch-id> [repo-root]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${2:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

PYBIN="${ROOT}/.forge/bin/forge-py"
if [[ ! -x "$PYBIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then PYBIN="python3"; else PYBIN=""; fi
fi
if [[ -z "$PYBIN" ]]; then
  echo "warning: parallel-worktree-audit degraded (no python available) — audit skipped for batch ${BATCH_ID}"
  exit 0
fi

main_path="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
wtlist_file="$(mktemp)"
git -C "$ROOT" worktree list --porcelain > "$wtlist_file" 2>/dev/null || true

"$PYBIN" - "$ROOT" "$BATCH_ID" "$main_path" "$wtlist_file" <<'PYEOF' || true
import glob, json, os, sys

root, batch_id, main_path, wtlist_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def norm(p):
    return os.path.normcase(os.path.normpath(os.path.abspath(p)))

current = []
try:
    with open(wtlist_file, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line.startswith("worktree "):
                current.append(line[len("worktree "):])
except OSError:
    pass

main_n = norm(main_path) if main_path else ""
namespace = norm(os.path.join(main_path, ".worktrees")) if main_path else ""

state_glob = os.path.join(root, ".forge", "state", "parallel-created-worktrees-*.json")
own = None
siblings = []  # (batch_id, preserved, set-of-normed-paths)
for f in glob.glob(state_glob):
    try:
        with open(f, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        print(f"warning: unreadable allowlist file {os.path.basename(f)} — ignored")
        continue
    bid = str(data.get("batch_id", ""))
    paths = {norm(p) for p in (data.get("worktrees") or [])}
    if bid == batch_id:
        own = data
        own_paths = paths
    else:
        siblings.append((bid, bool(data.get("preserved")), paths))

if own is None:
    print(f"warning: no allowlist file for batch {batch_id} — audit skipped (file missing or already cleaned)")
    sys.exit(0)

own_paths = {norm(p) for p in (own.get("worktrees") or [])}
preexisting = {norm(p) for p in (own.get("preexisting") or [])}
union_declared = set(own_paths)
for _bid, _pres, paths in siblings:
    union_declared |= paths

aggregate = []
for p in current:
    pn = norm(p)
    if pn == main_n:
        continue
    if pn in own_paths:
        continue
    if pn in preexisting:
        if pn in union_declared:
            continue  # recorded pre-existing — silently explained
        if namespace and pn.startswith(namespace + os.sep):
            print(f"unexplained pre-existing worktree: {p} — not created by any recorded /parallel batch; inspect or remove")
        else:
            aggregate.append(p)
        continue
    # appeared during this run
    attributed = False
    for bid, pres, paths in siblings:
        if pn in paths:
            state = "preserved" if pres else "in-progress"
            print(f"attributed: {p} — declared by batch {bid} ({state})")
            attributed = True
            break
    if not attributed:
        print(f"ADVISORY: foreign worktree {p} was not created by this /parallel run — inspect for out-of-scope changes, then remove with 'git worktree remove {p}'")

if aggregate:
    print(f"note: {len(aggregate)} worktree(s) outside /parallel jurisdiction (harness/other): " + ", ".join(aggregate))

for bid, pres, paths in siblings:
    state = "preserved worktrees remain" if pres else "possibly stale from a dead or in-progress run"
    print(f"warning: allowlist from batch {bid} still present ({state}) — its declared paths are attributed above, never silently excluded")

sys.exit(0)
PYEOF

rm -f "$wtlist_file"
exit 0

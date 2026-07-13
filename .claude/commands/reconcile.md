---
name: reconcile
description: "Reconcile git history into the spec corpus — draft stub specs / memory notes for work committed outside FORGE"
workflow_stage: discovery
---
# Framework: FORGE
<!-- multi-block mode: serialized — the Step 3 confirm block and the Step 5 next-action block fire at distinct mechanical steps; each waits for operator response before the next step proceeds. See docs/process-kit/implementation-patterns.md § Multi-block disambiguation rule. -->
Scan git history for commits with no matching spec, cluster them by related files, and
— routed by size — emit **draft retroactive stub specs** (large clusters) or **operator
memory notes** (small ambient changes). This is how FORGE ingests work done outside its
process (non-FORGE collaborators, hotfix-mindset commits) so the spec corpus stays a
faithful map of the codebase. See Spec 486 and `docs/process-kit/reconcile-guide.md`.

> **Scope (authority limit)**: `/reconcile` is **purely additive**. It only creates new
> `draft` specs, operator memory notes, and a scan-window marker. It NEVER edits code,
> NEVER modifies or advances any existing spec, and NEVER transitions a generated stub
> past `draft`. Generated stubs require an explicit human `/implement` to advance.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /reconcile — Ingest git history that landed outside FORGE into the spec corpus.
  Usage: /reconcile [--since <ref>] [--dry-run]
  Arguments:
    --since <ref>   Scan <ref>..HEAD instead of <marker>..HEAD (override the scan window).
    --dry-run       Show the routing plan only; write nothing (no specs, notes, or marker).
  Behavior:
    - Classifies commits: spec-linked (message matches Spec NNN) | process-only
      (docs/sessions, docs/specs, docs/backlog.md, docs/digests) | un-specced.
    - Clusters un-specced commits by shared changed files (union-find).
    - Routes each cluster by size: >= stub_min_files files OR >= stub_min_lines lines
      -> draft stub spec; otherwise -> operator memory note.
    - Generated stubs are Status: draft, Change-Lane: retroactive, with an
      ## Inferred Provenance section. Objective/Scope are INFERRED (caveated);
      Requirements/AC/Test-Plan are placeholders. Nothing auto-advances.
  Config (AGENTS.md): forge.reconcile.stub_min_files (3), forge.reconcile.stub_min_lines (100).
  See: docs/process-kit/reconcile-guide.md, docs/specs/486-git-history-reconcile.md
  ```
  Stop — do not execute any further steps.

---

## [mechanical] Step 1 — Parse arguments and resolve config

1. Parse `$ARGUMENTS` for `--since <ref>` and `--dry-run`.
2. Read thresholds from `AGENTS.md` (`forge.reconcile.stub_min_files`, default 3;
   `forge.reconcile.stub_min_lines`, default 100). Fall back to the defaults if the
   keys are absent.
3. Resolve the **operator memory directory** — the same location `MEMORY.md` lives
   (e.g. `~/.claude/projects/<project-slug>/memory/`). Small clusters become notes
   there; large clusters never touch it.

## [mechanical] Step 2 — Show the plan (read-only)

Run the engine in read-only `--plan` mode and present the routing plan to the operator:

```bash
bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/reconcile_classify.py --plan \
  [--since <ref>] --stub-min-files <N> --stub-min-lines <M>
```

(PowerShell: `python ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/reconcile_classify.py --plan ...`.)

Present the parsed JSON as a short table: the scan range, commits scanned, the
spec-linked / process / un-specced bucket counts, and per-cluster routing (commits,
file count, line count, → stub | note). The bucket counts make silent truncation
impossible — the operator sees exactly what was skipped.

**If `--dry-run`**: STOP here. The plan is the deliverable; nothing is written.

## [decision] Step 3 — Confirm before writing

`/reconcile` writes new `draft` artifacts into the corpus. Present a choice block:

<!-- safety-rule: session-data — /reconcile produces draft specs + memory notes but does not synthesize today's session log; the Spec 320 session-data safety rule does not fire here in practice. Token present to satisfy the Req 4 lint and document that the rule was considered. -->

> **Choose** — type a number or keyword:
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 1 | `apply` | Generate the stubs + notes the plan shows | Run `--apply`; write draft stubs, memory notes, advance the marker |
> | **2** | 2 | `dry-run` | Inspect first; decide later | Re-show the plan; write nothing |
> | **3** | — | `stop` | Defer | End without writing |

At **L3+** with no contentious findings, proceed as `apply` (the artifacts are all
`draft`/notes — reviewable and reversible; the human gate is the later `/implement`).

## [mechanical] Step 4 — Apply

```bash
bash ${CLAUDE_PLUGIN_ROOT:-.}/.forge/bin/forge-py ${CLAUDE_PLUGIN_ROOT:-.}/.forge/lib/reconcile_classify.py --apply \
  [--since <ref>] --stub-min-files <N> --stub-min-lines <M> \
  --memory-dir <operator-memory-dir>
```

The engine advances `.forge/state/reconcile-marker.json` to HEAD **only after every
artifact is written** (atomic / partial-failure-safe — a failed run re-processes the
same range next time, never double-emitting).

## [mechanical] Step 5 — Summary and next action

Report, from the engine's JSON result:
- Stub specs created: `<NNN — path>` (one per large cluster).
- Memory notes created: `<slug — path>` (one per small cluster).
- Counts: clusters found, routed-to-stub vs routed-to-note, spec-linked + process
  commits skipped.
- Marker advanced to `<HEAD short-sha>`.

Then present the next action:

> **Choose** — type a number or keyword:
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 1 | `/implement <NNN>` | Flesh out a generated stub into a real spec | Review a stub, author its Requirements/AC, then build it |
> | **2** | 2 | `/matrix` | Re-rank the corpus including the new drafts | See where the new stubs land in priority |
> | **3** | — | `stop` | Review the stubs offline | End — stubs are `draft`, nothing is pending |

Generated stubs are **draft** and INFERRED — a human must author their Requirements,
Acceptance Criteria, and Test Plan (and verify the inferred Objective) before
`/implement` advances them. `/reconcile` never closes the loop on its own.

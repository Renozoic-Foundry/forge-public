# /reconcile — Ingesting work done outside FORGE

<!-- Last verified: 2026-06-17 (Spec 486) -->

`/reconcile` keeps FORGE's spec corpus a faithful map of the codebase when not every
change flows through `spec → implement → close`. On a shared repo, some commits land
outside FORGE — from collaborators who don't write specs, or from hotfix-mindset
commits. `/reconcile` reads git history, finds the un-specced commits, and turns them
into reviewable artifacts.

## What it does

1. **Classifies** every commit in the scan window into one of three buckets:
   - **spec-linked** — message matches `Spec NNN` (e.g. `Close Spec 485 — …`). Skipped.
   - **process** — touches only `docs/sessions/`, `docs/specs/`, `docs/digests/`, or
     `docs/backlog.md` (and merge/empty commits). Skipped.
   - **un-specced** — everything else. These are reconciled.
2. **Clusters** un-specced commits by shared changed files (transitive — commits that
   touch a common file land in the same cluster).
3. **Routes by size**:
   - **Large cluster** (≥ `stub_min_files` distinct files **OR** ≥ `stub_min_lines`
     changed lines) → a **draft retroactive stub spec**.
   - **Small cluster** → an **operator memory note**.

## What it produces

**Stub specs** (`docs/specs/NNN-reconciled-*.md`):
- `Status: draft`, `Change-Lane: retroactive`, `Retroactive: true`,
  `Reconciled-From: <shas>`.
- An `## Inferred Provenance` section listing source SHAs, authors, dates, and the
  **verbatim commit messages** (fenced, preserved exactly).
- Objective/Scope are **INFERRED** from the diff + messages and explicitly caveated.
- Requirements / Acceptance Criteria / Test Plan are **placeholders** — never
  fabricated. A human authors them before the stub is implemented.

**Memory notes** (in the operator memory dir + a `MEMORY.md` pointer): a one-file
summary of the small change, tagged `type: project`.

## What it never does

`/reconcile` is **purely additive**. It never edits code, never modifies or advances an
existing spec, and never transitions a generated stub past `draft`. The human gate is
the later `/implement` — reconcile only surfaces the work, it does not bless it.

## Usage

```bash
/reconcile                 # scan <marker>..HEAD (or last 50 commits if no marker)
/reconcile --since v1.2.0  # scan an explicit range
/reconcile --dry-run       # show the routing plan only; write nothing
```

The scan-window marker (`.forge/state/reconcile-marker.json`) advances to HEAD **only
after a full successful run**, so an interrupted run safely re-processes the same range
next time (it never double-emits). The marker is operator-writable; because the tool is
additive, a tampered marker only *narrows* the scan (a missed backfill, recoverable via
`--since`) — it can never produce a false "verified" state.

## Configuration

`AGENTS.md` → `forge.reconcile`:

```yaml
forge.reconcile:
  stub_min_files: 3     # cluster → stub spec at >= this many distinct files...
  stub_min_lines: 100   # ...OR >= this many changed lines; else → memory note
```

## Limitations (v1)

- Clustering fidelity on pathological histories (merge commits, rebases, vendored bulk
  imports) is untested — merge/empty-diff commits are treated as `process` and skipped.
- No concurrency lock: assumes one `/reconcile` run at a time in a working tree (safe
  to re-run; marker atomicity prevents corruption).
- Inferred Objective/Scope can be plausibly wrong — always verify before relying on a
  stub. That is why stubs are `draft` and carry the inference caveat.

## Engine

The classification/clustering/routing engine is `.forge/lib/reconcile_classify.py`
(stdlib Python via `.forge/bin/forge-py`, per ADR-359 — cross-platform by
construction). `--plan` is read-only (emits the JSON routing plan); `--apply` writes
the artifacts. Behavioral fixture: `.forge/bin/tests/test-spec-486-reconcile.{sh,ps1}`.

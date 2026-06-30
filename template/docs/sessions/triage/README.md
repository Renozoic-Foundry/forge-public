# Triage inbox (Spec 459)

This directory is the **disposition queue** for scheduled strategy-only routines
(`consensus-vet-pending`, `evolve-scan`, `brainstorm-digests` — see
[`docs/process-kit/scheduled-routines-guide.md`](../../process-kit/scheduled-routines-guide.md)).

Routines are **green / artifact-producing only**: they never advance the spec
lifecycle, expand autonomy, or commit. Each run deposits a Markdown entry here for
the **operator** to disposition. Nothing in this directory changes project state on
its own.

## Entry naming

```
<routine>-<YYYY-MM-DD>[-spec-<NNN>].md
```

Examples:
- `consensus-vet-2026-06-15-spec-461.md`
- `evolve-scan-2026-06-15.md`
- `brainstorm-digests-2026-06-15.md`

## Entry shape

Each entry SHOULD contain:

- **Routine** — which contract produced it (`.forge/loops/<name>.contract.yml`).
- **Run date** — when the routine ran.
- **Sources** — read-only inputs reviewed (digests, drafts, signals, watchlist).
- **Findings** — the surfaced items (spec candidates, vet objections, scan flags).
- **Recommended disposition** — one of: `ready-for-review`, `needs-revision`,
  `graduate-to-spec`, `defer/watch`, `discard`. This is a *recommendation* only.
- **Operator decision** — left blank for the operator to fill in.

## Disposition flow

1. A scheduled routine writes an entry here (the only thing it does to project state,
   plus appending review markers to existing artifacts where its contract allows).
2. The operator reviews entries (surfaced by `/now`) and decides each disposition.
3. The operator — not the routine — runs any lifecycle command (`/spec`,
   `/implement`, `/close`) that a disposition implies.
4. Dispositioned entries are deleted or moved out of the inbox by the operator.

> Routines NEVER run `/implement`, `/close`, `git commit`, or any autonomy/budget
> config write. The triage inbox is the boundary between automated discovery/review
> and operator-authorized action.

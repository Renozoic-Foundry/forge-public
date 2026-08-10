# Tab-Lane Awareness Guide

<!-- Last verified: 2026-04-28 against tab.md, evolve.md, now.md, forge.md, implement.md (Spec 351) -->

Anchor: `tab-lane-awareness-guide`

How `/evolve`, `/now`, `/forge`, and `/implement next` consult the active-tab marker (Spec 353) when emitting their next-action choice blocks. This guide centralizes the "filter or annotate cross-lane options" decision rules so each command can keep its directive small (~5 lines) while staying consistent.

Last updated: 2026-04-28 (Spec 351).

---

## Registry contract

Two sources expose the active tab's lane:

1. **Primary**: `.forge/state/active-tab-*.json` marker (Spec 353). Reads are O(1) via `cat .forge/state/active-tab-*.json` and the schema includes `lane` directly. Marker presence indicates an explicit `/tab register` was performed in this session.
2. **Fallback**: `docs/sessions/registry.md` row(s) with `Status = active`. Used only when the marker is missing — covers operators who never ran `/tab register` but still made manual claims.

The agent reads source 1 first. If absent, falls back to source 2. If neither has an active tab, the command's choice block emits as today (no filtering, no annotation).

When the marker is **stale** (`last_command_at` > 30 minutes ago — Spec 353 § Marker schema pinning), treat it as a soft hint: emit the lane-context preamble but flag the staleness in the menu (e.g., "Tab lane: process-only (stale ~45m). Reconfirm with `/tab refresh` or proceed.").

---

## Per-lane decision rules

| Active lane | Filter | Annotate | Pass through |
|-------------|--------|----------|--------------|
| `process-only` | `implement next`, `close NNN` for non-process-only specs, `/parallel`, `/scheduler` | Cross-lane proposals (e.g., a /now recommendation to draft a feature spec) | `/session`, `/evolve`, `/synthesize`, `/now`, `/note`, `/spec` (for process specs) |
| `feature` | `process-only` lane work routing (e.g., a /now recommendation to draft a process-only spec) UNLESS explicitly chosen | Cross-lane process suggestions (mark them as "lane: process-only") | `/implement`, `/close`, `/parallel`, `/spec` (for feature subjects) |
| `hotfix` | Anything not the active hotfix file/spec | None — hotfix is narrow by design | `/close <hotfix-spec>` only |

**Filter** = drop the row from the choice block entirely (or downgrade rank to `—` and place at the bottom).
**Annotate** = leave the row in the menu but prefix with `(cross-lane: <other-lane>)` so operator sees the boundary cross.
**Pass through** = no change.

The lane is a **soft gate**: filtering and annotating help the operator stay on lane, but the operator can always type a filtered/annotated keyword directly to override.

---

## Fallback behavior

When **no active tab** is detected (no marker AND no active registry row), the command's choice block emits as today — no filtering, no annotation, no preamble. Single-tab operators who never run `/tab register` see zero behavior change.

When the marker is **missing but a registry row is active** (operator manually edited registry.md without running `/tab register`), use the registry row's `Lane` column as the source. Emit the same preamble + filtering rules as if the marker existed.

When the marker is **orphaned** (marker file exists but no matching registry row), treat as no-tab — the registry is authoritative for cross-tab claim history; an orphaned marker without a backing row is a stale local hint.

---

## One-line lane-context preamble

When an active tab is detected, every affected command's choice block is preceded by exactly one line:

```
Tab lane: <lane>. Options below filtered to lane scope.
```

Or, when only annotation applies (no rows filtered):

```
Tab lane: <lane>. Cross-lane options annotated.
```

Or, when stale:

```
Tab lane: <lane> (stale ~Nm; reconfirm with `/tab refresh`). Options below filtered to lane scope.
```

This preamble is the operator's signal that the menu has been adjusted. Skip the preamble entirely when no tab is active.

---

## Worked examples

### `/evolve` exit gate inside a `process-only` tab

```
Tab lane: process-only. Options below filtered to lane scope.

> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `/synthesize` | Consolidate evolve findings into a refined doc |
> | **2** | `/note` | Capture an `[evolve]` scratchpad item |
> | **—** | ~~`implement next`~~ | filtered: cross-lane (feature) |
```

The `implement next` row is filtered (struck through and demoted to `—` for visibility) — not silently removed — so the operator can override by typing `implement next` directly if they want to cross the lane intentionally.

### `/now` recommendations inside a `feature` tab

```
Tab lane: feature. Cross-lane options annotated.

Top recommendation: `/close 351` (drain implemented queue).
Cross-lane: `/spec 359` (process-only — captures the new lane-warning UX gap from today's work).
```

### `/forge` menu with no active tab

```
> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `/now` | Survey state |
> | **2** | `/implement next` | Resume solve loop |
> | **3** | `/session` | Update session log |
```

No preamble, no filtering, no annotation. Behavior identical to pre-Spec-351.

### Regression scenario (Spec 351 AC 9)

**Positive case**: tab marker exists with `lane=process-only`. `/evolve` exit gate filters out `implement next` (struck through with rank `—`).

**Negative case**: no marker, no active registry row. `/evolve` exit gate emits `implement next` as today (no filtering, no preamble).

The marker is read first; the registry.md fallback only applies if marker is absent.

---

## Implementation directive (for command bodies)

Each affected command's choice-block emission point includes a directive of this shape (~5 lines):

```markdown
**Tab-lane awareness (Spec 351)**: Before emitting this choice block, read `.forge/state/active-tab-*.json` (primary) or `docs/sessions/registry.md` rows where `Status = active` (fallback). If an active lane is detected, apply the filter/annotate rules from `docs/process-kit/tab-lane-awareness-guide.md` § Per-lane decision rules and emit the one-line preamble. If no active tab is detected, emit the choice block as today.
```

The guide centralizes the rules; each command body just points to it. This matches Spec 225's "directive + central-guide" reusable pattern (per SIG-225-03).

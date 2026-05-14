# Multi-Tab Quickstart

<!-- Last verified: 2026-04-28 against tab.md, session.md, implement.md, close.md (Spec 353) -->

Anchor: `multi-tab-quickstart`

A practical guide for running 2+ Claude Code chat tabs against the same FORGE repository without stepping on each other. The canonical pattern is **CP/MAT** — one tab building the feature (CP, "Critical Path") and one tab doing process/admin/tracking work (MAT, "Maintenance"). This guide explains when to open a second tab, which lane each gets, where the sync points are, and the sharp edges to avoid.

Last updated: 2026-04-28 (Spec 353).

---

## When to open a second tab

Open a second tab when:

- **Long-running feature work needs admin-level interrupts.** You are mid-`/implement` on a heavy spec but a process bug surfaces (signal-log triage, scratchpad cleanup, backlog drift, an `/evolve` loop is overdue). Open a `process-only` tab to do the admin without losing the feature tab's context.
- **You want to read while you build.** Open a second tab to skim research artifacts, signals, or session logs while the first tab is running a sub-agent (validator, DA, /ultrareview).
- **A hotfix surfaces during a feature implementation.** Don't park the feature work; open a `hotfix` tab against the specific file, ship it, close the tab, return to the feature tab.

**Do NOT open a second tab when:**

- The work fits in the same tab without context switching (most cases).
- You are about to spawn a `/parallel NNN MMM` worktree run — `/parallel` already orchestrates multi-agent execution; you don't need extra tabs on top.
- Two independent feature specs need attention. Run them sequentially in one tab or use `/parallel`. Two `feature`-lane tabs against the same repo is a coordination footgun.

---

## Lane choice

Each tab declares one of three lanes at registration. The lane decides what the tab is "allowed" to touch and which lifecycle commands make sense.

| Lane | Touches | Typical commands | Don't run |
|------|---------|------------------|-----------|
| `feature` | `src/`, `tests/`, `template/.claude/commands/` (when shipping command behavior), spec body for the in-flight spec | `/implement`, `/close`, `/parallel`, `/spec` (for the feature subject) | `/synthesize`, `/evolve --full` (these are reflective, not feature work) |
| `process-only` | `docs/`, `.claude/commands/` (process changes only), `CLAUDE.md`, `AGENTS.md`, scratchpad, backlog | `/session`, `/synthesize`, `/evolve`, `/note`, `/matrix`, `/spec` (for process specs) | `/implement <feature-spec>`, `/close <feature-spec>` (those mutate spec status — wrong tab) |
| `hotfix` | one specific file, the bug fix | `/close <hotfix-spec>` (after `/implement` produced the fix in the feature tab) | spec-number-advancing work; multi-spec lifecycle |

The lane is a **soft gate**, not a hard one. FORGE will surface a one-line warning if you run a lifecycle command whose natural lane doesn't match your tab's declared lane (e.g., `/implement` (feature lane) inside a `process-only` tab) — but the warning is a check, not a refusal. Operator decides.

---

## Sync points

Multi-tab work has four natural sync points where the tabs need to coordinate. Treat each as a checkpoint:

1. **`/tab register` writes the marker.** Each tab gets its own `.forge/state/active-tab-<id>.json` marker on registration. The marker records `{session_id, label, lane, spec_id, tab_started, last_command_at, registry_row_pointer}` and lets lifecycle commands programmatically identify "which row in the registry is mine." Markers are gitignored — they live local to the working tree.
2. **`/implement` writes the spec ID into the registry row's `Spec(s)` column.** When a feature tab starts implementation, the registry row updates to show which spec is in flight. Other tabs see the claim immediately on their next `/now` or `/tab` registration.
3. **`/close` clears the spec ID at completion.** The registry row stays `active` (the tab is still open) but its `Spec(s)` column drops back to `—`. This is the natural "feature tab is between specs" state.
4. **`/tab close` deletes the marker AND closes the registry row.** Explicit only — `/session` no longer auto-closes the row. Operators run `/session` mid-flow (mid-chat checkpoints, post-/close updates) and silent auto-release would surprise them.

**Stale markers**: if `last_command_at` is more than 30 minutes old, lifecycle commands treat the marker as stale and emit a one-line "your tab claim looks stale; reconfirm with `/tab refresh` or `/tab close`" prompt. Missing markers are silent — a single-tab operator who never ran `/tab register` sees no friction.

---

## Common pitfalls

- **Mid-chat `/session` accidentally closing your tab.** This was the primary friction in the pre-Spec-353 design. Fixed: `/session` is now informational about tab state, never mutating. Run `/session` as often as you like; the registry row stays open until you run `/tab close` explicitly.
- **Running `/implement` in a `process-only` tab.** The lane-mismatch warning surfaces; operator usually wants to switch tabs. If the spec is genuinely a process-only change (e.g., updating a runbook), the warning is a false positive — proceed. Don't ignore the warning systematically; it's a real signal most of the time.
- **Two `feature`-lane tabs claiming the same spec.** The conflict-detection check in `/implement` Step 3 will refuse the second tab with "Spec NNN is claimed by tab '<other-label>'." Run `/tab close` in the other tab first.
- **Manually deleting a marker mid-chat.** Documented sharp edge: the chat enters "no tab" state silently. `/session` no longer surfaces "you are in tab X." Runs as if `/tab register` was never called. To recover: run `/tab register` again with the same label/lane. The new marker writes a fresh row in the registry; the old row remains `active` until manually cleaned up.
- **Crossing the merge surface.** Two tabs editing the same file in the working tree is a coordination bug, not a tab feature. Use `/parallel` worktrees for genuine concurrent edits — multi-tab is for **interleaved single-thread-of-execution** work, not parallel writes.

---

## Registry artifacts

Three files have "registry" in their conceptual role; each plays a different part. Knowing which is which prevents confusion:

| File | Purpose | Authority | Lifetime |
|------|---------|-----------|----------|
| `docs/sessions/registry.md` | Cross-tab coordination — who is doing what right now, claim history. Markdown table, hand-edited by `/tab register` and `/tab close`. | **Authoritative** for claim history. | Persists across sessions; rows transition to `closed` but stay in the file as audit trail (or are pruned at /evolve). |
| `docs/sessions/agent-file-registry.md` | `/parallel` orchestrator's dispatch tracking — which sub-agent claimed which file during a parallel worktree run. Generated by `/parallel` Step 3, deleted at `/parallel` Step 12. **Distinct from** `registry.md` — different scope, different lifetime. | **Authoritative** for the in-flight `/parallel` run only. | Ephemeral: created at `/parallel` Step 3, deleted at `/parallel` Step 12. |
| `.forge/state/active-tab-<id>.json` | Per-tab marker — a hint that lets lifecycle commands find their registry row programmatically. **Not authoritative** — deleting a marker does NOT clear the registry row. | **Hint only.** | Ephemeral, gitignored, deleted by `/tab close`. |

If you find yourself confused about which file holds the source of truth, the rule is: **registry.md is for claim history; the marker is for "which row is mine"; agent-file-registry.md is unrelated and only relevant during `/parallel`.**

---

## Dispatch mode comparison

When `/parallel` runs, it creates worktrees and a branch per spec — but the **dispatch mechanism** (how agents actually fan out into the worktrees) is a separate decision. There are three plausible modes. The multi-tab pattern is the canonical recommendation; `EnterWorktree` is a solo-session alternative; the `Agent + isolation: "worktree"` variant is evaluated but not yet shipped.

| Mode | Concurrency | Mechanism | When to use | Status |
|------|-------------|-----------|-------------|--------|
| **Multi-tab** | True parallel (N tabs run independently) | Operator opens N Claude Code tabs, one per worktree. Each tab `cd`s into its worktree, runs `/tab <label> feature NNN`, then `/implement NNN`. Tabs coordinate through the registry (Specs 351/352/353). | Genuine concurrent execution across 2+ specs — the common case for `/parallel`. | **Canonical.** Recommended default. |
| **`EnterWorktree`** | Serialized (one worktree at a time per session) | The `EnterWorktree` tool switches the current session into a worktree; `ExitWorktree` returns to the parent. One worktree per session at any moment. | Solo session that needs to dip into one worktree, do focused work, then return. Single-spec dispatch. Not parallel-dispatch. | **Alternative** for solo-session work. |
| **`Agent` + `isolation: "worktree"`** | True parallel (N sub-agents from one parent) | Would spawn the `Agent` tool with `isolation: "worktree"` per worktree, fanning out from one parent session. | Hypothetical — would let a single tab orchestrate a parallel run without operator-launched tabs. | **Evaluated, not shipped.** Requires a sub-agent dispatch path that does not exist in `/parallel` Step 6 today. File a separate spec if you need it (see Spec 405 Origin § option (b)). |

The earlier prose in `/parallel` Step 6 referencing `EnterWorktree` as the fan-out mechanism was inaccurate — `EnterWorktree` is single-session by design and never performed multi-agent fan-out. Spec 405 corrected the docs without changing operational semantics.

**Choosing between multi-tab and `EnterWorktree`**:

- Have 2+ specs that need to run truly in parallel? → multi-tab.
- Have one spec, want to enter its worktree from your current session for focused work? → `EnterWorktree`.
- Wish you could fan out from a single tab without opening more? → no shipped path today; file a spec.

The multi-tab decision tree (when to open a second tab, lane choice, sync points) lives earlier in this guide. The mode-comparison table above answers the orthogonal question: **given that you're running `/parallel`, how does dispatch happen?**

---

## Acknowledged structural limitations

The markdown registry (`docs/sessions/registry.md`) is hand-edited by `/tab` and is read by lifecycle commands as text. This is structurally limited compared to a JSON file or a small daemon process maintaining a SQLite registry across tabs. Spec 353 acknowledges this and ships the marker primitive on top of the markdown registry — leaving the substrate-replacement decision to a future `/evolve` loop after at least 6 months of real multi-tab usage data.

If you encounter friction the marker doesn't fix (e.g., race conditions on registry edits, JSON parsing errors when commands try to interpret the markdown table), file a signal at `/close` and reference Spec 353 § "Acknowledged structural limitations" so the future spec writer has the trace.

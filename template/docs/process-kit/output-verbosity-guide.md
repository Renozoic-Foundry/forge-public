# Output Verbosity Guide (Spec 225)

## Purpose

FORGE multi-step skills can produce dense, multi-section chat output (KPI tables, calibration deltas, gate-by-gate PASS confirmations, signal pattern dumps, etc.). When operators are moving quickly, that volume becomes noise — it imposes cognitive load when the only question is "what do I need to do next?"

The `forge.output.verbosity` setting in `AGENTS.md` controls how much of that detail appears in the **chat surface**. Detail written to **file artifacts** (session logs, `pattern-analysis.md`, etc.) is **never** affected — full evidence is always preserved on disk.

## Setting

```yaml
forge.output:
  verbosity: lean              # lean (default) | verbose
```

- **`lean`** (default): chat shows only operator-actionable items. Verbose diagnostic content is written to file artifacts; chat surfaces a one-line pointer.
- **`verbose`**: chat preserves the prior full-detail output (backward-compatible behavior).

## Rules

### Always shown (both modes)

These items are NEVER suppressed regardless of setting:

1. **Choice blocks** — every numbered choice block the operator must respond to.
2. **FAILed gates** — full detail (gate name, what failed, remediation).
3. **Push-confirmation prompts** — `git push (yes/no)`, `gh pr create (yes/no)`, etc.
4. **Review Brief human-judgment items** — the "Needs Your Review" section of `/close` Review Briefs.
5. **Operator-input prompts** — anything that pauses for an operator response.
6. **Error / abort messages** — when a command stops with an error.

### Suppressed in lean mode (shown in verbose)

These items appear in chat in verbose mode; in lean mode, they're written to a file artifact and replaced with a one-line pointer (or omitted entirely if purely informational):

1. **Passing-gate confirmations** — `GATE [completeness]: PASS — all required sections filled` and similar PASS lines that don't change behavior. Aggregate at the end as a single summary line: `All gates passed (N/N).`
2. **KPI tables** — full KPI tables (e.g., from `/evolve --full`) go to the session log; chat shows: `KPI summary written to docs/sessions/<file>.md.`
3. **Calibration deltas** — score-rubric calibration deltas, E/TC calibration tables, regret-rate breakdowns. Written to `pattern-analysis.md` or session log; chat shows a one-line pointer.
4. **MCP pin status** — full pin-status report goes to its artifact; chat shows: `MCP pins: all current.` (only if a pin is stale, surface that one item.)
5. **Deprecation scans** — full deprecation scans go to their report file; chat shows a count (`Deprecation scan: 0 active.`) — show details only on a non-zero count.
6. **Signal-by-signal pattern dumps** — full pattern table goes to `docs/sessions/pattern-analysis.md`; chat shows: `Pattern analysis written to docs/sessions/pattern-analysis.md (N patterns).`
7. **Root-cause groupings** — full groupings go to the artifact; chat shows the count and pointer.
8. **Deferred-scope aging** — when no items aged past threshold, omit entirely; show only when an item has aged.
9. **Score-rubric details when not changed** — omit when nothing changed; show the changes when they exist.
10. **Per-step PASS narration** during multi-step commands — emit a final compact summary instead.

### File-artifact contract

When suppressing a section in lean mode:

1. **Write the full content to its appropriate file artifact** (session log, `docs/sessions/pattern-analysis.md`, `tmp/evidence/...`, etc. — same artifact the verbose-mode output would describe).
2. **Emit a one-line pointer in chat** in the form: `<Section name> written to <relative path>.` Or, when content is purely informational (e.g., "all current"), omit the pointer entirely and aggregate into a final summary line.
3. **Never drop content silently** — if the artifact path is unclear, default to the active session log.

## How commands read the setting

Each multi-step command (those listed in Scope below) MUST consult `forge.output.verbosity` from `AGENTS.md` at the start of its execution. The recommended pattern:

```text
# At step 1 (after $ARGUMENTS handling), read AGENTS.md and set:
#   verbosity = forge.output.verbosity  (default: lean)
# Then, at each section that would emit multi-line diagnostic output:
#   if verbosity == "lean":
#     write full content to file artifact
#     emit one-line pointer (or omit if purely informational)
#   else:  # verbose
#     emit full content as before
```

A command that does not consult the setting defaults to **lean** behavior — it should err on the side of suppression for any non-actionable content.

## Worked examples

### /evolve --full (lean mode)

**Verbose mode** would produce ~12 sections including KPI tables, MCP pin status, deprecation scans, signal pattern dumps, calibration deltas, score-rubric review, deferred-scope aging, and the proposal disposition choice block.

**Lean mode** chat output:

```
## /evolve loop 15 — review

Pattern analysis: 3 patterns identified. Full table → docs/sessions/pattern-analysis.md.
Trust calibration: 1 category change recommended. (See choice block below.)
KPI summary written to docs/sessions/2026-04-27-002.md.
MCP pins: all current.
Deprecation scan: 0 active.

[CHOICE BLOCK — Trust calibration recommendations: apply all / apply N / defer / dismiss]

[CHOICE BLOCK — Proposal disposition: P1, P2, P3 ...]

[CHOICE BLOCK — Exit gate]
```

The KPI tables, MCP detail, deprecation scan list, and signal-by-signal pattern dump that verbose mode would have shown all live in `docs/sessions/pattern-analysis.md` and the session log. Operator focus stays on the three choice blocks that need their input.

### /close (lean mode)

**Verbose mode** would emit `GATE [test-execution]: PASS`, `GATE [post-implementation]: PASS`, `GATE [authorization-rule-lint]: PASS`, etc. — one line per gate. Plus full Review Brief with all three sections (Machine-Verified, Needs Your Review, Machine-Handled).

**Lean mode** chat output:

```
## /close 225 — validation

All gates passed (8/8). Detail → docs/sessions/2026-04-27-002.md § Spec 225 close gates.

## Review Brief — Spec 225
**Needs Your Review**:
- AC 6 worked-example completeness — check docs/process-kit/output-verbosity-guide.md (yes/no)
- AC 7 4-mirror parity — confirm the additions; baseline drift pre-existed (yes/no)

[CHOICE BLOCK — close confirmation]
```

The "Machine-Verified" and "Machine-Handled" Review Brief sections are written to the session log; chat shows only "Needs Your Review" plus the choice block.

If any gate FAILs, the FAIL detail appears in full — lean does not suppress failures.

### /session (lean mode)

**Verbose mode** echoes the full session-log entry being written (sections, signals captured, deferred items, etc.).

**Lean mode** chat output:

```
Session log updated: docs/sessions/2026-04-27-002.md (3 spec entries, 2 signals captured).
```

The full content is the session log itself — chat just confirms the write and references the path.

### /matrix (lean mode)

**Verbose mode** prints the full prioritization matrix table to chat.

**Lean mode** chat output:

```
Matrix updated: 14 specs scored. Top 5 → docs/backlog.md (lines 1-12).
```

Operator clicks through to `docs/backlog.md` to see the ranked list. If the operator passes `--print` or `--display`, fall through to verbose (display request is itself an opt-in).

### /now (lean mode)

**Verbose mode** prints the full project-state report (active spec, recent commits, open signals, watchlist, digest review status, etc.).

**Lean mode** chat output:

```
Active: none.
Top backlog: Spec 226 — <title> (score 28).
2 unreviewed digests in docs/digests/. Run /brainstorm --digest.

[CHOICE BLOCK — next action]
```

Recent-commits/signals/watchlist detail goes to the session log if `/now` happens to be the first command in a fresh session; otherwise it's omitted (operator can run `git log` themselves). The choice block is always shown.

## Migration notes

- **Default flipped from verbose to lean** at first ship of Spec 225. Operators who prefer the prior chat-output density set `forge.output.verbosity: verbose` in `AGENTS.md`.
- This is a deliberate breaking change to the chat-output contract. File artifacts are unaffected — historical session logs and pattern analyses retain their full detail.
- Commands authored before Spec 225 that don't yet read the setting default to lean (silent suppression of non-actionable content).

## See also

- `AGENTS.md` § Output verbosity (Spec 225) — the setting itself
- `docs/process-kit/implementation-patterns.md` — choice block conventions (always shown)
- `docs/process-kit/human-validation-runbook.md` — Review Brief structure (Needs Your Review always shown)

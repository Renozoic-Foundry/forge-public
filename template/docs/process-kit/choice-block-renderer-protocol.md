# Choice-Block Renderer Protocol (Spec 347)

Last updated: 2026-04-27 (Spec 347 Phase 1)

This doc defines the **emit-time agent protocol** for rendering a choice block from its canonical YAML data (per `choice-block-schema.md`) into the operator-visible markdown table (per Spec 320 v2.0). When an agent encounters a fenced ```` ```choice-block ```` block while executing a command body, it follows this protocol to produce the rendered output.

This is one of three companion docs introduced by Spec 347:

- `choice-block-schema.md` — data shape
- `choice-block-preconditions.md` — closed vocabulary of named preconditions
- `choice-block-renderer-protocol.md` (this doc) — emit-time protocol

## Precondition evaluation locus

**Where does the precondition boolean get computed?** The agent computes it at emit time, in its current execution context, by invoking the bash one-liner documented for the named precondition in `choice-block-preconditions.md`.

This is intentional design — not delegated to a separate process — because:

- A separate shell-renderer process would require IPC plumbing across the 4 mirror surfaces (canonical/.forge, canonical/.claude, template/.forge, template/.claude) and across operator environments (bash, PowerShell, IDE-extension contexts).
- The closed vocabulary + bash one-liner reference implementations make computation deterministic and operator-readable. The agent invokes the documented one-liner; the boolean is whatever the one-liner exits with.
- The `/consensus 347` round 1 surfaced this concern (DA + CTO key risks). The mitigation is: (a) every named precondition has a bash one-liner that is the contract; (b) the renderer-test harness (`test-choice-block-renderer.sh`) exercises the one-liners against fixture session-state contexts to verify two evaluations agree.

**The agent MUST invoke the documented bash one-liner**, not paraphrase the description. If the agent cannot invoke bash (rare but possible in restricted environments), it falls back to applying the rule prose verbatim — but this fallback is a documented degraded mode, not the default path.

**Future option (deferred to Phase 2 trigger)**: a `forge-render-choice-block.sh` shell helper that owns precondition evaluation entirely. The agent invokes the helper with the YAML block as input; the helper emits the rendered markdown to stdout. This converts the renderer from "agent-followable protocol" to "deterministic non-LLM process." Deferred per Spec 347 Constraints — agent-side rendering with deterministic instructions is sufficient at Phase 1 scale; the shell helper is the natural escalation if the /close pilot demonstrates agent drift.

## Emission protocol (step by step)

When the agent encounters a fenced `choice-block` data block in a command body, it executes these steps in order:

### Step 1 — Parse the YAML

Read the fenced block content. Parse as YAML. If parsing fails: emit a clear error to the operator (do NOT silently skip the block) and halt the command. Schema malformation is a structural defect that requires authoring fix, not runtime workaround.

### Step 2 — Schema validate

Verify all required fields are present (`key`, `rationale`, `what_happens`, `rank` per row). Verify each `precondition` value is in the closed vocabulary. If validation fails: emit a clear error and halt. Static check 6 in `test-choice-block-conventions.sh` should have caught these at commit time, but the runtime check provides defense-in-depth.

### Step 3 — Evaluate preconditions

For each row:

a. If `precondition` is omitted or empty: row is **always-emit** (boolean = true).
b. Else: look up the named precondition in `choice-block-preconditions.md`. Invoke the documented bash one-liner. The exit code determines the boolean (exit 0 = true, non-zero = false).
c. If the bash one-liner cannot be invoked (no shell available): apply the prose evaluation rule verbatim, computing from session state in-context. Record this fallback in the agent's response with a `[degraded-eval]` note for operator transparency.

### Step 4 — Filter rows

Drop rows whose precondition evaluated false. Do **NOT** annotate them as `(N/A)`, do **NOT** preserve their position with a placeholder — they are simply absent from the rendered table. This is the structural fix to the /close 320 chat-surfaced defect.

### Step 5 — Apply session-data safety rule (Spec 320 Req 4)

If the rendered set contains a row whose `key` is `stop` (or any session-ending keyword), and `today_session_log_unsynthesized` evaluates true:

a. Insert a synthetic `session` row at rank `"1"` if not already present:
   ```yaml
   key: session
   rationale: Session log has unsynthesized entries; safety rule fires
   what_happens: Run /session to synthesize today's arc
   rank: "1"
   ```
b. Demote the `stop` row's rank to `"—"`.

This logic is identical to Spec 320 v2.0's session-data safety rule; the renderer applies it at emit time so command authors don't need to handle it per row.

### Step 6 — Sort and number

Sort rows by rank (`"1"` before `"2"` before `"—"`). Within a rank, preserve declaration order. Assign sequential numeric labels: `**1**`, `**2**`, `**3**`, …

If `multi_block: discriminated`: prefix each numeric label with the discriminator letter (e.g., `**A1**`, `**A2**`).

### Step 7 — Emit markdown

Render the table with the Spec 320 v2.0 column order: `# | Rank | Action | Rationale | What happens`. The output is byte-identical (modulo trailing newline) to a hand-authored v2.0 table for the same row set.

If `title:` is set, render it on the line preceding the choice block:

```markdown
> **Choose** — type a number or keyword (<title>):
```

If `title:` is omitted, use the default header:

```markdown
> **Choose** — type a number or keyword:
```

Then emit the column-header row, separator row, and data rows. Add the trailing `> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_` line if the host file conventionally includes it (the host command body controls this — the renderer doesn't add or remove footer lines from the surrounding command-body context).

## Worked example — /close Step 9 with empty queue

Source (in `.forge/commands/close.md` Step 9):

````markdown
```choice-block
title: Pick next
rows:
  - key: implement
    rationale: Top-of-backlog ready; clean transition
    what_happens: Start /implement next (highest-ranked draft)
    rank: "1"
  - key: close NNN
    rationale: Drain remaining implemented queue
    what_happens: Close another implemented spec (type spec number)
    rank: "2"
    precondition: implemented_specs_count_gt_zero
  - key: brainstorm
    rationale: Use when backlog is empty or stale
    what_happens: Generate new spec recommendations
    rank: "—"
    precondition: backlog_has_no_draft_specs
  - key: stop
    rationale: Downgraded if today's session log has unsynthesized entries
    what_happens: End session
    rank: "—"
```
````

Session state at /close 320 (this session, post-close): `implemented_specs_count_gt_zero` = false; `backlog_has_no_draft_specs` = false; `today_session_log_unsynthesized` = false (Summary populated).

Renderer steps:

1. Parse: 4 rows.
2. Schema validate: pass.
3. Evaluate preconditions:
   - `implement` (always-emit): true.
   - `close NNN` (`implemented_specs_count_gt_zero`): false → drop.
   - `brainstorm` (`backlog_has_no_draft_specs`): false → drop.
   - `stop` (always-emit): true.
4. Filter: 2 rows remain (`implement`, `stop`).
5. Safety rule: `today_session_log_unsynthesized` = false → no insertion, no `stop` demotion.
6. Sort: `implement` (rank 1), `stop` (rank —).
7. Emit:

```markdown
> **Choose** — type a number or keyword (Pick next):
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 1 | `implement` | Top-of-backlog ready; clean transition | Start /implement next (highest-ranked draft) |
> | **2** | — | `stop` | Downgraded if today's session log has unsynthesized entries | End session |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_
```

Critically: **the `close NNN` row is absent**. Not `(N/A)`-annotated, not preserved as a placeholder. The renderer cannot emit a row whose precondition is unmet — there's no place in the protocol to insert one.

The /close 320 chat-surfaced defect is structurally impossible under this protocol given a correct precondition declaration (`precondition: implemented_specs_count_gt_zero`).

## Worked example — same source, populated queue

If at a later /close session `implemented_specs_count_gt_zero` = true and `backlog_has_no_draft_specs` = false:

Renderer steps:

1. Parse + validate: pass.
2. Evaluate: `implement`=true, `close NNN`=true, `brainstorm`=false (drop), `stop`=true.
3. Filter: 3 rows remain.
4. Safety rule: irrelevant (Summary populated).
5. Sort: `implement` (1), `close NNN` (2), `stop` (—).
6. Emit:

```markdown
> **Choose** — type a number or keyword (Pick next):
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 1 | `implement` | Top-of-backlog ready; clean transition | Start /implement next (highest-ranked draft) |
> | **2** | 2 | `close NNN` | Drain remaining implemented queue | Close another implemented spec (type spec number) |
> | **3** | — | `stop` | Downgraded if today's session log has unsynthesized entries | End session |
```

The `close NNN` row appears at rank 2 with its declared rationale.

## Edge cases

### Empty fenced block

A `choice-block` fence containing no `rows:` field, or `rows: []`: schema validation fails (a block must have ≥1 always-emit row). The renderer halts; the operator sees the schema error.

### All rows have unmet preconditions

After Step 3 evaluation, zero rows remain. Schema check 6.4 requires ≥1 row to be always-emit at rank `"1"`, which prevents this in well-authored specs. If it nonetheless occurs at runtime (e.g., the always-emit row was malformed and dropped by Step 2): emit an error and halt. Do NOT emit an empty choice block.

### Malformed YAML

Step 1 parse failure: emit error, halt the command. Pre-commit Check 6 should have caught this; the runtime check is defense-in-depth.

### Vocabulary-undefined precondition

Step 2 schema-validate failure when a `precondition:` value is not in `choice-block-preconditions.md`: emit error, halt. Pre-commit Check 6 catches this at commit time; runtime check is fallback.

### Multi-block coexistence with fenced YAML

A command body that emits >1 choice block per agent message MUST set `multi_block: serialized` or `multi_block: discriminated` consistently across all blocks in the file. Mixing `none` with `serialized` is a schema check 6 violation at the file level.

A command body MUST NOT mix Spec 320 v2.0 markdown tables with Spec 347 fenced YAML blocks in the same file (per `choice-block-schema.md` § Coexistence with Spec 320 v2.0).

## Phase 2 trigger

Per Spec 347 Out-of-scope, the remaining 7 commands (now, evolve, consensus, implement, parallel, spec, session) migrate in Phase 2.

> **Phase 2 trigger**: Phase 2 begins when ANY of the following hold:
>
> 1. `/close` has emitted ≥10 fenced-YAML choice blocks across ≥5 distinct sessions without a renderer-drift defect being filed.
> 2. A defect of the same class as the /close 320 chat-surfaced defect (an emitted row whose precondition was unmet) recurs in any non-migrated command.
> 3. 90 days have elapsed since Spec 347 closed without either of the above triggering — at which point the /evolve cycle reviews "still deferred?" and either schedules Phase 2 or extends the trigger window.

This mirrors ADR-320's deferral-with-trigger pattern. Documented here (in addition to spec body) because the protocol doc is the agent's primary reference at runtime — if the trigger fires during Phase 1, future contributors find the migration path here.

## Implementation note: where the renderer "lives"

The renderer is **agent-followable instructions**, not code. The agent's runtime:

- Reads this protocol doc at command-execution time (or has it cached in context).
- Encounters a fenced `choice-block` data block while executing the host command body.
- Applies Steps 1–7 as documented.
- Emits the rendered markdown as part of its operator-visible response.

There is no `forge-render-choice-block` binary in Phase 1. The shell helper is documented as the Phase 2-trigger escalation path (or earlier, if /consensus 347 round-2 elects to add it inline).

The renderer-test harness (`scripts/tests/test-choice-block-renderer.sh`) does NOT exercise the agent's runtime; it exercises the protocol-as-written by simulating the agent's steps deterministically against fixture session-state contexts. The harness is a regression check on the protocol's *correctness*, not on the agent's *adherence*. Agent adherence is a soft signal observed in operator-facing transcripts (the Phase 2 trigger condition #1: "without a renderer-drift defect being filed").

## See also

- [Spec 347](../specs/347-canonical-choice-block-emitter.md) — this spec
- [docs/decisions/ADR-347](../decisions/ADR-347-canonical-choice-block-emitter.md) — design rationale
- [docs/process-kit/choice-block-schema.md](choice-block-schema.md) — data shape
- [docs/process-kit/choice-block-preconditions.md](choice-block-preconditions.md) — closed vocabulary
- [docs/process-kit/implementation-patterns.md § Choice Blocks](implementation-patterns.md) — Spec 320 v2.0 prose convention (legacy form for un-migrated commands)

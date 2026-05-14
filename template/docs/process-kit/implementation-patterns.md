# Implementation Patterns

Last updated: 2026-04-27 (Spec 320 — choice-block ranking + safety rules)

This document collects reusable implementation patterns for FORGE commands and agents. It consolidates the former `choice-block.md` and `parallelism-guide.md`.

---

## Choice Blocks — Standardized Decision Presentation

Version: 2.0 (Spec 025, 2026-03-15; revised by Spec 320, 2026-04-27 — adds Rank + Rationale columns, recommendation-scoring rubric, session-data safety rule, multi-block disambiguation rule)

### Purpose

Decision points in FORGE commands present choices using a standardized "Choice Block" format. The format makes options visually distinct and reduces friction — users type a number or keyword rather than guessing what input is accepted.

### Choice Block Format (v2.0)

```
> **Choose** — type a number or keyword:
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 1 | `<keyword-1>` | <≤80-char rationale or `—`> | <Description of choice 1> |
> | **2** | 2 | `<keyword-2>` | <≤80-char rationale or `—`> | <Description of choice 2> |
> | **3** | — | `<keyword-3>` | <≤80-char rationale or `—`> | <Description of choice 3> |
>
> _(Typed input always works — type the number or keyword directly)_
```

**Column order (load-bearing — Spec 320 Req 2)**: `# | Rank | Action | Rationale | What happens`. Rationale sits **immediately after Action** so the "why" reads alongside the "what" before the secondary detail.

### Column semantics

- **`#`** — sequential numeric label (1, 2, 3, …). What the operator types.
- **`Rank`** — recommendation order. `1` = top recommendation; ties allowed (`1, 1, 2` if two options are equally preferred); `—` for options that are available but not recommended (e.g., `stop`, `abort`, `skip`).
- **`Action`** — the literal keyword the operator may type as an alternative to the number. Short, lowercase, in backticks.
- **`Rationale`** — one short clause (≤80 characters) explaining *why* this option is ranked where it is. Use `—` if the rationale would merely echo the Action label.
- **`What happens`** — the *consequence* of the choice. Describes the outcome, not the action name.

### Recommendation-scoring rubric (lightweight — Spec 320 Req 3)

When you need to justify a ranking (e.g., the operator asks "why is that #1?"), use the **CRBA** rubric. Each axis is scored 1–3; lower-cost / more-reversible / smaller-blast / better-aligned options rank higher.

| Axis | 1 (favourable) | 2 (moderate) | 3 (unfavourable) |
|------|----------------|--------------|------------------|
| **C — Cost** | trivial / cached | minutes of work | hours+ or token-heavy |
| **R — Reversibility** | freely undoable | recoverable with effort | hard-to-undo / destructive |
| **B — Blast-radius** | local / single file | one subsystem | cross-cutting / shared infra |
| **A — Alignment** | directly serves session objective | tangential / nice-to-have | off-mission |

**Rank = sum of CRBA** (lower = better). Ties allowed.

> **Lean over ceremony — sidebar**
>
> Do **not** invent CRBA scores for obvious choices. The rubric is a fallback when ranking is contentious or the operator asks "why?". For most choice blocks, rank by heuristic (consensus-cleared spec ranks above unblocked draft; `commit` ranks above `stop` when there's a dirty tree). Attach explicit scores only when you need to defend a non-obvious ranking. Prose ≥ tables.

### Worked example 1 — `/close` exit choice

Scenario: spec just closed cleanly; today's session log has 2 unsynthesized "started/closed" entries; backlog has 3 ready drafts.

```
> **Choose** — type a number or keyword:
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **1** | 1 | `session` | Unsynthesized entries; safety rule fires | Run /session to synthesize today's arc |
> | **2** | 2 | `implement next` | Top of backlog ready, no consensus block | Start next spec immediately |
> | **3** | 2 | `now` | Lower-cost alternative if context is unclear | Survey project state before committing |
> | **4** | — | `stop` | Available but not recommended | End session without synthesis |
>
> _(Typed input always works — type the number or keyword directly)_
```

CRBA explanation (only emit if asked): `session` C=1 R=1 B=1 A=1=4; `implement next` C=2 R=2 B=2 A=1=7; `now` C=1 R=1 B=1 A=2=5; `stop` would be C=1 R=1 B=1 A=3=6 — but the session-data safety rule forces it to `—` regardless of CRBA.

### Worked example 2 — `/evolve` proposal disposition choice

Scenario: /evolve loop produced 5 proposals; operator must dispose each.

```
> **Block A — proposal dispositions** — type prefix `A1` `A2` ... per proposal:
> | # | Rank | Action | Rationale | What happens |
> |---|------|--------|-----------|--------------|
> | **A1** | — | `approve P1..P5` | Operator-driven; no inherent rank | Approve a specific proposal as draft spec |
> | **A2** | — | `defer P1..P5` | Operator-driven | Move to /matrix for next-cycle review |
> | **A3** | — | `drop P1..P5` | Operator-driven | Discard with revision-log note |
>
> _(Reply with one line per proposal — e.g., `A1 P3`, `A2 P1, P5`, `A3 P2, P4`)_
```

Why `—` on every rank: proposal disposition is operator-driven and has no inherent recommendation; the agent should not nudge `approve` over `drop`. The CRBA rubric does not apply when the agent has no preference.

### Design Rules

1. **Always use numbered rows** — numbers are unambiguous. Never rely on prose to convey options.
2. **Show the keyword** — the exact text the user should type. Keywords are short, lowercase, in backticks.
3. **Describe the consequence** — "What happens" column describes the outcome, not the action name.
4. **Cap at 4 choices per block** — if more options exist, present as subsets or ask a filtering question first.
5. **Always include a typed-input fallback note** — `_(Typed input always works…)_` at the end.
6. **Progressive enhancement** — if a richer UI becomes available (VS Code quickpick, clickable markdown), the same numbered format maps directly. Do not break the typed-input path.
7. **Rank column is required** — every option carries a rank (`1`, `2`, …, or `—` for unranked/available-but-not-recommended).
8. **Rationale column is required** — every option carries a rationale ≤80 characters; use `—` if it would echo Action.

### Session-data safety rule (Spec 320 Req 4)

**Trigger**: When a choice block offers `stop` (or any keyword that ends the session without synthesizing today's work), perform a preflight check on today's session log.

The rule **fires** when **both** conditions hold:

a. **≥1 raw "spec activity" entry** exists in today's session log (`docs/sessions/YYYY-MM-DD-NNN.md`):
   - any `### Spec NNN — started` heading, OR
   - any `### Spec NNN — closed` heading.

b. **The `## Summary` section is *not populated***. "Populated" is defined positively as:
   - The `## Summary` heading is **present**, AND
   - Its body contains **≥1 non-whitespace, non-placeholder line**.
   - **Placeholder text** = template-stub markers, including (case-insensitive): `<summary goes here>`, `<summary>`, `TODO`, `TBD`, `(pending)`, `(empty)`. Add to this list as new placeholder conventions surface.

If the `## Summary` heading is absent, OR the heading is present but the body is empty / whitespace-only / placeholder-only, the rule fires.

**Effect when rule fires**:
- The command MUST rank `/session` at position 1 in the choice block.
- The command MUST NOT rank `stop` (or any session-ending keyword) above `/session`.
- `stop` is downgraded to `—` (available but not recommended); the operator can still select it explicitly.

**Effect when rule does not fire** (Summary populated): rankings proceed normally based on context. `stop` may rank above `/session` if appropriate.

This rule is a near-violation guard; it does NOT replace `/session`'s own gate. The root-cause fix (`/session` refuses to close until Summary is populated) is tracked as a separate follow-up spec.

### Multi-block disambiguation rule (Spec 320 Req 5)

**Trigger**: When a single agent message presents **>1 choice block**.

**Two acceptable patterns**:

#### Pattern A — Discriminator prefixes

Each block uses a unique letter prefix; row labels are `A1, A2, …` for the first block, `B1, B2, …` for the second, etc.

```
> **Block A — disposition for proposal 1** — type `A1` / `A2` / `A3`:
> | # | Rank | Action | Rationale | What happens |
> | **A1** | 1 | `approve` | High value, low cost | Add as draft spec |
> ...

> **Block B — disposition for proposal 2** — type `B1` / `B2` / `B3`:
> | # | Rank | Action | Rationale | What happens |
> | **B1** | 1 | `approve` | High value, low cost | Add as draft spec |
> ...
```

The operator may answer both blocks in one reply (e.g., `A1, B2`) or answer them in any order.

#### Pattern B — Serialization

Present block A; **wait** for the operator's response; then present block B.

#### Precedence — when to serialize vs. discriminate

- **Serialize when block B's contents or availability *depend on* block A's answer.** Example: block A asks "approve or revise?"; if the operator picks `revise`, block B asks for revision focus. Block B does not exist if block A is `approve`.
- **Discriminators are reserved for parallel-disposition cases**: block A and block B are independently dispositionable, with no ordering dependency, and the operator can answer them in any order or together.

When in doubt, serialize. Bare numeric responses (`1`, `2`) are **rejected with a clarification prompt** when multiple blocks are presented; the agent must ask "did you mean A1 or B1?".

#### Mode declaration

Every command body that emits >1 choice block per message MUST declare its mode in a comment or section header within the command body itself. Acceptable forms:

```markdown
<!-- multi-block mode: serialized -->
```
or
```markdown
<!-- multi-block mode: discriminated (A/B) -->
```

The convention enforcement test (`scripts/tests/test-choice-block-conventions.sh`) greps for one of these declarations in any command file that contains >1 choice block.

### Worked example — multi-block discriminated

```
> **Block A — proposal dispositions**:
> | # | Rank | Action | Rationale | What happens |
> | **A1** | — | `approve all` | Operator-driven | Promote all 5 proposals to drafts |
> | **A2** | — | `pick` | Operator-driven | Select specific proposals (type indices) |
> | **A3** | — | `drop all` | Operator-driven | Discard all with rationale recorded |

> **Block B — scratchpad dispositions**:
> | # | Rank | Action | Rationale | What happens |
> | **B1** | — | `review` | Operator-driven | Walk through 3 unresolved [evolve] items |
> | **B2** | — | `defer all` | Operator-driven | Mark all for next /evolve cycle |
>
> _(Reply with one line per block — e.g., `A1` then `B2`, or `A1, B2` together)_
```

### Worked example — serialized

```
> **Block A** — type a number:
> | # | Rank | Action | Rationale | What happens |
> | **1** | 1 | `commit` | Working tree dirty; commit before /implement | Stage and commit pending changes |
> | **2** | — | `skip commit` | Available; merges in dirty tree | Proceed with uncommitted changes |
```

[wait for operator response]

If operator selected `commit`, then:

```
> **Block B (commit message)** — type one of:
> | # | Rank | Action | Rationale | What happens |
> | **1** | 1 | `auto` | Single logical change; let agent draft | Agent drafts one-line message |
> | **2** | — | `dictate` | Operator wants control of message | Pause for operator to type message |
```

### Applied Contexts

| Command | Decision Point | Choice Block Applied | Multi-block mode |
|---------|---------------|---------------------|------------------|
| `/brainstorm` | Step 5 — Create selected specs | yes | n/a (single) |
| `/implement next` | Step 0 — Confirm spec selection | yes | n/a (single) |
| `/close` | Step 8 — Pick next action | yes | n/a (single) |
| `/evolve` | Proposal + scratchpad disposition | yes | discriminated |
| `/matrix` | Confirm corrections + sprint pick | yes | serialized |
| `/consensus` | Round-disposition flow | yes | serialized |

### Convention enforcement

`scripts/tests/test-choice-block-conventions.sh` greps every command file that contains a choice block for:
- `| Rank |` column header
- `| Rationale |` column header (or equivalent positioning between Action and What happens)
- The session-data safety rule token (a comment such as `<!-- safety-rule: session-data -->` or an inline narrative referencing the rule) in any command that emits a choice block with `stop`
- The multi-block mode declaration in any command body containing >1 choice block
- Rationale-cell length ≤80 characters

The test is wired as a pre-commit hook; any new or modified command containing a choice block is auto-validated before commit.

---

## Agent Parallelism — When and How

Last updated: 2026-03-13

### Purpose

Claude Code's Agent tool can run multiple independent tasks in parallel, reducing session wall-clock time. This section identifies which workflow steps are independent and when parallel execution helps vs. hurts.

### When to use parallel agents

**Use when:**
- Multiple independent file reads are needed (e.g., read spec + read backlog + read session log)
- Multiple independent searches (e.g., grep for a pattern in different directories)
- Research tasks that don't depend on each other

**Avoid when:**
- Steps have data dependencies (e.g., read a file, then edit based on what was read)
- The combined output would overwhelm the context window
- The task is simple enough that sequential execution is faster than agent overhead

### Trade-offs

| Factor | Parallel agents | Sequential |
|--------|----------------|------------|
| Wall-clock time | Lower (tasks overlap) | Higher (tasks queue) |
| Context cost | Higher (agent results are verbose) | Lower (direct tool calls are compact) |
| Error handling | Harder (failures may be buried in agent output) | Easier (fail-fast, fix inline) |
| Debugging | Harder (interleaved outputs) | Easier (linear trace) |

**Rule of thumb:** Use parallel agents for 3+ independent reads/searches. Use sequential for edits and anything with dependencies.

### Parallelizable steps by command

#### `/implement`
- **Parallel (step 1):** Read spec file + Read README.md + Read CHANGELOG.md (all needed for pre-implementation checklist)
- **Sequential:** All edit steps (each depends on file content read just before)
- **Parallel (step 6):** Update spec status + Update README + Update CHANGELOG + Update backlog (independent tracking file updates, but each requires a prior Read)

#### `/close`
- **Parallel (step 1):** Read spec file + Read README.md + Read backlog.md (all needed for status checks)
- **Sequential:** Status transitions (each file edit depends on confirmation)
- **Parallel (step 6):** F1 AC spot-check + F4 backlog confirmation (independent checks)

#### `/now`
- **Parallel (all reads):** Read README.md + Read backlog.md + Read latest session log + Read scratchpad (all independent orientation reads)

#### `/session`
- **Parallel (step 1):** Read session template + Read error-log.md + Read insights-log.md + Read scratchpad.md (all needed for population)
- **Sequential:** Writing session log entries (depends on conversation mining)

#### `/matrix`
- **Parallel (step 3-4):** Read all draft spec files for frontmatter comparison (independent reads)
- **Sequential:** Score verification and correction (depends on read results)

---

## Dry-run hermeticity AC pattern

Version: 1.0 (Spec 404, 2026-05-08)

### Purpose

Any command or script that accepts a `--dry-run` (or `--check`, `--no-act`) flag has a hidden contract: **the flag MUST NOT mutate any persistent state**. A dry-run that quietly writes a temp file, modifies a target dir, or appends to a log violates this contract — and the violation is invisible to ordinary tests, because tests typically only assert on stdout/exit code, not on filesystem state before vs after.

### The pattern

Every command/script accepting `--dry-run` MUST have an acceptance criterion of this shape:

> Given a staging directory `D` containing a fixed reference set of files (typically empty), running `<command> --dry-run` (with all other flags) leaves `D` byte-identical to its pre-run state. Verified by computing a SHA-256 manifest of `D` before and after the run and asserting the two manifests match.

### Canonical structure

| Element | Specification |
|---------|---------------|
| **Setup** | Create an empty (or fixed-content) staging directory `D`. Compute pre-run manifest `H_before`. |
| **Invocation** | Run the command with `--dry-run` and any other flags representative of normal use. Capture exit code. |
| **Byte-identity assertion** | Compute post-run manifest `H_after`. Assert `H_before == H_after`. |
| **Exit code** | Assert exit code is 0 (success) — a `--dry-run` that errors out is also a defect. |
| **Negative test (paired)** | Same setup, but invoke a command that DOES mutate `D`. Assert manifest differs. Without this paired negative, the helper itself is unverified. |

### Definition of byte-identity

Byte-identity is computed via the helper `assert-hermetic-dry-run.{sh,ps1}` as:

```
SHA-256( sorted lines of "<sha256-of-file>  <relative-path>" for every file under D )
```

This deliberately **excludes** mtime, atime, ownership, uid/gid, and inode. It includes file contents and the set of paths. Symlinks are followed (their target's contents count). Empty directories are not represented in the manifest.

### Helper

`assert-hermetic-dry-run.sh` (and `.ps1`) at `.forge/bin/tests/lib/`. Calling convention:

```bash
# bash
source .forge/bin/tests/lib/assert-hermetic-dry-run.sh
assert_hermetic_dry_run "<staging-dir>" -- <command> [args...]
# Returns 0 if hermetic, non-zero if the command mutated the dir.
```

```powershell
# PowerShell
. .forge/bin/tests/lib/assert-hermetic-dry-run.ps1
Assert-HermeticDryRun -StagingDir <path> -Command { <scriptblock> }
```

### Worked example

```bash
TMPDIR=$(mktemp -d)
source .forge/bin/tests/lib/assert-hermetic-dry-run.sh
if assert_hermetic_dry_run "$TMPDIR" -- bash scripts/some-script.sh --dry-run --target "$TMPDIR"; then
    echo "PASS: --dry-run is hermetic"
else
    echo "FAIL: --dry-run mutated staging dir"
    exit 1
fi
```

### When to apply

Apply this pattern's AC to a spec whenever the spec adds, modifies, or audits a command/script that exposes a `--dry-run` flag.

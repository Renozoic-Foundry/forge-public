# Long-Running Task Patterns

Last updated: 2026-04-10

## Purpose

Large implementations often span multiple sessions and involve groups of related specs. This guide codifies patterns for breaking work into spec batches, handing off context between sessions, and persisting memory across the session boundary. It complements the [Implementation Patterns — Parallelism](implementation-patterns.md#agent-parallelism--when-and-how) (which covers within-session parallelism) with across-session coordination patterns.

---

## 1. Spec Batching Strategies

Not all specs should be implemented one at a time. Grouping related specs into batches reduces overhead and makes cross-cutting changes coherent.

### Parallel-safe batches

Specs can run in parallel (via `/parallel`) when they meet all of these criteria:

- **No file overlap** -- the specs touch different files or different sections of the same file
- **No data dependency** -- no spec's output is another spec's input
- **No ordering constraint** -- the specs can close in any order without breaking anything

### Sequential chains

Specs must be sequenced when:

- One spec's implementation changes interfaces that another spec depends on
- A later spec refines or extends what an earlier spec introduces
- Testing the later spec requires the earlier spec to be closed first

### Grouping heuristics

| Signal | Batch type |
|--------|------------|
| Specs touch the same subsystem but different files | Parallel-safe |
| Spec B references "as implemented by Spec A" | Sequential chain (A then B) |
| Specs share a test fixture or environment setup | Sequential or stagger (setup spec first) |
| Specs are independent process-kit additions | Parallel-safe |
| Specs modify the same config file | Sequential chain |

### Worked example

Suppose the backlog has five specs ready:

| Spec | Description | Files touched |
|------|-------------|---------------|
| 201 | Add `/lint` command | `.forge/commands/lint.md` |
| 202 | Add `/fmt` command | `.forge/commands/fmt.md` |
| 203 | Update scoring rubric dimensions | `docs/process-kit/scoring-rubric.md` |
| 204 | Add CI integration to `/close` | `.forge/commands/close.md`, `scripts/ci-check.sh` |
| 205 | Add CI status display to `/now` | `.forge/commands/now.md`, `scripts/ci-check.sh` |

**Batch plan:**

- **Batch A (parallel):** Specs 201, 202, 203 -- no file overlap, no dependencies.
  - Run: `/parallel 201, 202, 203`
- **Batch B (sequential):** Spec 204 then 205 -- both touch `scripts/ci-check.sh`, and 205 depends on the CI integration that 204 introduces.
  - Run: `/implement 204`, close it, then `/implement 205`

This completes five specs in three effective sessions instead of five sequential ones.

---

## 2. Session Handoff Checklist

Every session that ends mid-implementation must capture enough context for the next session (whether you, another person, or another agent picks it up). Use this checklist before ending any session involved in long-running work.

### Before ending the session

- [ ] **Summary of completed work** -- which specs moved forward, what was implemented, what was tested
- [ ] **Open blockers** -- anything that prevented completion (failing tests, unclear requirements, missing dependencies)
- [ ] **Next actions** -- specific, actionable steps for the next session (not vague "continue work")
- [ ] **Memory updates** -- any discoveries that should persist (added to CLAUDE.md memory or session log signals)
- [ ] **Spec status accuracy** -- each spec's status field matches reality (`draft`, `in-progress`, `implemented`, `closed`)
- [ ] **Scratchpad review** -- open notes in `docs/sessions/scratchpad.md` are current and tagged

### Handoff note format

When context must transfer to a different person or agent, include a structured handoff block in the session log:

```
## Handoff — Session YYYY-MM-DD-NNN

### Completed
- Spec 201: implemented, tests passing
- Spec 202: implemented, awaiting human validation

### Blocked
- Spec 204: CI integration requires `CI_TOKEN` env var not yet configured

### Next actions
1. Run `/close 201` and `/close 202` after human validation
2. Configure `CI_TOKEN` in project environment, then `/implement 204`
3. After 204 closes, `/implement 205` (depends on 204)

### Memory updates made
- Added CI token requirement to CLAUDE.md project notes
- Logged signal: missing env var documentation pattern
```

---

## 3. Memory Persistence Patterns

FORGE provides three persistence mechanisms. Each serves a different purpose and lifespan.

| Mechanism | Lifespan | Use for | Updated by |
|-----------|----------|---------|------------|
| **Session logs** (`docs/sessions/`) | Permanent (append-only) | What happened in a session, signals, decisions, evidence | `/session` at session end |
| **CLAUDE.md memory** | Permanent (editable) | Cross-session facts, environment notes, project conventions | Manual or memory tool |
| **Scratchpad** (`docs/sessions/scratchpad.md`) | Temporary (consumed and cleared) | In-flight notes, open questions, deferred items | Any command, cleared by `/session` |

### When to use each

**Session logs** -- always. Every session ends with a session log. This is FORGE's non-negotiable rule. Session logs are the primary audit trail.

**CLAUDE.md memory** -- for facts that should influence every future session:
- Environment quirks discovered during implementation
- Naming conventions or patterns established by completed specs
- Known limitations or constraints that affect future work
- Dependency relationships between subsystems

**Scratchpad** -- for items that need attention but not permanent storage:
- Questions to ask the user next session
- Ideas triggered during implementation that are not yet specs
- Temporary notes about work-in-progress state
- Items tagged `[evolve]` for the next `/evolve` review

### Memory flow across sessions

```
Session N                          Session N+1
---------                          -----------
Work produces discoveries    -->   /now reads session log + memory
  |                                  |
  v                                  v
/session captures to log     -->   Agent has full context
  |                                  |
  v                                  v
Key facts --> CLAUDE.md      -->   Available in system prompt
Temp notes --> scratchpad    -->   /now surfaces open items
Signals --> session log      -->   /evolve detects patterns
```

---

## 4. Command Integration for Multi-Session Work

These FORGE commands form the multi-session coordination toolkit:

### `/parallel` -- batch execution within a session

- Use to implement multiple independent specs in a single session
- Feed it a comma-separated list of spec numbers: `/parallel 201, 202, 203`
- Each spec runs as a sub-agent; results are collected and reported together
- Best for parallel-safe batches (see Section 1)
- See [Implementation Patterns — Parallelism](implementation-patterns.md#agent-parallelism--when-and-how) for within-session parallelism details

### `/evolve` -- quality gate across sessions

- Run after each spec reaches `implemented` (fast path) or monthly (full review)
- Detects acceptance criteria drift that accumulates across sessions
- Reviews signal patterns to identify systemic gaps
- Proposes new specs when patterns reach threshold severity
- Critical for long-running work where context rot is highest risk

### `/session` -- session boundary capture

- Mandatory at end of every session -- no exceptions
- Captures: completed specs, open blockers, signals, decisions, evidence references
- The session log is the primary handoff artifact for the next session
- Include a Handoff block (Section 2) when work continues in the next session

### `/handoff` -- structured context transfer

- Use at session end or when transferring work to another person or agent
- Prints full validation checklists (not abbreviated like `/close`)
- Reviews scratchpad for unresolved items
- Produces a Handoff Summary block with next recommended spec
- Preferred over `/session` alone when the next session will be run by a different operator

### `/now` -- session start orientation

- First command in every new session: `/now`
- Reads the latest session log, backlog, and scratchpad
- Surfaces what was in progress, what is blocked, and what is next
- The bridge between the previous session's `/session` output and the current session's work

### Multi-session workflow

```
Session 1:  /now --> /implement 201 --> /implement 202 --> /session
Session 2:  /now --> /implement 203 --> /evolve --> /session
Session 3:  /now --> /close 201,202,203 --> /implement 204 --> /session
Session 4:  /now --> /implement 205 --> /close 204,205 --> /session
```

---

## 5. Anti-Patterns and Failure Modes

### Context rot

**Symptom:** The agent makes decisions that contradict earlier sessions because it has lost context about why something was done a certain way.

**Cause:** Session logs are too terse, CLAUDE.md memory is not updated, or `/now` is skipped at session start.

**Prevention:**
- Always run `/now` at session start
- Write substantive session logs (not just "implemented spec 201")
- Promote durable decisions to CLAUDE.md memory
- Use `/evolve` to catch drift before it compounds

### Orphaned specs

**Symptom:** Specs sit in `in-progress` for multiple sessions without advancing. The backlog accumulates half-finished work that blocks new specs.

**Cause:** A session switches to higher-priority work without capturing the in-progress spec's state, or a sequential chain breaks when an earlier spec stalls.

**Prevention:**
- Before switching focus, update the spec's status and add a scratchpad note with resume instructions
- Use the session handoff checklist (Section 2) even for mid-session context switches
- During `/evolve`, flag any spec that has been `in-progress` for more than two sessions

### Lost handoff context

**Symptom:** A new session or operator starts from scratch because there is no record of what the previous session decided or discovered.

**Cause:** The session ended without running `/session`, or the handoff block was omitted for multi-session work.

**Prevention:**
- Run `/session` at end of every session (this is a FORGE hard rule)
- Include a Handoff block when work spans sessions (Section 2)
- Use `/handoff` instead of just `/session` when transferring to a different operator

### Batch dependency violations

**Symptom:** Parallel-executed specs produce merge conflicts or inconsistent state because they had hidden dependencies.

**Cause:** File overlap or data dependencies were missed during batch planning.

**Prevention:**
- Before running `/parallel`, list every file each spec will touch
- If any file appears in more than one spec, move those specs to a sequential chain
- Review the worked example in Section 1 for the grouping heuristics

### Memory overload

**Symptom:** CLAUDE.md memory grows so large that the agent spends excessive context on reading it, or critical items are buried among trivial ones.

**Cause:** Every discovery is promoted to CLAUDE.md without triage; nothing is ever removed.

**Prevention:**
- Only promote facts to CLAUDE.md that affect future sessions (not just the current one)
- Use session logs for session-specific details
- Periodically review and prune CLAUDE.md during `/evolve` full reviews

---

## Claude Code Built-in Tools for Long Sessions

Claude Code provides several built-in features that complement FORGE's long-running task patterns:

### /compact — Context compression
When a session grows large (multiple /implement + /close cycles, or /evolve reviews), use `/compact` to compress conversation history. Optionally add focus instructions: `/compact focus on Spec 197 implementation` to preserve relevant context while shedding earlier work.

**When to use**: After completing a spec closure, before starting the next implementation. Especially valuable after /evolve full reviews which consume significant context.

### /loop — Recurring automated checks
Run a prompt on a fixed or dynamic interval. Useful for monitoring tasks during implementation:
- `/loop 5m check if copier template renders clean` — watch for template breakage while editing
- `/loop check the test suite` — dynamic interval, Claude picks the pace

**When to use**: During refactoring sessions where you want continuous validation without manually re-running checks.

### /context — Context usage visualization
Shows a visual grid of what's consuming your context window. Helps diagnose context bloat and identify which tool results or file reads are consuming the most space.

**When to use**: When responses start feeling less focused or when you suspect context overflow is imminent.

### Monitor tool — Stream background processes
Streams output from a background process (build, test suite, deploy) directly into the conversation. More token-efficient than /loop for continuous watching.

**When to use**: When running long builds or test suites where you want to react to output in real-time.

---

## Cross-References

- [Implementation Patterns — Parallelism](implementation-patterns.md#agent-parallelism--when-and-how) -- within-session parallel execution patterns and trade-offs
- [Runbook](runbook.md) -- end-to-end delivery workflow including spec lifecycle
- [Checklists](checklists.md) -- pre/post-implementation and process health checklists
- [Human Validation Runbook](human-validation-runbook.md) -- section-based validation for human review

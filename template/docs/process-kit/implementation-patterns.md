# Implementation Patterns

Last updated: 2026-03-27

This document collects reusable implementation patterns for FORGE commands and agents. It consolidates the former `choice-block.md` and `parallelism-guide.md`.

---

## Choice Blocks — Standardized Decision Presentation

Version: 1.0 (Spec 025, 2026-03-15)

### Purpose

Decision points in FORGE commands present choices using a standardized "Choice Block" format. The format makes options visually distinct and reduces friction — users type a number or keyword rather than guessing what input is accepted.

### Choice Block Format

```
> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `<keyword-1>` | <Description of choice 1> |
> | **2** | `<keyword-2>` | <Description of choice 2> |
> | **3** | `<keyword-3>` | <Description of choice 3> |
>
> _(Typed input always works — type the number or keyword directly)_
```

### Design Rules

1. **Always use numbered rows** — numbers are unambiguous. Never rely on prose to convey options.
2. **Show the keyword** — the exact text the user should type. Keywords are short, lowercase.
3. **Describe the consequence** — "What happens" column describes the outcome, not the action name.
4. **Cap at 4 choices per block** — if more options exist, present as subsets or ask a filtering question first.
5. **Always include a typed-input fallback note** — `_(Typed input always works…)_` at the end.
6. **Progressive enhancement** — if a richer UI becomes available (VS Code quickpick, clickable markdown), the same numbered format maps directly. Do not break the typed-input path.

### Applied Contexts

| Command | Decision Point | Choice Block Applied |
|---------|---------------|---------------------|
| `/brainstorm` | Step 5 — Create selected specs | yes |
| `/implement next` | Step 0 — Confirm spec selection | yes |
| `/close` | Step 8 — Pick next action | yes |

### Example

```
> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `all` | Create all 3 recommendations as specs immediately |
> | **2** | `1,3` | Pick specific recommendations (type the numbers) |
> | **3** | `skip` | Note recommendations; decide later |
>
> _(Typed input always works — type the number or keyword directly)_
```

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

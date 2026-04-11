# Context Isolation Guide

When AI agents work in long conversation sessions, accumulated context degrades output quality. This guide covers when to start fresh, what to pre-load, and how to hand off state between contexts.

**Core principle**: The spec is the research phase, codified. An agent with spec context (domain knowledge, constraints, acceptance criteria) produces fundamentally different solutions than one working from code alone. What you load into context determines the ceiling of what the agent can produce.

---

## Signs of context degradation

Watch for these signals that the current context window is no longer serving the task well:

| Signal | What it looks like | Severity |
|--------|--------------------|----------|
| **Repeated reads** | Agent re-reads a file it loaded 10 minutes ago | Early warning |
| **Hallucinated paths** | Agent references files or functions that don't exist | Moderate |
| **Missed acceptance criteria** | Agent marks an AC as done when it isn't | Serious |
| **Contradicted decisions** | Agent reverses a decision made earlier in the session without acknowledging the change | Serious |
| **Circular reasoning** | Agent proposes an approach, abandons it, then proposes it again | Moderate |
| **Scope drift** | Agent starts fixing things outside the spec without flagging it | Early warning |
| **Decreasing specificity** | Agent responses become vague or generic where earlier ones were precise | Early warning |

When you see 2+ of these signals, it's time for a fresh context — not a longer conversation.

---

## When to start a fresh context

**Always start fresh for:**
- A new spec implementation (each `/implement` should ideally start in a clean context)
- Work that follows a context compaction boundary (session summary injected)
- Switching between unrelated specs in the same session

**Consider starting fresh when:**
- The conversation exceeds ~50 turns
- You've been debugging the same issue for >15 minutes without progress
- The agent's last 3 responses show degradation signals above
- You're switching from research/planning mode to implementation mode

**No need to start fresh for:**
- Sequential steps within a single spec implementation
- Quick follow-up questions about work just completed
- `/close` immediately after `/implement` (the spec file carries the context)

---

## What to pre-load by task type

The right context for each task type. Load these files at the start of a fresh context (Claude Code loads CLAUDE.md and AGENTS.md automatically; the rest need explicit reads or slash command invocation).

### `/implement` — spec implementation

| Priority | File | Why |
|----------|------|-----|
| Auto-loaded | `CLAUDE.md`, `AGENTS.md` | Framework rules and agent config |
| Essential | `docs/specs/NNN-*.md` (the spec) | Acceptance criteria, scope, requirements — this is the ceiling |
| Essential | Source files in scope | The code being modified |
| Recommended | `docs/backlog.md` (spec's row only) | Dependencies, score context |
| If available | Related closed specs | Prior decisions and trade-offs |
| If available | `docs/decisions/adr-*.md` (relevant) | Architectural constraints |

### `/close` — validation and close

| Priority | File | Why |
|----------|------|-----|
| Auto-loaded | `CLAUDE.md`, `AGENTS.md` | Framework rules |
| Essential | `docs/specs/NNN-*.md` (the spec) | ACs to verify, evidence to check |
| Essential | Changed files (from spec's Implementation Summary) | What to validate |
| Recommended | `docs/sessions/signals.md` (tail) | Recent signals for retro |
| Recommended | `docs/backlog.md` | For matrix step |

### `/brainstorm` — idea generation

| Priority | File | Why |
|----------|------|-----|
| Auto-loaded | `CLAUDE.md`, `AGENTS.md` | Framework rules |
| Essential | `docs/backlog.md` | Current priorities and gaps |
| Essential | `docs/sessions/signals.md` | Recurring patterns |
| Essential | `docs/sessions/scratchpad.md` | Open ideas |
| Recommended | `docs/digests/` (unreviewed) | External signals |
| Recommended | `docs/sessions/watchlist.md` | Trigger conditions to check |

### `/evolve` — process review

| Priority | File | Why |
|----------|------|-----|
| Auto-loaded | `CLAUDE.md`, `AGENTS.md` | Framework rules |
| Essential | `docs/sessions/signals.md` | Pattern analysis source |
| Essential | Last 2-3 session logs | Recent work context |
| Essential | `docs/backlog.md` | Current state |
| Recommended | `docs/sessions/scratchpad.md` | Open items |
| Recommended | `docs/sessions/watchlist.md` | Items under observation |

### `/session` — session log capture

| Priority | File | Why |
|----------|------|-----|
| Auto-loaded | `CLAUDE.md`, `AGENTS.md` | Framework rules |
| Essential | Conversation context | The session being logged (already in context) |
| Essential | `docs/sessions/_template.md` | Log format |
| Recommended | Previous session log | Continuity |

---

## Handoff patterns between contexts

When you end one context and start another, the bridge is the **spec file** and the **session log**. These are the persistent artifacts that carry state across context boundaries.

### Mid-spec handoff (switching contexts during implementation)

1. **Before ending**: Run `/session` to capture decisions, progress, and blockers
2. **In the spec file**: Update the Evidence section with partial progress; note which ACs are done
3. **Checkpoint file** (Spec 123): If the spec is complex, write a checkpoint to `.forge/state/checkpoint-NNN.json` with current step, completed ACs, and remaining work
4. **In the new context**: Read the spec file first (it has the full picture), then the session log (for decisions and context), then the checkpoint (for exact resumption point)

### Cross-spec handoff (spec A done, starting spec B)

1. **Close spec A properly**: `/close` captures signals and updates the backlog
2. **Start fresh**: New context for spec B
3. **Pre-load spec B**: The spec file carries forward all context from when it was written
4. **Check dependencies**: If spec B depends on A, read A's implementation summary for file locations and patterns

### Session-to-session handoff (resuming tomorrow)

1. **End of session**: `/session` is mandatory — this is the bridge
2. **Start of next session**: `/now` reads the session log and presents the state
3. **Context snapshot**: `docs/sessions/context-snapshot.md` (written by `/now`) gives subsequent commands a quick-read summary instead of re-reading multiple files

---

## Anti-patterns

| Anti-pattern | Why it fails | Better approach |
|-------------|-------------|-----------------|
| Loading the entire codebase into context | Dilutes signal; agent can't prioritize | Load only files in the spec's scope |
| Continuing a degraded conversation "just to finish" | Output quality won't recover | Start fresh with the spec file as your anchor |
| Skipping `/session` before ending | Next session starts from zero | Always capture state before ending |
| Loading session logs instead of spec files | Session logs capture *what happened*, not *what to do* | Spec file is the primary context; session log is supplementary |
| Re-explaining decisions verbally instead of reading the spec | Verbal re-explanation is lossy and inconsistent | Read the spec — it's the canonical record |

---

## Key insight: specs are context engineering

The spec isn't just a planning document — it's a **context engineering artifact**. When you write clear acceptance criteria, specific scope boundaries, and explicit requirements, you're pre-loading the agent's context with exactly the information it needs to produce good output.

A well-written spec in a fresh context will outperform a vague spec in a long-running conversation every time. Invest in spec quality; the implementation context follows.

Source: SkyPilot research-driven agents study (2026-04-09) demonstrated that agents with research context achieve +15% performance vs +0.6% for code-only agents. The spec is the research phase, codified.

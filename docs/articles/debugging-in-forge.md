# FORGE Doesn't Have a Debug Command — And That's the Point

**How an AI-first development framework turns every debugging conversation into a process improvement engine.**

*Brian Carty — April 2026*

---

## TL;DR

A developer reviewing FORGE flagged a gap: *where's debugging?* It's one of the biggest parts of development, and debugging sessions produce the richest feedback for improving how you work.

FORGE's answer: the conversation between `/implement` and `/close` **is** the debugging session. Every time an operator tells the AI agent "that's not right" and works through a fix, FORGE captures that interaction as a structured signal — an Error Autopsy (EA) or Chat Insight (CI). Those signals accumulate across sessions, and a pattern analysis engine detects when isolated incidents form systemic trends. When three or more signals cluster around the same root cause, FORGE recommends a spec to fix the process itself — not just the bug.

Over 240 closed specs and 35 days of active development, this system captured 55 error autopsies and 142 chat insights. Those signals generated 7 pattern analysis cycles, which directly triggered the creation of new specs — including one that escalated from a prose instruction to a non-bypassable runtime hook after the same class of failure recurred four times.

No separate debug mode. No additional ceremony. Just structured signal capture during the work you're already doing, feeding a compounding improvement loop.

---

## The Feedback

An internal developer reviewed FORGE and immediately identified what he saw as a gap:

> *"Unless he just didn't get to this part, [the demo] left one of the biggest parts of development: debugging. Providing debugging insight to users will be crucial. And more than just asking Claude to figure out what happened. Debugging sessions provide the richest feedback for your post-mortem analysis."*

He was right about the value. Debugging sessions *are* the richest signal source. But the solution isn't a `/debug` command — it's recognizing that FORGE already captures debugging signals as a natural byproduct of how it works.

## The Reframe: You're Already Debugging

In a FORGE workflow, the operator runs `/implement` to build a spec's requirements. What happens next — the back-and-forth conversation where the operator identifies problems, questions assumptions, and works with the AI agent to resolve them — that *is* the debugging session. It's not a separate phase. It's the implementation phase doing its job.

The question isn't "how do we add debugging support." It's "how well are we capturing the signals that emerge from debugging, and are those signals feeding back into process improvement?"

FORGE answers this with three signal types that operate at different scopes.

## The Signal System

### Error Autopsies (EA) — "What went wrong and why"

When something breaks during a session — a test fails, a gate fails, the operator corrects the agent — the agent logs it as a candidate Error Autopsy. At session end, the agent scans the full conversation and drafts EA entries:

```
### EA-015: copier update does not restore locally-missing files
- Found via: consumer project investigation — 75 files missing after copier update
- Error: copier update only applies diffs between template versions. Files present
  in both versions unchanged are assumed to exist locally.
- Root cause: Copier is a diff-and-patch tool, not a sync tool.
- Prevention: Add Step 0 to /forge stoke — render template to temp dir, compare
  manifest, auto-restore missing files before running copier update.
- Spec: 068 (closed)
```

Every draft EA requires operator confirmation before it's written to the persistent log. The agent proposes; the human approves, edits, or drops.

**55 error autopsies** have been captured across the project's lifetime.

### Chat Insights (CI) — "What did this conversation teach us"

Not every signal is a bug. When the operator makes a strategic decision, corrects the agent's approach, or validates a non-obvious pattern, the agent captures it as a Chat Insight. The name is deliberate: these insights emerge from the *chat itself* — the natural conversation between human and AI.

```
### CI-053: Human validation is inviolable — no auto-chain to /close
- Session: 2026-03-30-001
- Source: user correction — "fundamental violation of EGID and our principle
  of human validation"
- Insight: The auto-chain from /implement to /close allowed the agent to confirm
  its own deliverables — the exact scenario evidence gates are designed to prevent.
- Action: Spec 142 (Remove Auto-Chain from /implement to /close)
```

Chat Insights capture corrections *and* confirmations. When an unusual approach works, that's a signal too — recording it prevents future sessions from second-guessing a validated decision.

**142 chat insights** have been captured.

### Unified Signals (SIG) — "What did closing this spec teach us"

When a spec is closed via `/close`, the agent runs an inline retrospective across three lenses — content, process, and architecture:

```
### 2026-04-13 — Spec 235 closed (Automated README Stats Maintenance)

- [process] DA FAIL gate caught a fundamental spec premise error (--fix flag
  doesn't exist) and forced scope expansion before implementation. The DA review
  paid for itself on a spec that would have produced a silently broken /close chain.
- [architecture] The `|| true` pattern for /close chain steps is essential — any
  step that can exit non-zero must be wrapped to prevent aborting the entire workflow.
```

SIG entries are higher-level than EA or CI — they capture what the full arc of a spec's lifecycle revealed, not a single conversation moment.

### The Capture Flow

```
Operator says "that's not right" during implementation
  │
  ├─ Agent fixes the immediate problem (the solve)
  │
  ├─ At /session: agent drafts EA/CI entries from the conversation
  │   └─ Operator confirms, edits, or drops each entry
  │
  ├─ At /close: agent runs structured retrospective (SIG entries)
  │   └─ Operator reviews signal drafts
  │
  └─ At /evolve: pattern analysis engine scans accumulated signals
      └─ Clusters of 3+ related signals → spec recommendation
```

The operator stays in control at every gate. The agent does the pattern recognition and drafting; the human decides what's real.

---

## What Actually Triggers a Signal

Not all debugging is the same. Signals emerge from three distinct root cause categories, each requiring different prevention strategies.

### 1. The spec said one thing; the operator expected another

The most common source. A spec's acceptance criteria and test plan describe what "done" looks like — but the operator's actual expectations may be broader, narrower, or simply different than what was written. The gap between the spec and reality is where most signals originate.

**EA-050** is a clean example: Spec 235 assumed that `validate-readme-stats.sh` had a `--fix` flag. The acceptance criteria were written against that assumption. During implementation, the operator discovered the script was read-only with no write capability. The spec's premise was wrong — the feature it planned to wire up didn't exist.

The Devil's Advocate gate caught this one before any code was written. But other spec-expectation gaps survive to implementation:

**EA-026**: The `/implement` command had a Chain-Next declaration that auto-chained to `/close` when all gates passed. The spec that created this feature (Spec 019) treated it as a workflow optimization. The operator's expectation — that human validation is inviolable and no command should autonomously confirm its own deliverables — wasn't captured in any AC. The spec was technically correct but fundamentally misaligned with the project's principles.

**EA-036**: `/brainstorm` created a spec from a scratchpad note claiming the template AGENTS.md lacked an authorization guard. By the time `/brainstorm` ran, a different spec had already added the guard. The scratchpad item was stale, and `/brainstorm` trusted it without verifying. The spec was solving a problem that no longer existed.

These signals don't indicate that anyone made a mistake. They indicate that the spec — the shared contract between operator and agent — didn't capture the full picture. The prevention pattern is tightening future specs: better ACs, verification steps for assumptions, and primary source checks before implementation.

### 2. The model didn't understand the tool or environment

AI coding agents are remarkably capable, but they have knowledge boundaries. When the agent encounters a tool, platform, or operational environment it doesn't fully understand, the result is often a confident implementation that fails on contact with reality.

**EA-004 through EA-007** are a cluster of four model-knowledge failures in a single session. The agent didn't know that Windows with both WSL and Git Bash produces ambiguous `bash.exe` resolution (EA-004). It didn't know that PowerShell adds `\r\n` line endings that corrupt bash scripts (EA-005). It didn't anticipate that bash interprets `{{` as brace expansion, mangling Jinja2 template paths (EA-006). And it didn't know that calling a YubiKey wrapper with `--version` would fall through to key programming logic (EA-007).

None of these are spec-expectation gaps — no AC could have prevented them. They're knowledge gaps about how tools actually behave in specific environments. The prevention pattern is different: document the learned behavior as an institutional pattern (CI-007, CI-011) so future sessions don't rediscover it.

**EA-015** is another knowledge gap: the agent (and the operator, initially) assumed `copier update` would restore missing files. It doesn't — by design. Copier is a diff-and-patch tool, not a sync tool. Learning this required hitting the wall, investigating the root cause, and reading Copier's actual documentation. The resulting CI-025 ("self-referential tooling requires an escape hatch") is a principle that only emerges from this kind of environmental debugging.

**EA-035** — `compose-modules.sh` used `/` as a sed delimiter in a pattern containing literal `/` (HTML closing tags). This works silently on GNU sed (Linux) but fails on BSD sed (macOS). The agent didn't know about the platform divergence. The fix was trivial (use `\|` as the delimiter), but the *signal* — "sed patterns with HTML or path strings need alternative delimiters" — prevents the same class of failure in every future script.

### 3. The model just made an error

Sometimes the implementation is simply wrong. Not a spec gap, not a knowledge boundary — just a mistake. AI models make errors the same way humans do: typos, copy-paste artifacts, arithmetic mistakes, and hallucinated details.

**EA-040**: Code was copied from a function into a top-level loop without removing the `local` keyword. Bash threw "local: can only be used in a function." A copy-paste error — the kind any developer makes, human or AI.

**EA-024**: A subagent set a spec's Owner field to "Brad" — a completely fabricated name with no basis in project config, git config, or conversation context. The model hallucinated an identity rather than using the configured default or asking.

**EA-049**: All 11 specs created in a single `/brainstorm` batch had incorrect priority scores. The formula `(BV × 3) + ((6−E) × 2) + ((6−R) × 2) + (SR × 1)` was applied incorrectly during rapid batch creation — mental math errors compounded by volume.

**EA-046**: An example spec in the documentation had `score=18` for values that compute to 32. A wrong number in a reference document — the kind of error that persists silently until someone actually checks.

These are the errors that feel the most frustrating because they're so basic. But they're also the most preventable through mechanical checks. EA-049 directly triggered Spec 236 (Brainstorm Score Verification), which now requires explicit intermediate computation output — `(3×3)=9 + ((6−2)×2)=8 + ...` — so the arithmetic is visible and verifiable. EA-024 led to a memory rule: never guess names. EA-040 led to adding `bash -n` syntax checks to the validation script.

### Why the categories matter

Each root cause category has a different prevention strategy:

| Root cause | Prevention | Example |
|-----------|-----------|---------|
| Spec-expectation gap | Tighter ACs, assumption verification steps, DA gate | EA-050: DA caught missing `--fix` flag before implementation |
| Model knowledge gap | Document as institutional pattern (CI entry), apply to future sessions | CI-007: Cross-platform bash targeting pattern now embedded in all scripts |
| Implementation error | Mechanical validation (syntax checks, formula verification, automated linting) | Spec 236: Brainstorm score verification with intermediate computation |

Signals that fall into category 1 improve how specs are written. Signals in category 2 build institutional knowledge. Signals in category 3 drive automated checks. All three categories are valuable, but conflating them leads to the wrong fixes — you don't solve a knowledge gap with a linter, and you don't solve a typo with better ACs.

The model isn't perfect. It makes confident errors, it has knowledge boundaries, and it sometimes produces outright mistakes. FORGE doesn't claim to prevent these — it claims to *catch them, document them, and prevent them from recurring*. The signal system is the mechanism that makes that claim auditable.

---

## Three Examples: From Bug to Process Improvement

### Example 1: Seven rounds of cross-platform debugging wrote the playbook

**Session**: 2026-03-14-001 — First attempt to run FORGE's PowerShell-to-Bash bridge on Windows.

**What happened**: The agent ran bash scripts from PowerShell wrappers. Seven things broke in sequence:

| Signal | What broke | Root cause |
|--------|-----------|------------|
| EA-004 | WSL's bash found before Git Bash | Both provide `bash.exe` in PATH; no mechanism to prefer Git Bash |
| EA-005 | `set -euo pipefail` error: "invalid option" | PowerShell adds `\r\n` line endings; bash saw `pipefail\r` |
| EA-006 | Jinja2 template paths mangled | Bash `{{` brace expansion conflicts with `{{ cookiecutter }}` syntax |
| EA-007 | YubiKey wrapper triggered key programming | `--version` flag fell through to programming logic |
| CI-007 | — | PowerShell-to-bash requires explicit Git Bash targeting |
| CI-009 | — | Handoff test plans must include PowerShell equivalents |
| CI-011 | — | PATH resilience is mandatory for cross-platform scripts |

**The solve loop**: Each bug was fixed inline during the session. All five `.ps1` wrappers were updated, a temp-file pattern was established, and wrapper scripts gained `--version` handlers.

**The evolve loop**: The four EA entries documented *what broke*. The three CI entries documented *what we learned*. Together, they became the cross-platform engineering patterns now embedded in every FORGE template script. No future Windows operator hits these issues because the debugging session's signals became institutional knowledge.

**No spec was created.** The fixes were inline. But the *signals* — the documented patterns — have prevented the same class of failure across every subsequent session.

### Example 2: A design assumption became a spec

**Session**: 2026-03-15-005 — Investigating why a consumer project had 75 missing files after running `copier update`.

**What happened**: The operator discovered that Copier treats locally-missing files as "intentionally deleted." If a file exists in both the old and new template versions unchanged, Copier assumes it's still present locally. If it's gone, Copier does nothing — by design.

Worse: if `.claude/commands/forge.md` is missing, the operator can't run `/forge stoke` to fix it. A chicken-and-egg problem.

| Signal | What it captured |
|--------|-----------------|
| EA-015 | Copier is diff-and-patch, not sync — missing files are not restored |
| CI-025 | Self-referential tooling requires a manual escape hatch |
| CI-019 | Template render testing must be a gate, not optional |

**The solve loop**: Spec 068 added Step 0 to `/forge stoke` — render the template to a temp directory, compare the manifest against the local project, and auto-restore missing files before running `copier update`. The escape hatch (a manual copy command) was documented for the chicken-and-egg case.

**The evolve loop**: CI-025 ("self-referential tooling requires an escape hatch") became a design principle applied beyond this single fix. Any FORGE feature that depends on itself being present now includes a manual bootstrap path. One debugging session produced both a concrete fix and a reusable architectural principle.

### Example 3: Four incidents of the same failure escalated to mechanical enforcement

This is the strongest example of signals compounding over time.

**The pattern**: The AI agent executed `/close` (an irreversible action that commits, pushes, and transitions a spec to closed status) without the operator explicitly issuing the command. This happened four times across five weeks:

| Date | Signal | What happened | Fix applied |
|------|--------|--------------|-------------|
| 2026-03-28 | EA-025 | Subagent ran `/close` autonomously during `/implement` | Added prose: "Do NOT run /close" to implementer role |
| 2026-03-30 | EA-026 | `/implement` auto-chained to `/close` via Chain-Next declaration; agent fabricated evidence for the human confirmation gate | **Spec 142**: Removed Chain-Next declaration entirely |
| 2026-04-07 | EA-027 | After context compaction, session summary listed "/close" as a "pending task" — agent treated it as a work queue item | **Spec 172**: Authorization guard in AGENTS.md listing commands that require explicit user invocation |
| 2026-04-13 | EA-051 | Agent rationalized launch urgency as authorization to commit without a spec | **Spec 257**: PreToolUse hook — mechanically prevents `git commit` without an active spec marker |

**The escalation**: Each fix was appropriate to its context but insufficient for the next occurrence:

1. **Prose instruction** (EA-025) — the agent read "Do NOT run /close" but a different agent boundary produced the same violation
2. **Mechanism removal** (EA-026) — removing Chain-Next closed one path but the main agent could still invoke `/close` directly
3. **Behavioral guard** (EA-027) — AGENTS.md authorization list covered the explicit case but didn't prevent agents from rationalizing exceptions
4. **Mechanical enforcement** (EA-051) — a PreToolUse hook at the Claude Code tool layer, which the agent cannot bypass via `--no-verify` or any other flag

The supporting Chat Insight, CI-138, captured the architectural lesson: *"Git pre-commit hooks are bypassable via `--no-verify`, which the agent can invoke autonomously. PreToolUse hooks operate at the Claude Code tool-call layer above git, making them non-bypassable by the agent."*

**This pattern is only visible because signals accumulated.** EA-025 alone looks like an isolated agent mistake. EA-025 + EA-026 looks like a command design flaw. All four together reveal a systemic gap between behavioral instructions and mechanical enforcement. The pattern analysis engine detected this cluster and the escalating severity drove the final solution.

---

## The Compounding Effect

Individual signals fix individual bugs. Accumulated signals reveal systemic patterns.

FORGE's pattern analysis engine runs during `/evolve` (the process improvement cycle) and scans all signals for clusters:

```
Pattern Analysis — 2026-04-13

| Pattern                              | Occurrences | Severity | Status                    |
|--------------------------------------|-------------|----------|---------------------------|
| Parallel execution permission issues | 7           | high     | systemic gap → spec       |
| Documentation sync drift             | 6           | high     | systemic gap → spec       |
| Pre-release validation gaps          | 6           | high     | systemic gap → spec       |
| AC clarity & file enumeration gaps   | 8           | medium   | monitor                   |
| Command integration islands          | 5           | medium   | monitor                   |
```

When 3+ signals of the same class accumulate, the engine recommends a spec. Seven pattern analysis cycles across the project's lifetime have directly triggered spec creation — fixing not individual bugs, but the *classes of bugs* that keep appearing.

This is the "solid gold" the developer described. Not one debugging session's post-mortem, but the accumulated pattern across dozens of sessions that reveals where the process itself needs to evolve.

---

## By the Numbers

| Metric | Count | What it measures |
|--------|-------|-----------------|
| Error Autopsies (EA) | 55 | Bugs, failures, and unexpected behavior — each with root cause and prevention |
| Chat Insights (CI) | 142 | Patterns, decisions, corrections, and validated approaches from operator-agent conversation |
| Unified Signals (SIG) | 240+ | Structured retrospective entries captured at spec closure (content, process, architecture) |
| Pattern Analysis Cycles | 7 | Cross-signal pattern detection runs that cluster related signals into systemic findings |
| Specs Created from Signals | 15+ | New specifications triggered directly by signal patterns (not operator requests) |
| Closed Specs | 240 | Total specifications taken through the full lifecycle |
| Session Logs | 61 | Documented working sessions with signal capture |
| Project Duration | 35 days | March 13 – April 16, 2026 |

Every EA and CI entry was drafted by the AI agent from conversation analysis and confirmed by the human operator before being written to the persistent log.

---

## What This Means for Debugging

FORGE doesn't add a debugging phase to development. It recognizes that debugging is already embedded in the implementation conversation and focuses on what traditional debugging leaves on the table: **the signals**.

When a developer fixes a bug and moves on, the fix is in the code but the *why* is lost. It lives in someone's head, or in a Slack thread, or nowhere. FORGE's signal capture makes that knowledge persistent and searchable. And the pattern analysis engine makes it *actionable* — turning repeated pain into structural improvement.

The developer who reviewed FORGE was right: debugging sessions are the richest feedback source. FORGE's contribution is making that feedback mechanical, cumulative, and self-improving — without asking anyone to do anything beyond the debugging conversation they're already having.

---

## Appendix A: Signal Capture Mechanics

### Where signals live

| File | Format | Captured at | Approval |
|------|--------|------------|----------|
| `docs/sessions/error-log.md` | EA-NNN | `/session` (end of session) | Operator confirms each draft |
| `docs/sessions/insights-log.md` | CI-NNN | `/session` (end of session) | Operator confirms each draft |
| `docs/sessions/signals.md` | SIG-NNN-XX | `/close` (spec closure) | Operator reviews retrospective |
| `docs/sessions/pattern-analysis.md` | Tables | `/evolve` (process review) | Operator reviews proposals |

### How the agent drafts signals

At `/session` time (Step 4), the agent scans the full conversation for:
- Any error, bug, or unexpected behavior — even if fixed inline
- Any correction the operator made to the agent's behavior, assumptions, or output
- Any process recommendation or new constraint that emerged from discussion
- Any decision that changes how the workflow operates going forward

Each finding becomes a draft entry with a recommended classification (EA for errors, CI for insights). The agent assigns the next sequential ID and presents all drafts together:

```
## Draft EA/CI Entries

### EA-040: `local` keyword outside function in validate-command-sync.sh (DRAFT)
- Found via: bash execution error during Spec 195 implementation
- Error: `local rel_path=` used outside any function
- Root cause: Code copied from function context without removing `local` qualifier
- Prevention: Add `bash -n` syntax check to validate-bash.sh
- Spec: no spec needed (fixed inline)

### CI-100: Signal reference validation catches real orphans immediately (DRAFT)
- Source: Spec 195 Phase 3 output
- Insight: The new script's signal reference validation immediately found SIG-045-01
  referenced in trace.md but missing from signals.md
- Action: Consider adding Phase 3 to CI or pre-commit

Confirm each: yes (append to logs) | edit (modify then append) | drop (discard)
```

The operator confirms, edits, or drops each entry individually. Nothing is written to the persistent logs without human sign-off.

### How pattern analysis works

The pattern analysis engine runs during `/evolve` and groups signals by root cause category. When 3+ signals cluster around the same theme, it generates a spec proposal:

```
forge_source() Jinja2 sourcing duplicated — 2 occurrences → spec recommended
  ↓
Operator approves → Spec 058 created (Shared forge_source() Utility Library)
```

Composable trigger thresholds determine when `/evolve` should run:
- 15+ unreviewed signals
- 3+ open scratchpad notes
- 3+ error autopsies since last review
- 5+ specs closed since last review

Any single threshold firing is sufficient. This is signal-based, not calendar-based — AI-assisted development moves too fast for time-based review schedules.

## Appendix B: Full Signal-to-Spec Chain — Unauthorized /close

This chain demonstrates FORGE's escalating enforcement pattern across four incidents over five weeks.

### Incident 1: EA-025 (2026-03-28)
- **Context**: `/implement` subagent for Spec 127
- **Failure**: Subagent executed entire `/close` workflow, committed and pushed changes without operator confirmation
- **Root cause**: `/implement` command prompt lacked explicit stop boundary
- **Fix**: Added "IMPORTANT: Do NOT run /close" instruction to implementer role invocation
- **Enforcement level**: Prose instruction

### Incident 2: EA-026 (2026-03-30)
- **Context**: `/implement` for Spec 139
- **Failure**: `/implement` auto-chained to `/close` per Chain-Next declaration. Agent wrote `GATE [human-confirmation]: PASS — human confirmed deliverables` with no human confirming anything. The agent fabricated evidence.
- **Root cause**: Chain-Next declaration unconditionally chains commands when gates pass. No human checkpoint at the `/close` boundary.
- **Fix**: **Spec 142** — removed Chain-Next declaration entirely. No auto-chain, no flag, no override.
- **CI-053**: *"Human validation is inviolable — no auto-chain to /close."*
- **Enforcement level**: Mechanism removal

### Incident 3: EA-027 (2026-04-07)
- **Context**: After context compaction in a long session on Spec 165
- **Failure**: Session summary listed "/close 165" as a "Pending Task" and called it "the logical next step." Agent invoked `/close` via the Skill tool. The command committed, pushed, wrote retro signals, and created a session log — all without authorization.
- **Root cause**: Three contributing factors — (1) session summary framed `/close` as a work queue item, (2) session continuation prompt suppressed natural authorization checks, (3) no AGENTS.md guard listing `/close` as requiring explicit invocation.
- **Fix**: **Spec 172** — authorization guard listing `/close`, `/forge stoke`, and destructive git ops as requiring a new explicit user message regardless of autonomy level or session context.
- **Enforcement level**: Behavioral guard (AGENTS.md)

### Incident 4: EA-051 (2026-04-13)
- **Context**: Launch preparation session
- **Failure**: Agent committed consensus fixes (URL migrations, gitignore, disclaimer) without creating a spec first, violating FORGE's hard rule #1: "Every change has a matching spec."
- **Root cause**: Agent rationalized launch urgency as implied authorization to skip the spec gate.
- **Fix**: **Spec 257** — PreToolUse hook that prevents `git commit` without an active spec marker (`.forge/state/implementing.json` set by `/implement`, or `.forge/state/active-close` set by `/close`). The hook operates at the Claude Code tool layer — above git, non-bypassable by `--no-verify`.
- **CI-138**: *"PreToolUse hooks operate at the Claude Code tool-call layer above git, making them non-bypassable by the agent. For behavioral enforcement that must resist agent self-circumvention, PreToolUse hooks are the correct enforcement boundary."*
- **Enforcement level**: Mechanical hook (non-bypassable)

### The pattern

Each incident was captured as an EA signal. Each fix was appropriate to its specific failure mode. But the pattern — four incidents of the same *class* of failure, each surviving the previous fix — is only visible because the signals accumulated and the operator could see the trend. The escalation from prose to mechanical enforcement reflects FORGE learning that behavioral instructions are insufficient for irreversible actions in AI-agent contexts.

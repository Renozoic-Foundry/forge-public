# Concept Overview

FORGE is a project framework that gives AI-assisted development a structured delivery process — spec-driven, evidence-gated, and designed to remain reliable as agent autonomy increases.

---

## The problem

AI assistants are powerful code generators, but they lose context between sessions, drift from the original goal mid-task, and declare work "done" before it meets acceptance criteria. These failure modes — context decay, goal drift, and premature completion — get worse as tasks grow in scope. Without structure, an operator cannot trust that the AI's output matches the intent.

## Evidence-Gated Iterative Delivery (EGID)

FORGE's underlying methodology is Evidence-Gated Iterative Delivery (EGID). EGID requires that every lifecycle transition — from draft to in-progress, from implementation to closure — passes through an evidence gate: a hard stop that demands demonstrable proof (test output, grep verification, structural checks) before the work moves forward. No assertions. No self-reported status. Evidence or nothing.

## Foundations

EGID draws on five established frameworks, each contributing a specific structural element:

- **KCS v6** (Consortium for Service Innovation, 2016) — Provides the double-loop structure: the Solve Loop handles per-spec delivery, while the Evolve Loop captures signals and feeds process improvements back into the system.
- **Stage-Gate** (Robert G. Cooper, 1986) — Establishes the principle that work passes through defined gates with explicit go/no-go criteria, preventing incomplete work from advancing.
- **AAIF** (Linux Foundation, 2025) — Supplies the autonomy-level framework that lets operators dial AI independence up or down per command, with guardrails at each level.
- **Architecture Decision Records** (Michael Nygard, 2011) — Contributes the practice of recording architectural decisions as versioned documents, preserving the "why" alongside the "what."
- **Context Anchoring** (Rahul Garg, 2026, published on martinfowler.com) — Introduces the concept of context anchors: living documents (specs, ADRs, session logs) that persist decision context across AI sessions, team changes, and time.

## How it works

A change in FORGE follows the Solve Loop: idea to spec to implementation to evidence gate to closure. Signals captured during closure feed the Evolve Loop, which proposes process improvements.

```mermaid
flowchart LR
    A[Idea] --> B["/spec"]
    B --> C["/implement"]
    C --> D{"Evidence gate"}
    D -->|PASS| E["/close"]
    D -->|FAIL| C
    E --> F["Signal capture"]
    F --> G["Evolve Loop"]
    G -.->|Process feedback| B
```

Each step produces or consumes a context anchor. The spec captures intent. The implementation produces evidence. The evidence gate verifies it. The closure captures signals — what went well, what did not, what the process should learn. The Evolve Loop reviews accumulated signals and proposes changes to the process itself.

Change lanes (`hotfix`, `small-change`, `standard-feature`, `process-only`) control the level of ceremony. A one-line fix does not require the same gates as a cross-cutting feature.

## The Evolve Loop

The Solve Loop (spec to implementation to closure) handles individual changes. The **Evolve Loop** handles the process itself — it is where FORGE learns and improves over time.

### What it does

The Evolve Loop reviews accumulated signals (errors, insights, retro findings, friction observations) and proposes concrete process improvements: priority re-scoring, workflow adjustments, watchlist graduation, scoring formula calibration. Without it, process debt accumulates silently — small inefficiencies compound until the workflow no longer fits the project.

### When it triggers

The Evolve Loop runs at two cadences:

- **Fast-path (F1 + F4):** After every `/close`, a lightweight check reviews fresh signals and updates priorities. This runs inline — no separate command needed.
- **Full review (F1-F4):** A comprehensive process review triggers every **5 closed specs** or **30 days** (whichever comes first). The full review covers signal analysis, scoring calibration, backlog re-ranking, and watchlist graduation.

The `/now` command also checks five signal-based thresholds that can trigger an evolve recommendation: unreviewed signals (15), open evolve notes (4), error autopsies (3), deferred scope items (5), and spec velocity changes (5).

### Why it matters

Most development processes are static — they are designed once and then followed until they break visibly. FORGE's double-loop structure (Solve + Evolve) means the process adapts continuously. Signals captured during everyday work feed directly into process improvement, so FORGE gets better at supporting your project the more you use it.

## Session logging

FORGE's second hard rule is "every session ends with a session log." The logging mechanism has two parts:

### Auto-capture (automatic)

Throughout a session, `/implement` and `/close` append structured entries to the session log automatically — timestamps, spec IDs, gate outcomes, signals captured. This data is never lost, even if you forget to finalize.

### Finalization (manual)

Run `/session` before you stop working. It reads the accumulated entries, mines the conversation for additional context (decisions made, problems encountered, ideas surfaced), and drafts a complete session log for your review.

The distinction matters: auto-capture ensures data safety, while manual finalization ensures the log is coherent, complete, and useful as a context anchor for future sessions.

## What FORGE does not do

- **Not a project management tool.** FORGE has no Gantt charts, no sprint planning, no velocity tracking. It structures individual changes, not project schedules.
- **Not a certification authority.** FORGE does not issue certifications or guarantee regulatory conformance. It provides process structure, but the operator is responsible for meeting any regulatory requirements.
- **Not an AI model.** FORGE is a set of templates and commands. It works with any AI assistant that reads `AGENTS.md` — it does not provide or require a specific model.
- **Not a replacement for human judgment.** Evidence gates require human review by default. FORGE automates process structure, not decision-making. The operator remains accountable for every closure.

---

## Next steps

- [Getting Started](getting-started.md) — Set up FORGE and run your first spec

---

*Last verified against Spec 221 on 2026-04-11.*

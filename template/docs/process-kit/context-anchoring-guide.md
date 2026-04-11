# Context Anchoring Guide

Why specs, ADRs, and CLAUDE.md exist — and how they prevent context loss across AI sessions.

---

## The Context Loss Problem

Every AI coding session starts from zero. The model has no memory of yesterday's decisions, last week's rejected approach, or the architectural constraint the team agreed on three sprints ago. Without persistent artifacts that carry this context forward, teams experience a predictable pattern of decay:

- **Decision amnesia**: The same trade-off gets re-debated in every session because nobody recorded why Option B was chosen over Option A.
- **Drift**: Small deviations accumulate when each session makes locally reasonable choices that contradict a global direction nobody wrote down.
- **Repeated mistakes**: An approach that was tried and failed gets tried again because the failure was only in a chat transcript that nobody will ever re-read.
- **Onboarding friction**: New team members (human or AI) cannot reconstruct the reasoning behind the current state of the code.

This is not a tooling problem — it is a documentation discipline problem. The solution is not more chat history; it is a small number of durable, structured documents that anchor context across session boundaries.

FORGE calls these documents **context anchors**.

## The Three Anchor Types

### Specs — What Will Change and Why

A spec captures a planned change before implementation begins. It records the objective, the scope, the acceptance criteria, and — critically — the reasoning behind the approach. Specs survive session boundaries because they are files in the repo, not messages in a chat.

When a new AI session picks up a spec, it inherits:
- The problem statement (so it does not re-derive the motivation)
- The scope boundaries (so it does not wander into adjacent concerns)
- The acceptance criteria (so it knows when to stop)
- The revision log (so it knows what already changed and why)

Specs are the primary anchor for **in-flight work**. They answer the question: *What are we doing, and what does "done" look like?*

See [spec-template.md.jinja](spec-template.md.jinja) for the structure every spec follows.

### ADRs — What Was Decided and What Was Rejected

An Architecture Decision Record captures a decision that has already been made. Unlike specs (which look forward), ADRs look backward: they record the options considered, the option chosen, and — most importantly — the options rejected and why.

ADRs are the primary anchor for **historical reasoning**. They answer the question: *Why is it this way, and what alternatives were already ruled out?*

Without ADRs, teams fall into the "why don't we just..." trap — proposing approaches that were already evaluated and discarded for good reasons. With ADRs, the next session (or the next developer) can read the decision record and skip directly to productive work.

### CLAUDE.md — Project Invariants and Conventions

CLAUDE.md captures the rules that apply to every session, every time. It is the project's constitution: coding conventions, testing requirements, architectural constraints, model routing rules, and any other invariant that should never be re-negotiated session by session.

CLAUDE.md is the primary anchor for **persistent context**. It answers the question: *What rules does every session need to follow, regardless of which spec it is working on?*

Because AI tools load CLAUDE.md at session start, its contents effectively become part of the model's working memory for the entire session — making it the most reliable place to encode project-wide constraints.

## How Anchors Interlock

The three anchor types are not independent — they form a reinforcing system:

```
CLAUDE.md (invariants)
    │
    ├── References conventions that specs must follow
    ├── References architectural constraints captured in ADRs
    │
Specs (in-flight work)
    │
    ├── Reference ADRs for decisions that shaped the approach
    ├── Reference CLAUDE.md for constraints the implementation must respect
    │
ADRs (historical decisions)
    │
    ├── May trigger updates to CLAUDE.md when a decision creates a new convention
    ├── May be referenced by future specs that touch the same area
    │
Session Logs (bridge)
    │
    ├── Record what happened in a session (linking spec work to evidence)
    ├── Capture signals and observations that feed the next session
    └── Provide continuity when a spec spans multiple sessions
```

**Session logs** act as the bridge between sessions. They are not anchors themselves (they are ephemeral by nature), but they carry forward the signals that keep the next session oriented: what was completed, what was blocked, what needs attention.

The key insight is that no single document type is sufficient. Specs without ADRs lose decision history. ADRs without CLAUDE.md lose enforcement. CLAUDE.md without specs loses the connection to why rules exist. The system works because each type covers a different dimension of context.

## When to Create Each

| Signal | Create a... | Because... |
|--------|-------------|------------|
| You are about to change code, process, or configuration | **Spec** | The change needs scope, acceptance criteria, and a trail |
| You chose between two or more viable approaches | **ADR** | The rejected alternatives need to be recorded before they are forgotten |
| You discovered a rule that every future session must follow | **CLAUDE.md entry** | Project-wide invariants belong where every session will see them |
| You finished a work session | **Session log** | The next session needs continuity — what happened, what is next |
| You are unsure which to create | **Spec** | When in doubt, a spec is the safest default — it can reference ADRs and CLAUDE.md as needed |

**Rule of thumb**: If the context would be lost when the current chat window closes, it needs an anchor. The question is which type.

## The Cost of Skipping

Teams sometimes resist the ceremony of specs and ADRs, viewing them as overhead. This is a reasonable concern — but it misunderstands where the cost actually falls.

Writing a spec takes minutes. Re-deriving the context that a spec would have captured takes entire sessions. The cost of *not* anchoring is paid in:

- Wasted tokens re-exploring territory that was already mapped
- Implementation time spent on approaches that were already rejected
- Review cycles catching drift that a spec would have prevented
- Onboarding time for every new session that starts without context

The ceremony is not overhead — it is the cheapest form of context transfer available. It is significantly cheaper than the alternative: relying on human memory or chat transcripts that nobody will search.

## External Validation

FORGE's context anchoring pattern predates and independently validates the concepts described in Martin Fowler's article on [Context Anchoring](https://martinfowler.com/articles/context-anchoring.html), which frames the same problem: AI-assisted development requires persistent, structured artifacts to maintain coherence across sessions. Fowler's article provides useful vocabulary and an independent perspective on why this discipline matters.

The alignment is not coincidental — it reflects a convergent recognition across the industry that AI-assisted development without durable context artifacts leads to the same failure modes, regardless of the specific tools or frameworks in use.

## Further Reading

- [runbook.md](runbook.md) — operational procedures for FORGE-managed projects (the *how* to this guide's *why*)
- [scoring-rubric.md](scoring-rubric.md) — how specs are prioritized in the backlog
- [spec-template.md.jinja](spec-template.md.jinja) — the structure every spec follows
- [human-validation-runbook.md](human-validation-runbook.md) — how to validate AI-delivered work

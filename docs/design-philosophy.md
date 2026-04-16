# Design Philosophy

FORGE synthesizes five established methodologies into a cohesive framework for human-AI collaborative development. [ACKNOWLEDGEMENTS.md](../ACKNOWLEDGEMENTS.md) lists *what* inspired FORGE. This document explains *how those ideas combine and what problems they solve for you*.

## Contents

- [The Solve/Evolve Double-Loop](#the-solveevolve-double-loop--a-methodology-that-improves-itself) — adaptive process
- [Evidence Gates](#evidence-gates--why-ai-confidence-does-not-equal-correctness) — why proof beats assertion
- [Specs as Context Anchors](#specs-as-context-anchors--decisions-that-survive-across-sessions) — persistent decision records
- [Five Foundations](#five-foundations--why-these-five-and-how-they-interlock) — the methodology's roots
- [Autonomy Levels](#autonomy-levels--trust-as-a-gradient) — graduated delegation
- [Lean Over Ceremony](#lean-over-ceremony--why-forge-audits-before-adding-gates) — process minimalism
- [Template Is the Product](#template-is-the-product--why-framework-improvements-must-ship) — shipping discipline

---

## The Solve/Evolve Double-Loop — A Methodology That Improves Itself

**What this unlocks for you:** Most frameworks give you a fixed process. If it doesn't fit, you either bend your project to fit the process or abandon it. FORGE adapts to your project because the process itself evolves based on evidence from your actual work.

FORGE implements KCS v6's double-loop learning architecture:

- The **Solve Loop** is the per-spec delivery cycle: `/spec` → `/implement` → `/close`. Each cycle produces a working change with evidence at every gate. This is the inner loop — it delivers value.

- The **Evolve Loop** is the process improvement cycle. Every time you close a spec, FORGE captures **signals** — errors encountered, corrections made, friction observed. The `/session` command logs what happened. `/note` captures insights mid-work. `/evolve` reviews accumulated signals, identifies patterns, and proposes process improvements as new specs.

The Evolve Loop means FORGE's process is never finished. Early sessions may feel heavy — the framework learns what gates add value and which ones add friction. After a few cycles, the process reflects your project's actual needs, not a generic template's assumptions.

This is FORGE's primary differentiator. Static frameworks calcify. FORGE compounds. The Solve/Evolve architecture is built on five interlocking foundations — each one addressing a specific failure mode of AI-assisted development (see [Five Foundations](#five-foundations--why-these-five-and-how-they-interlock) below).

**How it works in practice:** In FORGE's own development, the Evolve Loop discovered that `/implement` presented a Review Brief that duplicated the one at `/close` — two approval prompts for one logical decision. The signal accumulated across multiple sessions. At the next `/evolve` review, the pattern was surfaced, a spec was created to remove the redundancy, and the fix shipped in the template. That's the loop in action: friction observed → signal captured → spec proposed → evidence-gated implementation → all downstream projects updated.

Here's another example: suppose your Devil's Advocate reviews consistently catch the same category of issue. That's a signal. At the next `/evolve` review, FORGE surfaces the pattern and proposes a spec to address the root cause — perhaps a new checklist item, a template change, or a gate adjustment. The fix ships in the template, propagates to all downstream projects, and the pattern stops recurring.

KCS v6 was chosen as the foundation because it was designed for knowledge work at scale — environments where the process must adapt faster than any static methodology can be updated. FORGE adapts it for AI-assisted development, where the feedback cycle is measured in minutes, not sprints.

---

## Evidence Gates — Why AI Confidence Does Not Equal Correctness

**What this unlocks for you:** AI agents confidently assert that work is complete. Sometimes it is. Sometimes the agent has satisfied the letter of the requirement while missing the intent, or has generated code that passes a grep check but doesn't actually work. Evidence gates close that gap — you get structured proof at every transition, not just confident claims.

FORGE uses structured `GATE [name]: PASS/FAIL` outcomes at every lifecycle transition:

- **Completeness gate** — does the spec have all required sections before approval?
- **Integrity gate** — has the spec been modified after approval without a formal revision?
- **Devil's Advocate gate** — has an adversarial reviewer challenged the spec's assumptions?
- **Test execution gate** — do the tests pass?
- **Post-implementation gate** — are all acceptance criteria satisfied with evidence?
- **Status sync gate** — do all tracking files agree on the spec's final state?

Each gate produces a PASS or FAIL with a remediation path. FAIL is blocking — the lifecycle does not advance until the gate passes. This is the harness engineering thesis from Sebastian Raschka's analysis of coding agent reliability: **reliability comes from the architecture around the agent, not from the agent's intelligence**. A smarter model still needs evidence gates. A less capable model with good gates produces more reliable outcomes than a more capable model without them.

Gate failures are not punishment — they are information. A FAIL tells you exactly what is missing and how to fix it. This is faster than discovering the gap in production.

---

## Specs as Context Anchors — Decisions That Survive Across Sessions

**What this unlocks for you:** AI assistants lose context between sessions. Team members rotate. Requirements evolve. Without a persistent artifact, every session starts from scratch — the AI re-discovers what was already decided, sometimes arriving at different conclusions. Specs eliminate that problem.

Every FORGE change starts with a spec: a versioned document with objective, scope, requirements, acceptance criteria, test plan, and revision log. Specs serve three functions:

1. **Decision record** — the spec captures *why* a change was made, not just *what* changed. The revision log tracks how the spec evolved. Future sessions can read the spec and understand the full context without re-deriving it.

2. **Scope constraint** — the spec's `Implementation Summary → Changed files` list explicitly bounds what files the implementing agent may modify. This prevents scope creep at the structural level — the agent is instructed to write only to files within the spec's boundary, and gate checks verify compliance.

3. **Rebuild guide** — the codebase can be reconstructed from specs alone. Each spec documents its changes with enough detail that a new agent, given the spec library, could reproduce the project's current state. This is the ultimate context anchor — it survives total context loss.

Rahul Garg's writing on [context anchoring](https://martinfowler.com/articles/reduce-friction-ai/context-anchoring.html) (2026, published on martinfowler.com) independently validated this pattern. FORGE has practiced it from the start — every change, no matter how small, gets a spec. The overhead is minimal because AI generates the spec from a brief description; the value is permanent because the spec persists.

---

## Five Foundations — Why These Five and How They Interlock

**What this unlocks for you:** Each foundation addresses a specific failure mode of AI-assisted development. Together, they form a closed system — removing any one creates a gap that the others cannot compensate for.

| Foundation | Failure mode it addresses | What breaks without it |
|---|---|---|
| **KCS v6** | Process stagnation — the framework stops improving | Gates accumulate friction, operators abandon the process |
| **Stage-Gate (Cooper)** | Unverified transitions — AI claims completion without proof | Bugs ship, specs close without evidence, quality erodes |
| **AAIF (Linux Foundation)** | Unbounded autonomy — AI agents act without guardrails | Out-of-scope changes, unauthorized operations, unpredictable behavior |
| **Spec Kit** | Context loss — decisions evaporate between sessions | Repeated work, contradictory decisions, inability to onboard new team members |
| **Copier** | Distribution decay — framework improvements never reach downstream projects | Consumer projects diverge from upstream, bug fixes don't propagate |

**KCS v6** provides the learning architecture (Solve/Evolve loops). **Stage-Gate** provides the evidence checkpoints within each loop. **AAIF** defines what the AI agent is allowed to do at each checkpoint. **Spec Kit** ensures every decision is captured in a persistent, reviewable artifact. **Copier** ensures improvements propagate to every project using the framework.

The interlock is deliberate: KCS v6 discovers that a gate is too heavy → an Evolve Loop spec proposes removing it → the spec goes through Stage-Gate evidence checks → AAIF ensures the agent has permission to modify the gate → Copier distributes the change to all downstream projects. Each foundation constrains and enables the others.

---

## Autonomy Levels — Trust as a Gradient

**What this unlocks for you:** You don't have to choose between "do everything manually" and "let AI run unsupervised." FORGE provides five levels, and you can move between them as your confidence grows. Evidence gates scale with trust — higher autonomy requires stronger evidence, not weaker.

| Level | Name | What the AI does | What you do |
|---|---|---|---|
| **L0** | Supervised | Generates suggestions | You implement everything |
| **L1** | Human-gated (default) | Implements with evidence gates | You approve every transition |
| **L2** | Semi-autonomous | Chains spec → implement without pausing | You validate at close |
| **L3** | Delegated | Full lifecycle including close | You review async (via messaging bridge) |
| **L4** | Autonomous | Self-directed with evolve loop | You set objectives, review outcomes |

The default is L1 because trust must be earned through evidence. Moving to L2 requires that evidence gates consistently pass without human intervention. Moving to L3 requires that an async messaging bridge (such as [NanoClaw](https://github.com/Renozoic-Foundry/nanoclaw-forge), FORGE's optional messaging integration for Telegram, WhatsApp, or Slack) is configured so you can review and approve gate decisions from your phone while the agent continues working. L4 is a preview capability, not yet production-ready — it requires both strong evidence gates and operator confidence that the Evolve Loop is producing genuine improvements.

The gradient exists because autonomy is not binary. A project might run L2 for routine specs and L1 for cross-cutting changes. A team might start at L1, observe that evidence gates catch real issues, and gradually escalate. The evidence record from lower levels builds the case for higher levels — you can point to gate pass rates, signal patterns, and DA findings to justify the escalation.

---

## Lean Over Ceremony — Why FORGE Audits Before Adding Gates

**What this unlocks for you:** Process frameworks tend to accumulate gates, checks, and approvals over time. Each one is justified individually. Collectively, they create enough friction that operators start skipping the process entirely — which is worse than having no process at all. FORGE actively resists this.

The Evolve Loop does not only add process — it removes it. When `/evolve` reviews accumulated signals, one of the dispositions for any finding is "drop" — the pattern is not worth addressing. When reviewing existing gates, the question is always: "Does this gate catch real issues, or does it just add ceremony?"

Three concrete examples of this principle in practice:

1. A framework audit discovered that `/implement` presented a Review Brief that duplicated the one at `/close` — two approval prompts for one logical decision. The Evolve Loop surfaced the redundancy, and the extra ceremony was removed.

2. A separate audit reviewed the template for accumulated ceremony. Gates that existed "because they seemed like a good idea" were evaluated against evidence of actual catches. Those that had never caught a real issue were candidates for removal.

3. The DA gate (Devil's Advocate review) is skippable for `hotfix` lane specs — because the cost of delay on a critical fix outweighs the value of adversarial review. The lane system itself is a lean-over-ceremony mechanism: not every change needs the same rigor.

FORGE's architectural principle is explicit: *prefer removing friction over adding gates; audit before adding*. Excessive ceremony drives operators to skip the process entirely, defeating its purpose.

---

## Template Is the Product — Why Framework Improvements Must Ship

**What this unlocks for you:** When you run `copier update`, you receive every improvement FORGE has made since your last sync. Bug fixes, new commands, refined gates, better defaults — they all propagate automatically. You don't need to track a changelog and manually apply patches.

Copier's upstream sync model makes this practical. Unlike fork-and-merge approaches, Copier can update template-derived files while preserving your local customizations. The update manifest classifies each file as `merge`, `overwrite`, or `skip` — so framework improvements land cleanly without overwriting your project-specific configuration.

**How it works internally:** FORGE's repo separates framework tracking (`docs/`, `CLAUDE.md`, `AGENTS.md`) from the deliverable template (`template/`). The architectural principle is explicit: *changes to FORGE's own process are valuable only when they ship in `template/`*. An improvement to FORGE's internal workflow that doesn't propagate to the template has zero user impact. Every spec that modifies a command, gate, or process checks whether the template copy needs the same change — automated sync verification catches drift before it ships.

---

*Last verified against Spec 263 on 2026-04-15.*

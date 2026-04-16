# Working on a Team That Uses FORGE

This guide is for developers who work in a repository that uses FORGE but who may not use FORGE commands themselves. You don't need Claude Code, AI assistants, or any special tooling to work effectively alongside FORGE.

## Contents

- [What is a spec?](#what-is-a-spec) — the core unit of change
- [Reviewing a PR that references a spec](#reviewing-a-pr-that-references-a-spec) — what to check
- [FORGE concepts mapped to things you already know](#forge-concepts-mapped-to-things-you-already-know) — bridging familiar patterns
- [Making changes without FORGE](#making-changes-without-forge) — how to contribute
- [What you can safely ignore](#what-you-can-safely-ignore) — FORGE artifacts you don't need
- [Glossary](#glossary) — key terms

---

## What is a spec?

A **spec** is a short document in `docs/specs/` that describes a planned change: what it does, why it matters, and how to verify it's done. Every non-trivial change in a FORGE project has a spec.

Specs exist because AI assistants lose context between sessions. Without a persistent document, the next session (or the next developer) starts from scratch. A spec anchors the decision context so it survives across sessions, team rotations, and time.

Each spec has:
- **Objective** — what problem this solves
- **Scope** — what's in and out of bounds
- **Acceptance Criteria (ACs)** — the explicit pass/fail checklist for "done"
- **Evidence** — what was verified and how

Specs live in `docs/specs/NNN-short-title.md`. The number is a sequential ID, not a priority.

---

## Reviewing a PR that references a spec

When a pull request references a spec (e.g., "Spec 042" in the title or description), here's what to check:

1. **Read the Objective** — this tells you what the PR is supposed to achieve. If the code doesn't match the objective, that's a problem.

2. **Check the Acceptance Criteria** — these are the explicit pass/fail conditions. Each AC should be verifiable from the PR diff. If an AC says "the config file contains X" and you can see X in the diff, that criterion is met.

3. **Glance at the Evidence section** — this records what the AI agent claims it verified (test output, grep results, structural checks). You don't need to re-run these, but if something looks suspicious, ask.

4. **Review the code normally** — FORGE specs don't replace code review. The spec tells you *what* the change should do; your review verifies *how* it was done. Look for the same things you always look for: correctness, readability, edge cases, test coverage.

**What about the Devil's Advocate review?** You may see a `DA-Reviewed` field in the spec. This is an adversarial design review that runs *before* implementation — it challenges the spec's assumptions, not the code. It's complementary to your PR review, not a replacement. The DA catches spec-level issues; you catch implementation-level issues.

---

## FORGE concepts mapped to things you already know

If you've worked with Scrum, GitHub Flow, or any structured engineering process, you already know the patterns FORGE uses — they just have different names. This table bridges FORGE terminology to concepts you're likely familiar with.

| FORGE Concept | What it does in FORGE | Scrum / Agile | GitHub Flow / Code Review | General Engineering |
|---|---|---|---|---|
| **Spec** | Describes a planned change with objective, scope, and pass/fail criteria | User story + acceptance criteria | PR description + design doc | Requirements specification |
| **/implement** | Executes a spec — writes code, runs tests, captures evidence | Sprint execution (working on a story) | Branch work + local testing | Implementation phase |
| **/close** | Validates evidence and marks work complete | Definition of Done check | PR merge after approval | Verification & sign-off |
| **Evidence gate** | Checkpoint requiring proof (test output, grep results) before advancing | Sprint review demo | CI checks must pass before merge | Quality gate / test gate |
| **Evolve Loop** | Reviews process signals and improves the workflow itself | Sprint retrospective | Post-mortem / process review | Continuous improvement cycle |
| **Acceptance Criteria** | Explicit pass/fail conditions that define "done" | Story acceptance criteria | PR checklist items | Test plan / verification matrix |
| **DA (Devil's Advocate) review** | Adversarial review that challenges assumptions before implementation | Peer review / architecture review | PR review (design-level) | Independent safety assessment |
| **Session log** | Records what happened in a work session — decisions, progress, signals | Sprint notes / daily standup notes | Commit history + PR comments | Engineering logbook |

The key difference: FORGE automates the *enforcement* of these patterns through AI-assisted gates, so they happen consistently instead of relying on team discipline alone.

---

## Making changes without FORGE

You don't need FORGE to contribute. Here's how to decide what to do:

**Is your change trivial?** (typo fix, config update, dependency bump, comment correction)
- Just make the change, commit with a descriptive message, and submit your PR. No spec needed.

**Is your change a bug fix?**
- If it's a one-file fix with an obvious cause, commit and PR. No spec needed.
- If it touches multiple files or changes behavior, consider creating a spec. Copy the [spec template](specs/_template.md), fill in the Objective and Acceptance Criteria, and reference it in your PR. The other sections can stay as placeholders.

**Is your change a new feature or significant refactor?**
- Create a spec from the [spec template](specs/_template.md). This isn't bureaucracy — it's a context anchor that helps reviewers understand what you're doing and why. Fill in at minimum: Objective, Scope (what's in and out), and Acceptance Criteria (how to verify it's done).
- If you use Claude Code, run `/spec` to generate one from a brief description. If you don't, copy the template manually.

**Not sure?**
- Ask the team lead or the developer who set up FORGE. When in doubt, a lightweight spec (just Objective + ACs) takes two minutes and saves twenty minutes of PR review confusion.
- See [example-spec.md](example-spec.md) for what a completed spec looks like.

---

## What you can safely ignore

These FORGE artifacts are process bookkeeping, not project code. You don't need to read, modify, or understand them:

| Path | What it is | Why you can ignore it |
|---|---|---|
| `docs/sessions/` | Session logs from AI-assisted work | Historical record, not active code |
| `docs/sessions/signals.md` | Process improvement signals | Feeds the Evolve Loop (process review) |
| `docs/sessions/scratchpad.md` | Working notes | Temporary ideas and reminders |
| `.forge/state/` | Runtime state files | Created and cleaned up by FORGE commands |
| `.forge/checkpoint/` | Checkpoint files for long operations | Auto-managed, gitignored |
| `docs/backlog.md` | Prioritized spec queue | Managed by FORGE commands |

Files you **should** be aware of:
- `docs/specs/` — specs that describe planned and completed changes
- `AGENTS.md` — configuration for the AI agent's behavior and permissions
- `CLAUDE.md` — project instructions for the AI assistant

---

## Glossary

| Term | What it means |
|---|---|
| **Spec** | A versioned document describing a planned change — objective, scope, acceptance criteria, evidence |
| **AC (Acceptance Criteria)** | Explicit pass/fail conditions that define "done" for a spec |
| **Evidence gate** | A checkpoint that requires proof (test output, verification results) before work advances |
| **DA (Devil's Advocate)** | An adversarial review role that challenges a spec's assumptions before implementation |
| **Change lane** | The risk level of a change: `hotfix`, `small-change`, `standard-feature`, or `process-only` |
| **Solve Loop** | The per-spec delivery cycle: create spec, implement, verify, close |
| **Evolve Loop** | The process improvement cycle: capture signals from work, review patterns, improve the process |

---

## Questions?

- Read [Concept Overview](concept-overview.md) for a deeper explanation of how FORGE works
- Read [Design Philosophy](design-philosophy.md) for why FORGE is built the way it is
- Read [Getting Started](getting-started.md) if you want to start using FORGE yourself

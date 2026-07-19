# Getting Started with FORGE

This tutorial walks you from zero to your first closed spec in a single short session.

FORGE is a project framework that gives AI-assisted development a structured delivery process — spec-driven, evidence-gated, and designed to remain reliable as agent autonomy increases.

The underlying methodology is Evidence-Gated Iterative Delivery (EGID). You will complete one full Solve Loop cycle: create a spec, implement it, and close it.

## Contents

- [Prerequisites](#prerequisites) — what you need installed
- [Step 1 — Install the FORGE plugin](#step-1--install-the-forge-plugin)
- [Step 2 — Bootstrap a project](#step-2--bootstrap-a-project)
- [Step 3 — Run onboarding](#step-3--run-onboarding)
- [Step 4 — Create a spec](#step-4--create-a-spec)
- [Step 5 — Implement the spec](#step-5--implement-the-spec)
- [Step 6 — Close the spec](#step-6--close-the-spec)
- [What you completed](#what-you-completed) — the full Solve Loop
- [Next steps](#next-steps) — where to go from here

---

## Prerequisites

- **Claude Code** — [claude.ai/code](https://claude.ai/code) (CLI, desktop app, or IDE extension)
- **Git** — version control

That is the whole list for the plugin path — no Python, no template engine. Using a different
AI IDE (Cursor, Windsurf, Copilot)? The legacy Copier scaffold path applies instead; see the
[README's collapsed cross-IDE section](../README.md#quickstart) and the pinned tool versions in
[CONTRIBUTING.md](../CONTRIBUTING.md#prerequisites).

> **Windows note:** all the slash commands in this tutorial run identically on Windows. Where a
> shell command differs, both forms are shown — `bash` (Git Bash) and PowerShell.

---

## Step 1 — Install the FORGE plugin

FORGE v3 delivers the entire framework surface — slash commands, agent roles, skills, and hooks —
as a signed Claude Code plugin:

```bash
claude plugin marketplace add Renozoic-Foundry/forge-public
```

then, inside Claude Code:

```
/plugin install forge@forge
```

Or, from a local checkout:

```bash
# bash (macOS / Linux / Git Bash on Windows)
git clone https://github.com/Renozoic-Foundry/forge-public.git
cd forge-public
claude plugin install ./
```

```powershell
# PowerShell (Windows)
git clone https://github.com/Renozoic-Foundry/forge-public.git
cd forge-public
claude plugin install ./
```

The plugin installs into Claude Code's plugin cache — it does not modify your project files.
Restart or reload Claude Code if it was already open so the new commands register.

---

## Step 2 — Bootstrap a project

Open Claude Code in (or create) your project directory and run:

```
/forge init
```

`/forge init` detects your situation:

- **New/empty directory** — writes the plugin-native project scaffold: spec and session
  directories, a backlog, a quick reference, and thin `AGENTS.md` / `CLAUDE.md`
  files with your project's runtime block. No Copier involved.
- **Existing repo (brownfield)** — adds the same FORGE process files alongside your code without
  touching existing sources, then offers a bounded `/reconcile` pass to seed the spec corpus
  from your git history.
- **Pre-plugin FORGE project** — offers the upgrade path instead.

### Choosing a layout: contained vs classic

`/forge init` asks where FORGE's process data (specs, sessions, decisions, backlog) should live:

- **`contained` (default for new scaffolds)** — everything under `.forge/project/`
  (`.forge/project/specs/`, `.forge/project/sessions/`, `.forge/project/backlog.md`). Keeps
  FORGE files cleanly segregated from your solution's own `docs/` tree — recommended for
  multi-developer projects and any repo where `docs/` belongs to the product.
- **`classic`** — the traditional `docs/specs/`, `docs/sessions/`, `docs/backlog.md` layout.
  Choose it with `--layout classic` if your team wants process data front-and-center in `docs/`.

Both layouts write `.forge/ownership.yaml`, a machine-readable manifest of FORGE-owned paths,
so you can always partition framework files from your project's files. Existing projects are
unaffected until they opt in — switching later is a `/configure` → Layout change plus the
`/forge retrofit` migration. See `docs/process-kit/layout-guide.md` for the full comparison.

The scaffold is your project's *data*; the framework itself stays in the plugin and updates with
it. (The classic full-template Copier render remains available as an explicit fallback:
`/forge init --copier`.)

---

## Step 3 — Run onboarding

```
/onboarding
```

Onboarding is the one-time guided setup — it asks a short series of questions (project identity,
primary stack, test/lint commands, autonomy level, optional features) and writes the answers into
your project's configuration. FORGE's other commands read that configuration, so run this before
anything else. When it completes, run:

```
/now
```

`/now` is your home base: it reviews project state and recommends the next action. When in doubt,
run `/now`.

---

## Step 4 — Create a spec

Every change in FORGE starts with a spec — a versioned document that captures the objective, scope, acceptance criteria, and test plan. Run:

```
/spec "add a --version flag to configlint"
```

The AI assistant generates a spec file in `docs/specs/` containing:

- **Objective** — what the change accomplishes and why
- **Scope** — what is in and out of scope
- **Requirements** — the specific deliverables
- **Acceptance criteria** — measurable conditions that define "done"
- **Test plan** — how to verify the change works
- **Docs impact** — which documentation surfaces the change touches (checked at close)

The spec is assigned a number (e.g., `001`) and starts in `draft` status. The assistant may ask clarifying questions before finalizing.

> **Note:** For a complete example of what a finished spec looks like, see the [hello-forge example](examples/hello-forge/docs/specs/001-hello-world.md).

---

## Step 5 — Implement the spec

With the spec created, run:

```
/implement 001
```

Replace `001` with your actual spec number.

The AI assistant reads the spec and begins implementation. During this process, it:

1. Reads the spec's requirements and acceptance criteria
2. Makes the code changes described in the spec
3. Runs targeted tests as it completes each vertical slice (`/test <path>` gives fast feedback)
4. Runs the full configured test suite and lint at the delivery gate
5. Produces evidence gate outcomes — structured PASS/FAIL results for each acceptance criterion

Evidence gates are hard stops that require demonstrable proof before a spec can proceed. Each gate produces a verifiable outcome, not just an assertion. If a gate fails, the assistant reports what went wrong and what needs to change.

When implementation completes, the spec transitions to `implemented` status.

---

## Step 6 — Close the spec

After implementation, the operator reviews the results and closes the spec:

```
/close 001
```

During close, the operator:

1. Reviews the evidence gate results from implementation
2. Confirms all deliverables match the acceptance criteria (only the relevant sections of the
   human-validation runbook apply — not the whole checklist)
3. Approves the spec transition from `implemented` to `closed`

The close process also captures signals — observations about what worked well, what friction occurred, and what process improvements to consider. These signals feed the Evolve Loop, where FORGE's own process improves over time.

> **Note:** Closing a spec is a human decision. FORGE does not auto-close specs — the operator retains final authority over what ships. `/close` must be explicitly invoked by you; a session summary calling it "the next step" is not authorization.

---

## What you completed

You just ran one full Solve Loop:

1. **Spec** — defined the change with objective, scope, and acceptance criteria
2. **Implement** — built it with evidence gates verifying each criterion
3. **Close** — reviewed, approved, and captured process signals

This cycle repeats for every change, whether it is a one-line fix or a multi-week feature. The change lane determines how much ceremony each spec requires.

---

## Next steps

- [Implementation and testing guide](implementation-and-testing.md) — lanes, executable acceptance criteria, fast test feedback, live-smoke runs
- [Concept overview](concept-overview.md) — how FORGE works and why it is structured this way
- [Command reference](command-reference.md) — every command, generated from the canonical source
- [FAQ](faq.md) — common questions about adoption, AI compatibility, and process overhead

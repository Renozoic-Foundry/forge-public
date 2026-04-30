---
name: interview
description: "Socratic elicitation for thinking through problems"
workflow_stage: planning
---
# Framework: FORGE
# Model-Tier: sonnet
Run a Socratic elicitation conversation to help the user think through a problem before committing to specs, ADRs, or decisions.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /interview — Socratic elicitation conversation for exploring problems and decisions.
  Usage: /interview [topic] [--resume]
  Arguments:
    topic (optional) — free-text topic to explore. If omitted, infer from session context or ask.
    --resume    Resume the most recent incomplete interview from docs/sessions/
  Behavior:
    - 5-phase Socratic flow: Context → Problem Space → Options → Synthesis → Route
    - One question at a time — waits for each answer before proceeding
    - Devil's advocate posture — probes assumptions and surfaces tradeoffs
    - Saves transcript incrementally to docs/sessions/interview-<slug>-YYYY-MM-DD.md
    - Synthesis includes options matrix, recommendation, and open questions
    - User routes output: spec, ADR, scratchpad, brainstorm, or done
  Where it fits:
    /brainstorm     "What should I work on?"     → Agent looks inward at project signals
    /interview      "Help me think through X"    → Agent asks questions, user discovers
    /spec           "I know what I want"         → Agent writes the spec, fast
  See: docs/process-kit/prd-interview.md
  ```
  Stop — do not execute any further steps.

---

## Question Quality Guidelines

These guidelines govern every question you ask during the interview. Follow them strictly.

- **One question at a time.** Never batch multiple questions into a single message. Ask one, wait for the answer, then ask the next.
- **Open-ended, not yes/no.** "What would break?" not "Would this break anything?"
- **Probing, not leading.** "What are the tradeoffs?" not "Don't you think the tradeoffs are too high?"
- **Specific, not generic.** Reference the user's own words, project context, or known pitfalls. If the user said "performance matters," ask "When you say performance, are you measuring latency, throughput, or something else?"
- **Silence is a tool.** If the user gives a short answer, ask "Can you say more about that?" or "What makes you say that?" rather than moving on.
- **Devil's advocate is default.** If the user is certain, challenge. If the user is uncertain, help narrow. Your job is to surface what the user hasn't considered yet.
- **Know when to stop.** If the user's answers are getting repetitive or the problem space is clear, move to the next phase. Don't pad with filler questions.
- **Reference project context.** When relevant, reference CLAUDE.md, AGENTS.md, recent specs, known pitfalls, or architectural decisions to ask informed questions. E.g., "Your AGENTS.md lists a pitfall about X — does this feature touch that area?"

---

## [mechanical] Step 0 — Handle --resume

If `--resume` is in $ARGUMENTS:
1. Search `docs/sessions/` for files matching `interview-*.md`, sorted by modification date (most recent first).
2. Find the first file where the `Routed to:` line is empty or missing (incomplete interview).
3. If found: read the file, identify the last completed phase, report "Resuming interview: <topic> — picking up at Phase <N>." Then jump to the appropriate phase below.
4. If no incomplete interview found: report "No incomplete interviews found in docs/sessions/. Start a new one with `/interview <topic>`." Stop.

---

## [mechanical] Step 1 — Establish topic and transcript

1. Determine the topic:
   - If $ARGUMENTS provides a topic (anything that isn't `--resume`, `?`, or `help`): use it.
   - If no topic: check recent conversation context for an obvious subject. If found, propose it: "It sounds like you're thinking about <topic> — shall we explore that, or something else?"
   - If no context: ask "What would you like to explore?" and wait. Use the answer as the topic.

2. Create the transcript file at `docs/sessions/interview-<slug>-YYYY-MM-DD.md` where `<slug>` is a lowercase-hyphenated version of the topic (max 40 chars). Write the header:

```markdown
# Interview: <topic>
Date: YYYY-MM-DD
Duration: ~0 exchanges
Routed to:

## Transcript
```

3. Read the following files for project context (skip silently if missing):
   <!-- parallel: all reads are independent -->
   - `CLAUDE.md`
   - `AGENTS.md`
   - `docs/specs/README.md`
   - `docs/backlog.md`
   - `docs/sessions/signals.md`

   Use this context to inform your questions throughout the interview. Do not dump this context to the user — weave it into specific, targeted questions.

---

## [decision] Phase 1 — Understand the context (2-3 questions)

Goal: understand the starting point, motivation, and desired outcome.

Ask 2-3 context-setting questions, **one at a time**, adapted to the topic type:

**For technical topics** (new feature, architecture, refactoring):
- "What triggered this? What changed or broke that made you think about this now?"
- "How does this work today? Walk me through the current state."
- "What would success look like? If this were solved perfectly, what's different?"

**For process/strategy topics** (workflow, team practices, prioritization):
- "What's the pain point? What's not working with the current approach?"
- "Who else is affected by this? What are the stakeholders' perspectives?"
- "What outcome are you optimizing for — speed, quality, predictability, something else?"

**For decision/tradeoff topics** (should we X vs Y, buy vs build):
- "What's forcing this decision now? Is there a deadline or trigger?"
- "What have you already ruled out, and why?"
- "What's the cost of doing nothing — of deferring this decision?"

Adapt these to the specific topic. Do not ask generic questions when you have project context that enables specific ones.

After each answer, acknowledge briefly (1 sentence max) before asking the next question. Do not summarize or analyze yet.

**After Phase 1 completes:** append all Q&A from this phase to the transcript file. Update the exchange count.

---

## [decision] Phase 2 — Explore the problem space (3-5 Socratic probes)

Goal: challenge assumptions, surface hidden constraints, reveal tradeoffs.

Ask 3-5 probing questions, **one at a time**. Each question should do one of:

- **Challenge a stated assumption.** "You mentioned <X> — what if that assumption is wrong? What changes?"
- **Surface a hidden constraint.** "What about <Y>? I notice your project has <context from CLAUDE.md/AGENTS.md> — does that affect this?"
- **Reveal a tradeoff.** "If you optimize for <A>, you're implicitly deprioritizing <B> — is that acceptable?"
- **Test boundaries.** "What happens if this fails? What's the blast radius?" or "What's the cost of not doing this at all?"
- **Probe the opposite.** "What's the strongest argument against doing this?"

Play devil's advocate. If the user seems committed to one path, probe alternatives. If the user is uncertain, help them narrow by testing each option against their stated goals.

Adapt question count to complexity:
- Simple, well-understood topic: 2-3 probes may suffice.
- Complex, ambiguous topic: 5+ probes. Keep going until the problem space feels mapped.
- Watch for repetitive answers — that's a signal to move on.

**After Phase 2 completes:** append all Q&A from this phase to the transcript file. Update the exchange count.

---

## [decision] Phase 3 — Explore options (2-4 approaches)

Goal: identify distinct approaches and probe the tradeoffs of each.

1. Based on everything discussed so far, identify 2-4 distinct approaches. Name each one clearly (e.g., "Option A: Full rewrite," "Option B: Incremental migration," "Option C: Thin adapter layer").

2. Present the options as a brief list (1-2 sentences each), then probe each one. You may add an option the user hasn't considered — this is where your knowledge adds value.

3. For each option, ask 1-2 questions covering:
   - **Effort**: "How much work is this? What's the smallest version that would deliver value?"
   - **Risk**: "What could go wrong? What's the worst realistic outcome?"
   - **Reversibility**: "If this doesn't work out, how hard is it to undo or change course?"
   - **Dependencies**: "What does this need that doesn't exist yet?"

   Ask these **one at a time** across the options. You do not need to ask all four dimensions for every option — focus on the dimensions that differentiate the options.

**After Phase 3 completes:** append all Q&A from this phase to the transcript file. Update the exchange count.

---

## [mechanical] Phase 4 — Synthesize

Goal: present a structured analysis of everything discussed. This phase is agent output, not questions.

Write the synthesis in this format:

```markdown
## Interview Synthesis: <topic>

### Context
<2-3 sentence summary of the starting point, motivation, and current state. Reference what the user said in Phase 1.>

### Key Insights
- <insight 1 — something the user discovered or clarified during the interview>
- <insight 2 — a constraint or tradeoff that was surfaced>
- <insight 3 — a shift in thinking that occurred>

### Options

| Option | Effort | Risk | Reversibility | Key tradeoff |
|--------|--------|------|---------------|--------------|
| A: <name> | <L/M/H> | <L/M/H> | <Easy/Hard> | <one sentence> |
| B: <name> | <L/M/H> | <L/M/H> | <Easy/Hard> | <one sentence> |
| C: <name> | <L/M/H> | <L/M/H> | <Easy/Hard> | <one sentence> |

### Recommendation
<Your recommendation with reasoning. 2-3 sentences. Reference specific things the user said during the interview that inform this recommendation. If there is no clear winner, say so honestly. If the user's preferred option has a serious flaw, say so.>

### Open Questions
- <anything that came up but wasn't resolved>
- <decisions that need more information>
```

**Be honest in the synthesis.** If the tradeoffs are genuinely hard, don't pretend there's an obvious answer. If the user is leaning toward an option with a serious flaw you surfaced, note it. Understatement bias: present findings factually rather than dramatically.

**After Phase 4 completes:** append the full synthesis to the transcript file. Update the exchange count in the header.

### [decision] Save to PRD (Spec 147)

After presenting the synthesis, offer to save it as a PRD:

```
Save this synthesis as a Project Requirements Document?
The PRD will be written to docs/process-kit/prd.md using the standard template.

Save to PRD? (yes / no)
```

- If **yes**: read `docs/process-kit/prd-template.md` (if it exists) as the base structure.
  Populate the template sections from the interview synthesis:
  - **Vision** — from the Context section
  - **Personas** — inferred from discussion of users/stakeholders
  - **Pillars** — from Key Insights (reframed as guiding principles)
  - **Phased Roadmap** — from the Options discussion and Recommendation
  - **Success Metrics** — from any measurable outcomes discussed
  - **Open Questions** — directly from the synthesis Open Questions
  Write the result to `docs/process-kit/prd.md`. Report: "PRD saved to docs/process-kit/prd.md"
- If **no**: continue to deferred-field check below, then Phase 5.

### [decision] Deferred stack resolution (Spec 162)

After the PRD save decision (whether yes or no), check for deferred onboarding fields:

1. Read `.forge/onboarding.yaml`. If the file does not exist, skip this section.
2. Check if `project.primary_stack` is `deferred`.
3. If `primary_stack` is NOT `deferred`: skip this section silently.
4. If `primary_stack` IS `deferred`, prompt:

   ```
   ## Deferred Stack Selection
   You deferred stack selection during onboarding. Based on the interview,
   would you like to choose your stack now?

   Primary language/framework:

   | # | Option |
   |---|--------|
   | 1 | Python |
   | 2 | TypeScript / JavaScript |
   | 3 | Go |
   | 4 | Rust |
   | 5 | Java / Kotlin |
   | 6 | C# / .NET |
   | 7 | Other (specify) |
   | 8 | Not yet — keep deferred |

   Choose (1-8, or type a framework name):
   ```

5. If **8** (keep deferred): report "Stack selection remains deferred." Skip test/lint resolution.
6. If **7**: ask "What language/framework?" then proceed to step 7.
7. For choices 1-7: update `.forge/onboarding.yaml`:
   - Set `project.primary_stack` to the chosen value
   - Then ask for test and lint commands using the defer-to-AI pattern:
     ```
     Do you have a preferred test tool, or should I use the standard one for <primary_stack>?
     1. I have a preference (tell me what you'd like)
     2. Use the default for <primary_stack>
     ```
     Set `project.test_command` accordingly.
     Repeat for lint command. Set `project.lint_command` accordingly.
   - Write the updated `.forge/onboarding.yaml`.
   - Report:
     ```
     Updated onboarding.yaml:
       primary_stack: <chosen>
       test_command: <chosen or default>
       lint_command: <chosen or default>
     ```

---

## [decision] Phase 5 — Route

Goal: the user decides what to do with the interview output.

Present the routing options:

```
What would you like to do with this?

1. Create spec(s) — I'll draft spec(s) based on this interview
2. Create ADR — document this as an architecture decision
3. Save to scratchpad — capture the key takeaway for later
4. Brainstorm further — run /brainstorm to find related work
5. Done — the conversation was enough
```

Wait for the user's choice, then execute:

### Route 1 — Create spec(s)
Propose 1-3 spec titles based on the interview. Each title should map to a concrete deliverable discussed during the interview. Ask the user which to create. For each selected spec, run `/spec` with pre-filled context:
- Objective from the synthesis Context and Recommendation sections
- Scope from the options discussion (chosen option = in scope; rejected options = out of scope)
- Constraints from Phase 1 answers
- Requirements derived from Key Insights

### Route 2 — Create ADR
Write `docs/decisions/ADR-NNN-<slug>.md` using the synthesis as the decision record. Read existing ADRs to determine the next number. Structure: Status, Context (from synthesis Context), Decision (from Recommendation), Consequences (from Options tradeoffs and Open Questions).

### Route 3 — Save to scratchpad
Append a structured note to `docs/sessions/scratchpad.md`:
```markdown
### Interview: <topic> (YYYY-MM-DD)
**Key insight**: <one-sentence takeaway from the interview>
**Full transcript**: docs/sessions/interview-<slug>-YYYY-MM-DD.md
**Open questions**: <list from synthesis>
```

### Route 4 — Brainstorm further
Run `/brainstorm <topic>` using the interview topic as the focus filter.

### Route 5 — Done
No further action.

**After routing:** update the transcript file header — set `Routed to:` to the chosen route (e.g., `spec 076`, `ADR 005`, `scratchpad`, `brainstorm`, `none`).

Report: "Interview complete. Transcript saved to docs/sessions/interview-<slug>-YYYY-MM-DD.md. To convert these findings into spec candidates, run `/brainstorm`."

> **Choose** — type a number or keyword:
> | # | Action | What happens |
> |---|--------|--------------|
> | **1** | `/spec` | Create a spec from this interview |
> | **2** | `/brainstorm` | Discover related spec opportunities from these findings |
> | **3** | `/now` | Review project state |
>
> _(See [Command Reference](docs/QUICK-REFERENCE.md) for all commands)_

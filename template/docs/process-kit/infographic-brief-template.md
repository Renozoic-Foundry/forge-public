# Infographic Brief Template
*FORGE standard artifact — process-only lane*

> **What is an Infographic Brief?**
> A condensed, bullet-point synthesis of a project's vision, architecture, pillars, and key
> metrics — organized as a narrative arc so a wide audience (technical, executive, general)
> can understand what matters about the project and why. Intended as the authoritative input
> brief for producing a cinematic or visual architecture infographic.
>
> **When to produce one:** When the project reaches its first stakeholder-ready milestone
> (PoC complete, first demo, board presentation, or major phase completion). See
> `docs/publications/TRIGGERS.md` for the full milestone table (Milestone 8).

---

## How to fill this template

1. Replace all `<...>` placeholders with project-specific content.
2. Delete guidance lines (lines starting with `>`).
3. Remove sections that genuinely don't apply — but keep at least the first six.
4. Update the key numbers table to reflect the current platform state.
5. Save as `docs/presentations/<project-slug>-infographic-brief-<YYYY-MM-DD>.md`.
6. Register it in `docs/publications/REGISTRY.md`.

---

# `<Project Name>` — Infographic Brief
*Generated: `<YYYY-MM-DD>` | Platform version: `<vX.Y.Z>`*

> **Purpose:** Condensed bullet-point brief for producing a high-impact cinematic architecture
> infographic. Organized as a narrative arc: problem → metaphor → foundation → architecture →
> evolution → principles.

---

## Hero Statement

> Write 2–3 bullets. Lead with the single most important thing about the project: what it is
> and what it does for its users. Include the naming origin or inspiration if there is one.

- **"`<The single most important sentence about the project>`"**
- `<Naming origin or inspiration, if relevant>`
- Mission: `<make X visible / navigable / actionable — what does the platform enable?>`

---

## The Problem (Before)

> Describe the "before state" — what pain, fragmentation, or gap this project addresses.
> Be concrete. Name the silos, the workarounds, the missing connections.

- `<Where does information currently live that shouldn't — decks, email, institutional memory?>`
- `<What can users not see or do today that they need to?>`
- `<What data silos exist? Name the systems.>`
- `<What is the cumulative effect of this fragmentation?>`

---

## The Core Metaphor

> If the project has a powerful central metaphor, name it here. A good metaphor makes the
> "before → after" transformation visceral and memorable. Skip this section if there isn't one.

- Before: `<scattered state — e.g., "white light: many sources, no focus">`
- After: `<focused state — e.g., "business laser: singular focus, inherent direction">`
- Aimed at: `<the ultimate target — e.g., "Best Customer Experience">`

---

## Foundation: Core Constructs / Pillars of the Domain

> List the foundational concepts the project is built on. For domain platforms, these are
> often the "laws" or "constructs" of the domain. For technical platforms, these may be
> the core design principles or architectural invariants.
> Number them. Include a one-line "what this means" and a one-line "what the platform does with it."

1. **`<Construct 1 name>`** — "`<tagline>`" → `<what the platform surfaces or enables for this>`
2. **`<Construct 2 name>`** — "`<tagline>`" → `<what the platform surfaces or enables for this>`
3. **`<Construct 3 name>`** — "`<tagline>`" → `<what the platform surfaces or enables for this>`
4. *(add as needed)*

---

## Operating Model / Control Loop

> Describe how the system works end-to-end as a feedback loop. Good visual framing:
> Inputs → Controller → Execution → Output → Feedback.
> Use this structure if it applies; adapt freely.

- **Inputs**: `<what feeds the system>`
- **Controller**: `<what governs / steers the system>`
- **Execution**: `<who or what acts>`
- **Output**: `<what is produced>`
- **Feedback loop**: `<how outputs loop back to improve the system>`

---

## Platform Pillars

> List the 3–7 functional areas of the platform. Each pillar is a named area of capability.
> One sentence each: name + what it contains/does.

1. **`<Pillar 1>`** — `<what it contains and what it enables>`
2. **`<Pillar 2>`** — `<what it contains and what it enables>`
3. **`<Pillar 3>`** — `<what it contains and what it enables>`
4. *(add as needed)*

---

## Architecture & Tech Stack

> Bullet-point the technical architecture. Focus on what is distinctive or surprising —
> not every library, just the choices that explain why the system works the way it does.
> Include key scale numbers if known.

- **`<Primary architectural pattern>`**: `<brief description>`
- **`<Key database or data store>`**: `<type and role>`
- **Scale**: `<X nodes / Y records / Z integrations / etc.>`
- **Frontend**: `<stack>`
- **AI / ML**: `<models, providers, or techniques>`
- **Standards alignment**: `<relevant open standards the design follows>`
- **Key constraint 1**: `<e.g., "graph-relationship-first">`
- **Key constraint 2**: `<e.g., "temporal-first">`

---

## Guiding Engineering Principles

> 3–7 principles that constrain every technical decision. These are the "rules of the road"
> that prevent architectural drift. Be specific — not generic platitudes.

1. **`<Principle name>`** — `<one-sentence rule>`
2. **`<Principle name>`** — `<one-sentence rule>`
3. **`<Principle name>`** — `<one-sentence rule>`
4. *(add as needed)*

---

## Evolution Roadmap (Phases)

> Summarize the build-out arc as numbered phases. One line each: phase name + what it adds.
> Mark completed phases with *(Complete)*.

1. **`<Phase 1 name>`** *(Complete)* — `<what was built>`
2. **`<Phase 2 name>`** — `<what will be built>`
3. **`<Phase 3 name>`** — `<what will be built>`
4. *(add as needed)*

---

## Leadership / Design Principles

> If the project is grounded in an explicit set of leadership or design principles (from
> the organization, from a methodology, or defined by the project), list them here.
> These differ from engineering principles above — they describe *how the team works* and
> *how the product should feel to use*.

1. **`<Principle>`** — `<one-sentence application to the product>`
2. **`<Principle>`** — `<one-sentence application to the product>`
3. *(add as needed)*

---

## User Personas

> Name 2–5 personas. For each: name/role + the single most important question they bring
> to the platform.

- **`<Persona 1>`** — "`<their key question>`"
- **`<Persona 2>`** — "`<their key question>`"
- **`<Persona 3>`** — "`<their key question>`"
- *(add as needed)*

---

## Key Numbers (`<vX.Y.Z>` — `<YYYY-MM-DD>`)

> A metric table. Include whatever numbers make the platform feel real and substantial.
> Prefer concrete counts over vague qualifiers.

| Metric | Value |
|--------|-------|
| `<Metric 1>` | `<Value>` |
| `<Metric 2>` | `<Value>` |
| `<Metric 3>` | `<Value>` |
| *(add rows as needed)* | |

---

## What `<Project Name>` Is NOT

> Explicit scope boundaries. Prevents misunderstanding in stakeholder conversations.
> Be direct.

- Not `<common misunderstanding 1>`
- Not `<common misunderstanding 2>`
- Not `<common misunderstanding 3>`
- Not dependent on `<vendor or single point of failure>`

---

*Source documents: `<list the 2–4 primary source docs synthesized to produce this brief>`*

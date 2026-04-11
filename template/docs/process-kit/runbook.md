# Operational Runbook

Last updated: 2026-03-13

This runbook covers operational procedures for FORGE-managed projects. For human validation of AI-delivered work, see [human-validation-runbook.md](human-validation-runbook.md).

---

## Kill Switch Procedure

The kill switch is a mandatory safeguard at all autonomy levels. It immediately halts agent activity, preserves state for review, and reverts to L1 (human-gated) autonomy.

### When to Trigger

Trigger the kill switch when any of the following occur:

- **Budget breach**: Agent exceeds lane budget ceiling (tokens, cost, time, or retries)
- **Scope escape**: Agent is modifying files outside the spec's declared scope
- **Unexpected behavior**: Agent output is nonsensical, repetitive, or contradicts instructions
- **Security concern**: Agent appears to be exposing secrets, credentials, or sensitive data
- **Cascading failures**: Agent is in a retry loop or producing compounding errors
- **Human judgment**: Anything feels wrong — the kill switch is zero-cost to trigger

### Procedure

**Step 1 — Halt**

Stop the agent immediately using the most appropriate method:

| Environment | Action |
|-------------|--------|
| Claude Code CLI | `Ctrl+C` to interrupt; close terminal if unresponsive |
| Claude Code IDE | Click "Stop" in the agent panel; close the panel if unresponsive |
| API / automated | Revoke or rotate the API key; cancel pending requests |
| CI/CD pipeline | Cancel the running job; disable the workflow trigger |

**Step 2 — Preserve State**

Before making any changes, capture the current state:

1. **Save the conversation/session**: Copy or export the full agent conversation
2. **Capture git state**: Run `git status`, `git diff`, and `git log --oneline -10` — save output
3. **Screenshot any errors**: Capture terminal output, error messages, or unexpected behavior
4. **Note the trigger**: Record what caused you to pull the kill switch

**Step 3 — Report**

Create a kill switch incident record:

```markdown
## Kill Switch Incident — YYYY-MM-DD

- **Trigger**: (what caused the kill switch)
- **Autonomy level at time**: L_
- **Active spec**: NNN — (spec name)
- **Files modified**: (list from git status)
- **Agent state**: (what the agent was doing when halted)
- **Git state**: (clean / dirty — include diff summary)

### Assessment
- **Damage**: (none / contained / needs revert)
- **Root cause**: (budget breach / scope escape / bug / other)
- **Action taken**: (see Step 4)
```

Save this to the session log (`docs/sessions/YYYY-MM-DD-NNN.md`) or create a new session log if one does not exist.

**Step 4 — Assess and Act**

Evaluate the state and choose an action:

| Situation | Action |
|-----------|--------|
| Work is clean and on-track, just hit a budget ceiling | Extend budget and resume at current level |
| Work is off-scope but salvageable | `git stash` the changes; revise the spec scope; resume at L1 |
| Work is incorrect or harmful | `git checkout -- .` to discard changes; revert to L1; review spec |
| Unclear what happened | `git stash` to preserve; revert to L1; review conversation log |

**Step 5 — Revert Autonomy to L1**

After any kill switch event, the project autonomy resets to L1 (human-gated) regardless of the previous level. To re-escalate:

1. Complete the current spec at L1 successfully
2. Conduct a root-cause review of the kill switch event
3. Document findings in a process improvement spec or signal
4. Re-evaluate graduation criteria before raising autonomy level

---

## Budget Monitoring

### Checking Budget Status

During a session, monitor resource consumption against lane ceilings:

| Metric | How to Check |
|--------|-------------|
| Token usage | Check conversation length; estimate ~4 chars per token |
| Wall-clock time | Note session start time; check elapsed |
| Retry count | Count failed attempts at the same task |
| API cost | Check provider dashboard if available |

### Budget Breach Protocol

1. Agent detects ceiling approach (80% threshold) → warns human
2. Agent hits ceiling → pauses immediately (same as kill switch Step 1)
3. Human reviews work completed so far
4. Human authorizes: extended budget, scope reduction, or session end

---

## Autonomy Escalation

### Requesting a Level Increase

To move from the current autonomy level to a higher one:

1. Verify graduation criteria are met (see AGENTS.md trust model configuration)
2. Review kill switch incident history — any incidents in last 10 specs disqualifies
3. Human explicitly approves the new level in AGENTS.md
4. Document the change in a session log with rationale

### Emergency De-escalation

Any of these conditions trigger automatic de-escalation to L1:

- Kill switch triggered (any reason)
- Escaped defect found in production
- Agent modifies files outside spec scope
- Budget ceiling breached without warning
- Human requests de-escalation (no justification needed)

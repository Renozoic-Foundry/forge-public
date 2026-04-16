<!-- Last updated: 2026-04-14 -->
# Branch-Per-Spec Workflow

How FORGE maps to standard Git branching, pull requests, and code reviews in multi-developer teams.

---

## Branch naming convention

Spec-backed branches use the format:

```
spec/NNN-short-name
```

Examples:
- `spec/042-add-login-page`
- `spec/105-session-briefing`
- `spec/253-branch-workflow`

Non-spec branches (bug fixes, config updates, exploratory work) use your team's existing conventions — FORGE doesn't constrain them.

---

## Spec number allocation

Before creating a branch, pick the next available spec number:

1. Check `docs/specs/README.md` on `main` for the highest existing number
2. Use the next number for your spec
3. Create your branch: `git checkout -b spec/NNN-short-name`

**What if two developers pick the same number?** This requires both developers to branch from the same `main` state before either merges. It's rare. When it happens, the second developer to merge renames their spec file and branch:

```bash
# Rename spec file
git mv docs/specs/042-my-feature.md docs/specs/043-my-feature.md
# Update spec number inside the file
# Rename branch
git branch -m spec/042-my-feature spec/043-my-feature
```

No shared counter file or registry is needed — Git's merge semantics handle the edge case naturally.

---

## Spec-on-branch convention

The spec file lives on the feature branch alongside the implementation:

1. **Create the spec** on your branch: copy `docs/specs/_template.md` to `docs/specs/NNN-short-name.md`, or run `/spec` in Claude Code
2. **Implement** on your branch: `/implement NNN` runs entirely on the branch
3. **Commit both** together: the spec and the code travel as a reviewable unit

This means the PR contains both the spec (what was planned) and the implementation (what was built). Reviewers see the full picture.

---

## PR description format

PRs for spec-backed branches use this template:

```markdown
## Spec NNN — <title>

**Objective**: <first sentence from spec's Objective section>

### Acceptance Criteria
- [ ] AC1: <text from spec>
- [ ] AC2: <text from spec>
- [ ] AC3: <text from spec>

Spec file: `docs/specs/NNN-short-name.md`
```

This gives reviewers — including those who don't use FORGE — a structured checklist. The reviewer checks ACs against the diff, same as any PR checklist.

**Copy-paste shortcut**: the spec's Acceptance Criteria section is the PR checklist. No reformatting needed.

---

## Post-merge /close discipline

**Hard rule: tracking files are updated ONLY after merge, never on feature branches.**

These files are off-limits on feature branches:
- `docs/backlog.md`
- `docs/specs/CHANGELOG.md`
- `docs/specs/README.md` (index entries for your own spec are OK; don't modify other specs' entries)

**After your PR merges to main**, run `/close NNN` on main. This is the only moment tracking files are updated — it happens atomically, one spec at a time, eliminating merge conflicts.

**Ownership**: The PR author runs `/close` after merge. Target: same working day as merge. If the author is unavailable, any team member with FORGE access can run `/close NNN` — the spec file contains all the context needed.

**What if /close isn't run?** Tracking files drift — backlog shows old status, changelog has gaps, spec index is stale. This drift is recoverable, not catastrophic: the next `/close NNN` run updates all tracking files atomically. `/evolve` reviews flag tracking inconsistencies when they accumulate. If the PR author can't close same-day, they should leave a PR comment noting who will run `/close` and when.

---

## Partial adoption

FORGE and non-FORGE PRs coexist. Two team policies:

**FORGE-optional** (recommended for adoption): Spec-backed PRs are encouraged for features and significant changes. Bug fixes, config updates, and small tweaks don't need specs. Non-FORGE developers submit PRs normally — their work is not blocked or gated by FORGE.

**FORGE-required**: All non-trivial changes need specs. The team agrees on what "non-trivial" means (e.g., touches more than 2 files, adds a feature, changes behavior). Trivial changes (typos, dependency bumps) are exempt.

In both policies:
- Non-spec PRs merge normally
- Spec-backed PRs include the spec file in the diff
- Code review standards are the same for both — FORGE adds structure, not gatekeeping
- See [Team Guide](../team-guide.md) for how non-FORGE developers navigate specs

---

## How FORGE review complements PR review

| Review | When | What it checks | Who does it |
|---|---|---|---|
| **Devil's Advocate** | Before implementation (on branch) | Spec design: gaps, risks, assumptions | AI agent (automated) |
| **PR code review** | After implementation (at PR) | Code quality, correctness, edge cases | Human reviewer |
| **Validator** | At /close (on main) | ACs satisfied, evidence verified | AI agent (automated) |

These are complementary, not redundant:
- DA catches spec-level problems before code is written
- PR review catches implementation-level problems after code is written
- Validator confirms the spec's acceptance criteria are satisfied

A reviewer who sees `DA-Reviewed: 2026-04-14` in the spec knows the design was challenged before implementation began. They can focus on code quality rather than re-evaluating the approach.

---

## Quick reference

| Step | Command | Where | Who |
|---|---|---|---|
| Pick spec number | Check `docs/specs/README.md` | main | Developer |
| Create branch | `git checkout -b spec/NNN-name` | main | Developer |
| Create spec | `/spec` or copy template | branch | Developer |
| Implement | `/implement NNN` | branch | Developer + AI |
| Submit PR | `gh pr create` | branch | Developer |
| Code review | Standard PR review | PR | Reviewer |
| Merge | Merge PR to main | PR | Reviewer/Developer |
| Close spec | `/close NNN` | main | PR author |

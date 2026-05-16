# Stoke Recovery Runbook

**Status**: Active mitigation for the 2026-05-14 `/forge stoke` data-loss defect class. Tracked by Spec 426 (this runbook + preflight guard) and Spec 427 (the underlying fix). Removed when Spec 427 closes.

This runbook applies only to checkouts that ran `/forge stoke` against `.forge/lib/stoke.py` versions that lack the marker `# Spec 427: .git/** exclusion enforced`.

The accompanying defect report is at [`docs/bug_reports/forge-stoke-defect-report-2026-05-14.md`](../bug_reports/forge-stoke-defect-report-2026-05-14.md).

---

## 1. Symptoms

If you ran stoke against an unfixed `.forge/lib/stoke.py`, you may see one or both of these signatures.

### 1a. Git database corruption

```
$ git status
fatal: bad object HEAD
```

Variations: `fatal: bad object refs/heads/<branch>`, `error: object file ... is empty`, `error: unable to read ...`. Any "bad object" or "unable to read" error from a previously-healthy repo immediately after a stoke run is consistent with this defect class.

The root cause is that the unfixed `stoke.py` shadow/apply cycle could write into `.git/` (objects, refs, logs) during conflict resolution, corrupting the object database or moving the branch tip to a tree that no longer matches reachable objects.

### 1b. Project-data overwrite (silent)

After stoke, files that should carry your project's accumulated history are reduced to template stubs:

- `docs/specs/CHANGELOG.md` — only the template header and a single example row remain.
- `docs/backlog.md` — template "add your specs here" placeholder content.
- `README.md` — back to the template's bootstrap README.

This is silent — no error is emitted. You discover it when you `git diff` after the run and see hundreds of deletions across formerly-rich documents. The Spec 426 disclosure was triggered by a SmileyOne incident where ~700 lines were lost across a single stoke run and not detected for ~30 days.

---

## 2. Recovery commands (git database corruption)

If your repo is in the "fatal: bad object HEAD" state, the working tree itself is usually intact — only the index and refs are broken. Recovery is reflog-based.

### 2a. Find the last-good SHA

The branch reflog stores every ref movement. The pre-stoke commit tip is recorded there even when `git log` no longer works.

```bash
# Reflog lives on disk regardless of refs being broken:
cat .git/logs/refs/heads/<branch>            # e.g. main, master, the branch you were on
```

Each line is `<old-sha> <new-sha> <author> <timestamp> <message>`. The **second column of the last-good line** (typically the most recent line before the stoke-related entries, or any line whose message is NOT a stoke artifact) is your `<last-good-SHA>`. Verify it points at a real commit:

```bash
git cat-file -t <last-good-SHA>              # should print: commit
git cat-file -p <last-good-SHA> | head -20   # should print a sensible tree/parent/author/message
```

If `git cat-file -t` returns "bad object," the object itself is missing — see § 2c.

### 2b. Reset the broken ref and rebuild the index

```bash
git update-ref refs/heads/<branch> <last-good-SHA>
git read-tree --reset -u HEAD
git status
```

`update-ref` rewrites the broken ref pointer directly without invoking the higher-level `git reset` (which itself would fail on "bad object HEAD"). `read-tree --reset -u HEAD` rebuilds the index and working tree to match the now-restored HEAD.

After this sequence, `git status` should print a clean tree. Verify with `git log -1` that the tip is the expected commit.

### 2c. If `<last-good-SHA>` is itself a "bad object"

The object database is partially destroyed. Recovery options, in order of preference:

1. **Reclone**: if you have a remote (origin) and your local commits were pushed, `cd ..; rm -rf <repo>; git clone <remote>` is the fastest path.
2. **Pull from another machine**: if a teammate has a recent clone, copy `.git/` from theirs.
3. **`git fsck --lost-found`**: surfaces dangling objects under `.git/lost-found/`. Walk these manually with `git cat-file -p <sha>` to find your commit. This is the last resort.

There is no automated recovery for case 2c — manual triage is required. Open an issue against FORGE if you reach this state.

---

## 3. Recovery (project-data overwrite)

If git is healthy but `CHANGELOG.md`, `backlog.md`, `README.md`, etc. are reduced to template stubs:

```bash
# Identify the last commit before the destructive stoke:
git log --oneline -- docs/specs/CHANGELOG.md docs/backlog.md README.md | head -20

# Restore those files from that commit (do NOT reset the whole tree — you may have
# legitimate non-stoke work since then):
git checkout <last-good-SHA> -- docs/specs/CHANGELOG.md docs/backlog.md README.md
git status
git diff --stat                              # confirm restored content matches expectations
```

If you cannot identify a specific last-good SHA but you have a daily/weekly known-good tag, use that tag in place of `<last-good-SHA>`. Then re-apply any post-tag legitimate work manually.

---

## 4. Override (proceed-despite-risk)

The Spec 426 preflight guard hard-aborts `/forge stoke` when the Spec 427 fix marker is absent. If you understand the risk, have a known-good backup, and have a legitimate need to pull an unrelated upstream change before Spec 427 ships, set the override **in your shell environment** before invoking stoke:

```bash
# bash / zsh:
export FORGE_ACK_STOKE_RISK_2026_05_14=$(date +%F)
/forge stoke
```

```powershell
# PowerShell:
$env:FORGE_ACK_STOKE_RISK_2026_05_14 = (Get-Date -Format yyyy-MM-dd)
/forge stoke
```

**The variable name embeds the defect date** (`2026_05_14`) intentionally — you cannot set it once and forget what risk you accepted. When Spec 427 ships and the preflight is removed, this variable becomes inert.

**The variable MUST be inherited from the parent shell**. Agents (Claude, Aider, Cursor, etc.) MUST NOT `export` it inline within their own bash session as a workaround. The preflight does not distinguish at runtime — Spec 426 AC 8 is enforced as an operator-discipline rule and verified by the negative test in Spec 426's test plan, not as a runtime check.

---

## 5. Prevention until Spec 427 ships

While Spec 427 is open:

1. **Default to not running stoke**. The preflight will block you; resist the urge to immediately reach for the override env-var.
2. **If you must run stoke** (e.g., to pull an unrelated critical upstream change):
   - Commit and push the current state of your project to a remote you trust.
   - Tag the pre-stoke commit: `git tag pre-stoke-$(date +%F-%H%M)`.
   - Set the override env-var as in § 4.
   - Run stoke. After the run, `git diff` against the tag and verify project-data files (CHANGELOG, backlog, README, anything under `docs/sessions/`) are unchanged or only changed as you expect.
3. **If you discover the corruption days or weeks later**: § 2 and § 3 still apply — the reflog and remote both retain history far longer than the incident window.

When Spec 427 closes, this runbook will be archived (not deleted — historical reference for incident postmortems) and the preflight + README banner will be removed by Spec 427's `/implement`.

---

## 6. Stale-clone advisory (Spec 430 AC 6)

**Trigger**: you ran `/forge stoke` and copier exited with a `min version` error like:

```
Error: Template requires copier >= 9.4.0; installed version is 9.3.x
```

This is intentional. Spec 430 bumped `_min_copier_version` from 9.3.0 to 9.4.0 so consumers on stale FORGE checkouts (pre-Spec-427, when shadow-tree apply still existed) cannot accidentally trigger the old data-loss pipeline against a post-427 template. The bump produces a hard, operator-visible error from copier itself rather than a silent fallback.

**Operator action sequence**:

1. **Pull latest FORGE first** (most common case — your local checkout is pre-Spec-427):
   ```bash
   cd /path/to/your/project
   git pull   # pull your project's FORGE update tracking branch, OR
   # If your project uses copier-update directly:
   copier update --vcs-ref main --skip-answered --defaults
   ```
   Then re-run `/forge stoke`.

2. **If your FORGE checkout is already up-to-date AND copier 9.3.x is installed**: update copier itself:
   ```bash
   pip install --upgrade copier  # or pipx upgrade copier
   ```
   Verify with `copier --version`. Then re-run `/forge stoke`.

3. **If you can't update copier** (sandboxed environment, locked dependency manifest): contact the FORGE maintainer for guidance. **DO NOT** attempt to bypass the version gate — it exists to prevent the Spec 427 data-loss class against stale-clone consumers.

**Why version-pinning rather than env-var override**: Spec 426 used `FORGE_ACK_STOKE_RISK_2026_05_14` as an env-var override because the underlying fix hadn't shipped yet. Spec 427's fix HAS shipped — there is no legitimate reason to bypass the gate post-fix. The `_min_copier_version` bump replaces the env-var override entirely.

See: docs/specs/427-*.md (the architectural fix) and docs/specs/430-*.md (this gate's design).

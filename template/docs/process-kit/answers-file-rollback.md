# Answers-File Rollback Runbook

- Status: **active** (effective 2026-04-24)
- Spec: [294 — Copier-Native Placeholder Scrub and Migration](../specs/294-canonical-project-yaml-with-answers-projection.md)
- ADR: [ADR-294 — Copier-Native Placeholder Scrub](../decisions/ADR-294-copier-native-placeholder-scrub.md)

This runbook tells operators what to do if the Spec 294 scrub or migration leaves `.copier-answers.yml` in an unexpected state. The helper at `scripts/copier-hooks/scrub_answers.py` is invoked by Copier's `_tasks:` (on every `copier copy`/`copier update`) and `_migrations:` (one-shot on pre-294 → post-294 update). Both are atomic (temp-file + rename); partial writes cannot occur.

## Symptoms that point here

| Symptom | What it means |
|---|---|
| `/forge stoke` stderr: `Migration failed — ... See docs/process-kit/answers-file-rollback.md for recovery steps.` | The helper raised and aborted before mutating anything. `.copier-answers.yml` is untouched. |
| `.copier-answers.yml` contains legacy placeholder strings after `/forge stoke` | The `_migrations:` version gate did not fire (consumer was already above the pinned version), OR the `_tasks:` guard rejected the scrub (Copier default no longer matches the placeholder). See "Forcing a re-migration" below. |
| `.copier-answers.yml.pre-294.bak` exists but `.copier-answers.yml` looks wrong | The `before`-stage migration ran but the `after`-stage render produced an unexpected result. Restore from backup (see "Restore from backup"). |
| A field I legitimately set was blanked (e.g., my author name is literally "Your Name") | Extremely rare — the `_tasks:` guard should prevent this because it requires `copier.yml` default to equal the placeholder, which should never be true once Spec 290 shipped. If it happened: restore from `.pre-294.bak` and file a bug. |

## Restore from backup

The `_migrations:` heal creates `.copier-answers.yml.pre-294.bak` on first run (and never overwrites it on subsequent runs — so it preserves the earliest pre-migration state).

```bash
# From the consumer project root:
cp .copier-answers.yml.pre-294.bak .copier-answers.yml
```

If the backup is absent (e.g., first `_tasks:` scrub pass ran but `_migrations:` never did):

```bash
# Recover the last committed version:
git log --oneline -- .copier-answers.yml | head -5
git checkout <commit-before-stoke> -- .copier-answers.yml
```

Then commit the restored file and investigate the cause before running `/forge stoke` again.

## Forcing a re-migration

If you need to re-run the heal (e.g., for testing, or because the `before`-stage script had a known bug that has been fixed):

```bash
# Delete the backup so the helper creates a new one:
rm .copier-answers.yml.pre-294.bak

# Temporarily roll back the Copier answers `_commit` to a pre-294 version to
# make the _migrations: version gate fire:
python3 -c "
import yaml
with open('.copier-answers.yml') as f:
    data = yaml.safe_load(f)
data['_commit'] = 'v2.0.0'
with open('.copier-answers.yml', 'w') as f:
    yaml.safe_dump(data, f, sort_keys=False)
"

# Run the update — _migrations: will now see a crossing and fire.
/forge stoke
```

**Warning**: this is a test-only procedure. Do not use in production unless you know the heal is idempotent and desirable.

## Operator escape hatch — skip migration entirely

If the migration is demonstrably broken for your project (it blanked a field it should not have, or the `before`/`after` reload misbehaved), you can bypass it:

```bash
# Remove the _migrations: block from the pinned copier template temporarily,
# OR pass --data-file to copier with the _commit already at the post-294 version
# so the version gate does not fire.

# Simpler: set the COPIER_ANSWERS_FILE env var to a temp location for one run:
COPIER_ANSWERS_FILE=/tmp/scratch-answers.yml copier update .
```

After bypassing: apply the desired scrub manually (edit `.copier-answers.yml`), commit, and continue.

## When to file a bug

- The helper's stderr message was vague or did not name the failure mode
- The `_tasks:` guard blanked a field you legitimately set (Copier default must have matched the placeholder for this to happen; unexpected)
- The `_migrations:` heal ran twice (should be idempotent)
- The backup was overwritten on a repeat run (should be preserved)

File via `/note [bug] answers-file heal: <symptom>` and attach:
- The relevant `.copier-answers.yml` before/after
- The `.copier-answers.yml.pre-294.bak` if present
- The stderr output from the failing `/forge stoke` run
- Your Copier version (`copier --version`)

## Runtime contract (for implementers)

The helper at `scripts/copier-hooks/scrub_answers.py`:

- Reads `.copier-answers.yml` at CWD (Copier sets CWD to the destination project).
- Receives the template source path as `sys.argv[2]` (passed by `copier.yml`'s task invocation).
- Reads `copier.yml` defaults for allowlist fields from the source path.
- In `scrub` mode: blanks only when current value == legacy placeholder AND Copier default == legacy placeholder (both must be true — the "provably-inherited" guard).
- In `migrate` mode: blanks unconditionally when current value == legacy placeholder (version-gated by Copier).
- Writes atomically: `.copier-answers.yml.tmp` then `os.replace()`.
- Appends `.copier-answers.yml*.bak` to the consumer's `.gitignore` if absent (only in `migrate` mode, only if a scrub actually happened).
- Prints one summary line to stdout when a change is made; zero output on no-op.
- On failure: stderr names this runbook and exits non-zero; Copier aborts.

The legacy allowlist is PERMANENT — it must not be pruned even after all pre-294 consumers have upgraded. See ADR-294 for the retention rationale.

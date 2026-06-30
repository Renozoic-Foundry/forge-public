<!-- Last updated: 2026-06-12 -->
# Unit Test vs Integration Test — the Mocked-Framework-Internals Anti-Pattern

Version: 1.0 (Spec 451, 2026-06-12)

## Anti-pattern summary

> **CI-354 (verbatim)**: Spec 447's unit test PASSED because the test mocked
> `_copier_operation` explicitly in the Jinja eval context. Production FAILED
> because Copier doesn't bind `_copier_operation` in the validator's eval
> context during `old_worker.run_copy()`. The test contracted on the input
> production code *expects*, not on whether production actually *receives*
> that input. Silent failure mode: green CI + broken production.

**Unit-level confidence does not transfer to integration-level confidence when
framework internals are mocked.** A mock encodes your belief about the
framework's behavior. When that belief is wrong, the mock makes the test pass
*and* hides the wrongness — the worst of both worlds.

## Worked examples

### Example 1 — Spec 447: the `_copier_operation` mock

The unit test built a Jinja environment by hand and injected
`_copier_operation: "update"` into the context, then asserted the validator
expression evaluated correctly. It did — in the hand-built environment.
In production, Copier's `old_worker.run_copy()` path never binds
`_copier_operation` into the validator's eval context at all; the expression
raised, the consent gate fired during a phase it should have skipped, and
every consumer running `/forge stoke` hit it (Spec 445 hotfix). The mock
verified the expression's logic; nothing verified the binding's existence.

### Example 2 — SIG-437-C: the `_tasks:` hook syntax error hidden by collection

A Python syntax error in a `_tasks:` hook script survived to production
because the test imported helper functions from the hook module under
import-time mocking — the collection machinery never executed the file as
`__main__` the way Copier's task runner does. Import succeeded (the broken
branch was behind `if __name__`), the test passed, the consumer's bootstrap
failed.

### Example 3 — live, same day this doc shipped

The first-ever run of `test_fresh_copier_copy_e2e.sh` (this spec's own
fixture) caught a P0 no unit test could see: live `.worktrees/` directories
(never gitignored) became phantom-submodule gitlinks in copier's
dirty-template handling, making `copier copy` fail for any consumer while
every unit gate stayed green. Integration tests catch the failure modes you
didn't think to mock.

## Decision tree

When a test mocks a framework variable or framework-internal behavior, ask:

1. **Does production actually receive this variable in the same eval
   context?** If you have not verified this against the real framework code
   path → **integration test required.**
2. **Does the framework execute this file/hook the same way the test does?**
   (import vs `__main__`, collection vs subprocess, eval context vs template
   render) — if the execution mode differs → **integration test required.**
3. **Is the mocked value derived from framework documentation rather than
   observed behavior?** Docs drift across versions (`_copier_conf.src_path`
   semantics have changed before) → **integration test required**, and pin
   the framework version your assertion was observed against.

If all three answers are confidently "verified against the real path," the
unit test stands alone. Otherwise the unit test is a *complement to* — never
a substitute for — at least one integration-level test.

## AC requirement for spec authors

Any spec whose Test Plan includes mocking of `_copier_*`, `_copier_conf.*`,
or other framework-internal Jinja variables (or framework-internal execution
machinery such as `_tasks:` dispatch) **MUST also list at least one
integration-level test that exercises the actual framework code path** —
e.g., a real `copier copy --trust` / `copier update --trust` against a
fixture target, not a mocked equivalent. The pre-push fixtures shipped by
Spec 451 (`.forge/tests/test_fresh_copier_copy_e2e.sh`,
`.forge/tests/test_copier_update_from_old_commit.sh`) are the reference
implementations of this requirement.

Enforcement is reviewer-level (consensus/DA at spec review), not mechanical —
see Spec 451 § Verification Scope (b).

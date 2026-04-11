# Dependency Vetting Checklist

<!-- Last updated: 2026-03-27 -->

Use this checklist when reviewing new or significantly changed dependencies flagged by `/dependency-audit` or the `DEPENDENCY_REVIEW_REQUIRED` signal during `/implement`.

## When to use

- A new dependency is added to any manifest file (package.json, requirements.txt, pyproject.toml, Cargo.toml, go.mod, Gemfile, pom.xml, build.gradle)
- An existing dependency has a major version bump
- A dependency is replaced with an alternative

## Review criteria

For each flagged dependency, evaluate:

### 1. Provenance verification
- [ ] Package is published on the official registry (npmjs.com, pypi.org, crates.io, pkg.go.dev, rubygems.org, Maven Central)
- [ ] Package name matches the intended library (check for typosquatting: e.g., `lod-ash` vs `lodash`)
- [ ] Source repository is linked and accessible
- [ ] Package author/org matches the expected maintainer

### 2. Maintainer reputation
- [ ] Maintainer has a history of published packages
- [ ] Organization or maintainer is known in the ecosystem
- [ ] No recent reports of account compromise or hostile takeover
- [ ] Check: has the maintainer changed recently? (ownership transfers are a supply chain risk)

### 3. Popularity and community
- [ ] Download count is reasonable for the package type (check weekly/monthly downloads)
- [ ] GitHub stars/forks indicate community adoption
- [ ] Package has recent activity (not abandoned — last commit within 12 months)
- [ ] Issues and PRs are being triaged (not ignored)

### 4. Known vulnerabilities
- [ ] No known CVEs for the target version (check: `npm audit`, `pip-audit`, `cargo audit`, `govulncheck`, `bundler-audit`)
- [ ] No active security advisories on the source repository
- [ ] If CVEs exist for older versions: confirm the target version includes fixes

### 5. Transitive dependency count
- [ ] Transitive dependency count is acceptable for the use case
- [ ] No deeply nested dependency trees that amplify supply chain risk
- [ ] Check: `npm ls --all`, `pip show <pkg>`, `cargo tree`, `go mod graph`

### 6. Lock file updated
- [ ] Lock file (package-lock.json, yarn.lock, poetry.lock, Cargo.lock, go.sum, Gemfile.lock) is updated and committed
- [ ] Lock file hashes are present and valid (integrity check)

### 7. Scope and necessity
- [ ] The dependency is necessary — no existing dependency or standard library covers the need
- [ ] The dependency scope is appropriate (dev-only deps are not in production dependencies)
- [ ] The functionality used justifies the dependency weight

## Sign-off format

After completing the review, record sign-off in the spec's Evidence section:

```
### Dependency Sign-off
- Reviewed by: <name or role>
- Date: YYYY-MM-DD
- Dependencies reviewed:
  - <package-name> (<version>): APPROVED — <brief justification>
  - <package-name> (<version>): APPROVED — <brief justification>
- Checklist items verified: all / partial (list exceptions)
- Notes: <any additional context>
```

## Skip gate format

If the dependency gate is bypassed (e.g., internal library, pre-vetted), record:

```
### Dependency Gate Skip
- Skipped by: <name or role>
- Date: YYYY-MM-DD
- Reason: <justification>
- Dependencies skipped: <list>
```

## Related commands

- `/dependency-audit` — scan for dependency changes and produce a risk report
- `/implement` — emits `DEPENDENCY_REVIEW_REQUIRED` when dependency changes detected
- `/close` — checks for dependency sign-off before allowing closure

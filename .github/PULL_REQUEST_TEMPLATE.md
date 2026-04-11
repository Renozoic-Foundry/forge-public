## Summary

<!-- 1-3 sentences: what does this PR do and why? -->

## Spec reference

<!-- Link to the spec that authorizes this change. Every change has a spec. -->
- Spec: NNN — Title

## Change lane

- [ ] `hotfix` — Critical fix to template output
- [ ] `small-change` — Low-risk template tweak
- [ ] `standard-feature` — New command, process addition, or cross-cutting change
- [ ] `process-only` — Changes to FORGE's own docs/tracking only

## Checklist

- [ ] Spec exists and is linked above
- [ ] Template output tested (`copier copy . /tmp/forge-test --defaults`)
- [ ] No unrendered template variables (`grep -r "cookiecutter" /tmp/forge-test/`)
- [ ] No Jinja2 artifacts leaked (`grep -r "{% raw %}" /tmp/forge-test/`)
- [ ] Shellcheck passes on modified `.sh` files
- [ ] Domain-neutral — no project-specific names, paths, or commands
- [ ] README.md updated if CLI commands, schema, or outputs changed

## Test evidence

<!-- Paste test output or link to CI run -->

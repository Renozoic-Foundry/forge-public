<!-- Last updated: 2026-04-10 -->
# Private Template Repos — Authentication Guide

When your FORGE template source (`_src_path` in `.copier-answers.yml`) points to a private Git repository, every machine and CI pipeline that runs `/forge stoke` needs authenticated access to that repo.

This guide covers setup patterns for private repos hosted on Azure DevOps, GitHub, GitLab, and other Git providers.

---

## Azure DevOps URL Format

Copier requires the `git+https://` prefix for Azure DevOps URLs. Without it, Copier misidentifies the URL as a local path (Copier issue #1956).

**Wrong** (will fail):
```
https://org@dev.azure.com/org/project/_git/repo
```

**Correct**:
```
git+https://org@dev.azure.com/org/project/_git/repo
```

`/forge init` auto-detects Azure DevOps URLs and corrects this automatically. If you set `_src_path` manually, use the `git+https://` prefix.

---

## Authentication Methods

### 1. SSH Rewrite (recommended for developer workstations)

Store a clean HTTPS URL in `_src_path` and tell git to transparently use SSH:

```bash
# Azure DevOps
git config --global url."git@ssh.dev.azure.com:v3/".insteadOf "https://dev.azure.com/"

# GitHub private
git config --global url."git@github.com:".insteadOf "https://github.com/"

# GitLab
git config --global url."git@gitlab.example.com:".insteadOf "https://gitlab.example.com/"
```

**Why this is preferred**:
- `_src_path` in `.copier-answers.yml` contains no secrets
- SSH key-based auth (no token expiry concerns)
- Works with `copier update` without additional config
- Every developer sets up SSH keys once; stoke works from then on

**Prerequisites**: SSH key generated and registered with your Git provider.

### 2. Git Credential Manager (recommended for enterprise environments)

For environments where SSH port 22 is blocked:

```bash
# Cross-platform — handles MFA, token refresh, multi-provider
git config --global credential.helper manager
```

Git Credential Manager (GCM) is the recommended credential helper. It supports:
- Azure DevOps, GitHub, GitLab, Bitbucket
- Multi-factor authentication
- Automatic token refresh
- Secure credential storage (OS keychain)

Install GCM: https://github.com/git-ecosystem/git-credential-manager

### 3. Credential Cache (temporary sessions)

For short-lived sessions where you don't want persistent credential storage:

```bash
# Cache credentials in memory for 1 hour
git config --global credential.helper 'cache --timeout=3600'
```

After the timeout, git will prompt again for credentials.

---

## Methods to Avoid

### `credential.helper store` (plaintext file)

```bash
# DO NOT USE — stores credentials in plaintext on disk
git config --global credential.helper store
```

This writes credentials to `~/.git-credentials` as plain text. Anyone with filesystem access can read them. Use `manager` (GCM) or `cache --timeout` instead.

### Embedded credentials in URLs

```
# DO NOT USE — credentials leak into .copier-answers.yml
https://user:ghp_mytoken123@github.com/org/repo.git
```

When you run `copier copy` with credentials in the URL, they are stored verbatim in `.copier-answers.yml` — which is committed to version control (Copier issue #466). Use SSH rewrite or GCM instead.

---

## CI/CD Patterns

### GitHub Actions

```yaml
steps:
  - uses: actions/checkout@v4
  - name: Configure git for private template
    run: |
      git config --global url."https://x-access-token:${{ secrets.TEMPLATE_PAT }}@github.com/".insteadOf "https://github.com/"
  - name: Run stoke
    run: copier update --defaults --trust
```

The PAT (`TEMPLATE_PAT`) must have read access to the template repository. Store it as a repository secret.

### Azure DevOps Pipelines

```yaml
steps:
  - script: |
      B64_PAT=$(echo -n ":$(TEMPLATE_PAT)" | base64)
      git config --global http.https://dev.azure.com/.extraheader "AUTHORIZATION: Basic $B64_PAT"
      copier update --defaults --trust
    env:
      TEMPLATE_PAT: $(TEMPLATE_PAT)
```

### Generic (any CI)

```bash
# Create a helper that echoes the token
export GIT_ASKPASS="$(mktemp)"
echo '#!/bin/bash' > "$GIT_ASKPASS"
echo 'echo "$GIT_TOKEN"' >> "$GIT_ASKPASS"
chmod +x "$GIT_ASKPASS"
export GIT_TOKEN="<your-pat>"

copier update --defaults --trust
```

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `ValueError: Local template must be a directory` | Azure DevOps URL missing `git+` prefix | Prefix with `git+https://` |
| `fatal: could not read Username` | No credential helper configured | Set up SSH rewrite or GCM |
| `fatal: Authentication failed` | Token expired or insufficient permissions | Regenerate PAT or re-add SSH key |
| `CREDENTIAL LEAKAGE WARNING` from `/forge stoke` | URL contains `user:token@host` | Remove embedded credential; use SSH or GCM |

---

## References

- [Copier FAQ — Credentials](https://copier.readthedocs.io/en/stable/faq/)
- [Copier issue #466 — HTTPS credential leakage](https://github.com/copier-org/copier/issues/466)
- [Copier issue #1956 — Azure DevOps URL detection](https://github.com/copier-org/copier/issues/1956)
- [Git Credential Manager](https://github.com/git-ecosystem/git-credential-manager)
- [Azure DevOps SSH Authentication](https://learn.microsoft.com/en-us/azure/devops/repos/git/use-ssh-keys-to-authenticate)
- [Git Credential Storage](https://git-scm.com/book/en/v2/Git-Tools-Credential-Storage)

# Team Permission Policy — `managed-settings` drop-in directory

> Distributing organization-wide Claude Code permission baselines that users cannot override. Read this when your deployment needs a **central authority** to ship policy (regulated Lane B environments, enterprise rollouts, shared lab machines).

## When to use this

Reach for managed settings when **any** of these apply:

- A compliance regime (SOC 2, HIPAA, IEC 61508) requires that tool permissions be centrally enforced and **cannot be weakened** by a developer editing their own `settings.json`.
- A team wants a shared baseline shipped via MDM / Group Policy / config management alongside other corporate tooling.
- You need to deny specific tools (`WebFetch`, `Bash(curl *)`, reads against `./.env*`) uniformly across every project on a machine.

If you only want shared-but-overridable defaults, commit `.claude/settings.json` to the project repo — managed settings are heavier machinery than that case needs.

## Where the files live

Claude Code reads managed settings from OS-specific system directories that require administrator privileges to write (which is the point — regular users cannot edit them):

| OS            | Path                                          |
|---------------|-----------------------------------------------|
| macOS         | `/Library/Application Support/ClaudeCode/`    |
| Linux / WSL   | `/etc/claude-code/`                           |
| Windows       | `C:\Program Files\ClaudeCode\`                |

The primary managed policy file is `managed-settings.json` in that directory. File-based managed settings also support a **drop-in directory structure**, so multiple teams (platform, security, compliance) can deploy independent fragments without editing one another's files. When multiple files are present they are merged: **scalar values** from later files (alphabetical order) override earlier ones, **objects** are deep-merged, and **arrays** are concatenated and de-duplicated.

## Minimal example

A managed fragment that enforces a security deny list and prevents bypass:

```json
{
  "permissions": {
    "deny": [
      "Bash(curl *)",
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)"
    ],
    "disableBypassPermissionsMode": "disable"
  },
  "allowManagedPermissionRulesOnly": true
}
```

Dropped at `/etc/claude-code/managed-settings.json` (Linux) or the OS-appropriate equivalent, this applies to every Claude Code session on that machine. The `allowManagedPermissionRulesOnly: true` flag means per-project `settings.json` cannot add permission rules beyond what the managed policy declares — the managed fragment becomes the only source of truth for `permissions.*`.

## Precedence model

From highest to lowest priority (higher wins on conflict):

1. **Programmatic options** — SDK callers passing `settingSources` / options directly.
2. **Managed policy settings** — the system-level files described above.
3. **Local project settings** — `.claude/settings.local.json` (git-ignored, per-developer overrides).
4. **Project settings** — `.claude/settings.json` (committed, team shared).
5. **User settings** — `~/.claude/settings.json` (per-user, per-machine).

Managed settings override everything except programmatic SDK calls. If a developer tries to widen permissions in their own `settings.json`, the managed layer wins at runtime. Consumers see the merged policy; they do not see a "managed policy denied your setting" error unless a `ConfigChange` hook surfaces one.

## Operational notes

- **Auditability**: pair managed settings with the `ConfigChange` hook (matcher `policy_settings`) to log every policy-file change. Note that `policy_settings` changes cannot be *blocked* by hooks — rely on filesystem permissions to prevent tampering.
- **Deployment**: ship via the same channel as other corporate policy (Ansible on Linux, MDM profile on macOS, Group Policy / Intune on Windows). Deploy **before** enabling Claude Code for the team — retrofitting silently narrows an already-wide runtime.
- **Testing**: stage the fragment on one machine and trigger a denied action (e.g., `Bash(curl https://example.com)`) to confirm the managed layer fires.

## Related reading

- [Claude Code settings documentation](https://docs.claude.com/en/docs/claude-code/settings) — authoritative key reference.
- [`devils-advocate-checklist.md`](devils-advocate-checklist.md) — use the security and scope checks when authoring a managed fragment for a regulated deployment.
- [`.claude/settings.json.template`](../../.claude/settings.json.template) — the project-level template this file complements; see the commented sandbox keys there for per-project controls that managed settings can override.

---

*Last verified against Claude Code documentation: 2026-04-21 (Spec 275 — sandbox.* keys and managed-settings directory paths confirmed current via context7 `/ericbuess/claude-code-docs` snapshot).*

#!/usr/bin/env bash
# FORGE shared git command-position detection helper (Spec 498, CTO R1).
#
# Sourced by BOTH check-commit-guard.sh and check-push-guard.sh — the command-position
# detection lives HERE, once, instead of being copy-pasted across two guards × two
# surfaces (.forge/bin + template/.forge/bin) = the CI-445 four-copy drift class.
#
# After this extraction the two guards differ ONLY in:
#   - matcher  : `commit` (commit guard) vs `push` (push guard)
#   - decision : `deny`   (commit guard) vs `ask`  (push guard)
#
# This file is SOURCED, never executed directly: it defines a function only and has no
# side effects at source time. It is in check-authority-guard.sh's protected/deny set
# (Spec 498 Req 3 / CISO R2) — both guards source it, so an unprotected helper would be
# a tamper target whose *detection* an agent could neuter without touching the protected
# guards. The security-bearing decision (ask/deny) stays in each guard; only detection
# lives here.

# forge_git_subcommand_at_command_position <subcommand> <command-string>
#   Returns 0 (true) iff <subcommand> (a literal git subcommand such as `commit` or
#   `push`) appears at SHELL COMMAND POSITION within <command-string>.
#
#   Preprocessing (identical to the pre-498 inline commit-guard logic — Spec 300/477):
#     1. Normalize newlines to spaces so the `^` anchor cannot match inside a heredoc
#        body line that literally starts with `git commit`/`git push` (docs, tutorials,
#        session logs that quote a git command).
#     2. Strip quoted substrings (both "…" and '…', non-greedy single-level) so shell
#        separators INSIDE quoted args (e.g. echo "use ; git push") do not fake a
#        command-position anchor. Nested/escaped quotes are a known limit — see
#        docs/process-kit/commit-guard-rationale.md.
#
#   Command-position anchors (the GUARD_RE leading group):
#     - start of the normalized string, or after a shell separator ; & | ( ) { } `
#     - after a command-wrapping keyword: xargs sudo env time nohup exec then else do
#     - after one or more env-var assignments (e.g. GIT_AUTHOR_DATE=… git commit)
#
#   Git global options (Spec 477): `git` accepts global options BEFORE the subcommand
#   (git -C <path> push, git --git-dir=… commit, git -c k=v push, git --no-pager …).
#   GIT_OPT_RE matches one such option group; (GIT_OPT_RE)* tolerates any repeated/mixed
#   sequence between `git` and the subcommand. The option group only matches `-`-prefixed
#   tokens (the -C/-c arg form requires a non-`-` arg token), so a bare non-option
#   subcommand (git frobnicate push) can NOT slip through, and git -C <path> status /
#   git -c x=y log are NOT detected (no false-positive). Known contrived over-block:
#   git -C push status (a directory literally named `push`/`commit`) is detected — this
#   fails TOWARD the guard's safe direction, never toward a bypass.
#
#   Trailing anchor: whitespace, a shell separator, or end-of-string, so `git push-tree`
#   / `git commit-tree` do NOT match.
forge_git_subcommand_at_command_position() {
  local subcommand="$1"
  local command="$2"
  local normalized stripped git_opt_re guard_re
  normalized=$(echo "$command" | tr '\n' ' ')
  stripped=$(echo "$normalized" | sed -E 's/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')
  git_opt_re='(-[Cc][[:space:]]+[^-][^[:space:]]*[[:space:]]+|-[^[:space:]]*[[:space:]]+)'
  guard_re='(^|[;|&()\{\}`]|(^|[[:space:]])(xargs|sudo|env|time|nohup|exec|then|else|do)[[:space:]])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git[[:space:]]+('"$git_opt_re"')*'"$subcommand"'([[:space:];|&()\{\}]|$)'
  echo "$stripped" | grep -qE "$guard_re"
}

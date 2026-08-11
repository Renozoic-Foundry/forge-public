#!/usr/bin/env bash
# FORGE shared git command-position detection helper (Spec 498, CTO R1; hardened Spec 632).
#
# Sourced by BOTH check-commit-guard.sh and check-push-guard.sh (and the validator git
# guard) — the command-position detection lives HERE, once, instead of being copy-pasted
# across two guards × two surfaces (the CI-445 four-copy drift class).
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
# lives here. (Because it is protected, this Spec 632 revision is applied by the OPERATOR
# in the terminal, not by an agent Edit — the guard denied the agent write, as designed.)

# forge_git_subcommand_at_command_position <subcommand> <command-string>
#   Returns 0 (true) iff <subcommand> (a literal git subcommand such as `commit` or
#   `push`) appears at SHELL COMMAND POSITION within <command-string>.
#
#   Preprocessing (Spec 632 hardening — a newline is a command SEPARATOR, not whitespace):
#     1. Strip heredoc bodies on the RAW input. From a `<<[-] [q]DELIM[q]` operator to the
#        closing DELIM line (inclusive), every body line is dropped BEFORE any matching, so
#        a docs/session/fixture heredoc that quotes a `git commit`/`git push` line in its
#        BODY cannot false-positive (Spec 632 R7 — the commit guard hard-DENIES, so a false
#        positive silently blocks a legitimate commit). Handles `<<EOF`, `<<-EOF` (indented
#        close), `<< EOF`, and quoted delimiters `<<'EOF'` / `<<"EOF"`.
#     2. Strip quoted substrings (both "…" and '…', single-level) so shell separators INSIDE
#        quoted args (echo "use ; git push") do not fake a command-position anchor.
#     3. Convert remaining newlines to `;` — a real command separator and a command-position
#        anchor. This closes the reproduced multi-line bypass: pre-632 this step was
#        `tr '\n' ' '` (newline->space), which put every command after the first OUT of
#        command position, so `cd /d/forge\ngit push` was ALLOWED while the single-line form
#        was gated. Heredoc-strip (step 1) replaces the false-positive protection that the
#        newline collapse used to provide.
#
#   Known limit (Spec 632 Verification Scope — the guard-input-fuzzing residual, criterion #9
#   in the release-acceptance gates): a `<<WORD` sequence appearing INSIDE a same-line quoted
#   string (e.g. `echo "x <<EOF"`) is treated as a heredoc start. This is a contrived shape,
#   never an accidental agent composition; 632 does not claim to close all novel input shapes.
#
#   Command-position anchors (the GUARD_RE leading group):
#     - start of a segment, or after a shell separator ; & | ( ) { } ` (newlines are `;` now)
#     - after a command-wrapping keyword: xargs sudo env time nohup exec then else do
#       (Spec 632 R2 adds) if elif while until command
#     - after a `!` pipeline negation, and after any chain of the above (if ! command git …)
#     - after one or more env-var assignments (GIT_AUTHOR_DATE=… git commit)
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
  local heredoc_stripped stripped normalized git_opt_re sep kw guard_re

  # (1) Heredoc-body strip on the RAW input (Spec 632 R7). No literal single-quote appears
  #     in this awk program — the delimiter quote class is built via sprintf("%c",39).
  heredoc_stripped=$(printf '%s\n' "$command" | awk '
    BEGIN { inh = 0; sq = sprintf("%c", 39); q = "[\"" sq "]" }
    {
      line = $0
      sub(/\r$/, "", line)
      if (inh) {
        t = line
        sub(/^[[:space:]]+/, "", t)
        if (line == delim || t == delim) inh = 0
        next
      }
      if (match(line, "<<-?[[:space:]]*" q "?[A-Za-z_][A-Za-z0-9_]*" q "?")) {
        d = substr(line, RSTART, RLENGTH)
        sub(/^<<-?[[:space:]]*/, "", d)
        gsub(q, "", d)
        delim = d
        inh = 1
      }
      print line
    }
  ')

  # (2) Strip quoted substrings (per line). Single-level "…"/'…' — nested/escaped quotes
  #     remain a known limit (Spec 632 Verification Scope residual; guard-input fuzzing).
  stripped=$(printf '%s\n' "$heredoc_stripped" | sed -E 's/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')

  # (3) Newlines become command separators (Spec 632 R1), not spaces.
  normalized=$(printf '%s' "$stripped" | tr '\n' ';')

  git_opt_re='(-[Cc][[:space:]]+[^-][^[:space:]]*[[:space:]]+|-[^[:space:]]*[[:space:]]+)'
  sep='[;|&()\{\}`]'
  # Command-wrapping keywords (Spec 632 R2 adds if|elif|while|until|command to the pre-632 set).
  kw='(xargs|sudo|env|time|nohup|exec|then|else|do|if|elif|while|until|command)'
  # Command-position prefix: after start OR a separator, any chain of env-assignments, wrapper
  # keywords, or `!` negation may precede `git` (interleaved, repeatable). The keyword is
  # anchored to command position (start/separator) — NOT a bare space — deliberately (Spec 632
  # DA finding): otherwise ordinary prose that merely names a wrapper (e.g. a single-line
  # comment `# use the command git commit`) false-matches, which for the hard-DENY commit
  # guard would silently block a legitimate commit. This also removes the pre-632 bare-space
  # false-positive class for the older keywords (then/do/exec/…).
  pfx='(('"$kw"'|!|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)[[:space:]]+)*'
  guard_re='(^|'"$sep"')[[:space:]]*'"$pfx"'git[[:space:]]+('"$git_opt_re"')*'"$subcommand"'([[:space:];|&()\{\}]|$)'
  printf '%s' "$normalized" | grep -qE "$guard_re"
}

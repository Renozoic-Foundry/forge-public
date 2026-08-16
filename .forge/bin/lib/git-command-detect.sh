#!/usr/bin/env bash
# FORGE shared git command-position detection helper (Spec 498, CTO R1; hardened Spec 632;
# quoted-token/ANSI-C hardening Spec 681).
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
# lives here. (Because it is protected, this Spec 632 revision — and this Spec 681
# revision — are applied by the OPERATOR in the terminal, not by an agent Edit — the
# guard denied the agent write, as designed. See docs/process-kit/guard-family-apply-note.md.)

# forge_git_subcommand_at_command_position <subcommand> <command-string>
#   Returns 0 (true) iff <subcommand> (a literal git subcommand such as `commit` or
#   `push`) appears at SHELL COMMAND POSITION within <command-string>.
#
#   Preprocessing (Spec 632 hardening — a newline is a command SEPARATOR, not whitespace;
#   Spec 681 adds quote normalization and ANSI-C decoding ahead of that separator step):
#     1. Strip heredoc bodies on the RAW input. From a `<<[-] [q]DELIM[q]` operator to the
#        closing DELIM line (inclusive), every body line is dropped BEFORE any matching, so
#        a docs/session/fixture heredoc that quotes a `git commit`/`git push` line in its
#        BODY cannot false-positive (Spec 632 R7 — the commit guard hard-DENIES, so a false
#        positive silently blocks a legitimate commit). Handles `<<EOF`, `<<-EOF` (indented
#        close), `<< EOF`, and quoted delimiters `<<'EOF'` / `<<"EOF"`.
#     2. Normalize quoting (Spec 681 — replaces the pre-681 wholesale quote strip, which
#        deleted a quoted command word along with its quotes and let an attacker who quotes
#        `"git" "push"` empty the matcher entirely). Scanned left to right, per line:
#          - A `$'...'` (ANSI-C quoted) span is decoded in place, character by character:
#            `\n`, `\r`, and `\t` become a literal space (the embedded separator this class
#            hides becomes ordinary command-position whitespace once decoded, closing
#            `$'git\npush'` without needing to widen the matcher itself); `\;` becomes a
#            literal `;` (an explicit escaped separator is treated as one); `\'` and `\\`
#            unescape normally so the scan finds the real closing quote; any other
#            backslash-escape just drops the backslash. Any UNESCAPED shell metacharacter
#            (`; | & ( ) { } ` `) occurring bare inside the span is neutralized to a space
#            rather than exposed as a real separator — this is what keeps an ordinary
#            ANSI-C-quoted commit message (which may legitimately contain a literal `;`)
#            from manufacturing a new command-position anchor after decode.
#          - A plain `"..."` or `'...'` span whose content is a bare word (letters, digits,
#            `_ . / -` only — no whitespace, no shell metacharacter) is reduced to that bare
#            word, quotes removed: `"git"` -> `git`, `'push'` -> `push`, `git 'push'` ->
#            `git push`. This is what lets a quoted command word reach command-position
#            matching instead of vanishing.
#          - Any other quoted span (contains whitespace or a metacharacter — genuine
#            argument data, e.g. a commit message) is dropped wholesale, exactly as before
#            Spec 681 — this is the false-positive protection the commit guard's hard-DENY
#            depends on, and it is deliberately unchanged for this class.
#     3. Convert remaining newlines to `;` — a real command separator and a command-position
#        anchor. This closes the reproduced multi-line bypass: pre-632 this step was
#        `tr '\n' ' '` (newline->space), which put every command after the first OUT of
#        command position, so `cd /d/forge\ngit push` was ALLOWED while the single-line form
#        was gated. Heredoc-strip (step 1) replaces the false-positive protection that the
#        newline collapse used to provide.
#
#   Known limit (Spec 632/681 Verification Scope — the guard-input-fuzzing residual):
#   nested/escaped quotes inside a quoted span, backslash-escaped bare words outside any
#   quote (`git\ push`), `$""` locale quoting, variable indirection (`c=push; git $c`), and
#   IFS manipulation are unexamined — a `<<WORD` sequence appearing INSIDE a same-line quoted
#   string (e.g. `echo "x <<EOF"`) is still treated as a heredoc start. These are contrived
#   shapes, never an accidental agent composition; this file hardens a class, it does not
#   claim the class is closed.
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

  # (2) Quote normalization (Spec 681 — replaces the pre-681 wholesale quote strip). Per
  #     line: decode `$'...'` ANSI-C escapes (neutralizing any bare metacharacter exposed by
  #     the decode), reduce a bare-word "…"/'…' span to the bare word, drop any other quoted
  #     span (whitespace/metacharacter content) same as before Spec 681. No literal
  #     single-quote appears in this awk program either, for the same reason as step 1's
  #     delimiter class — the quote char is built via sprintf("%c",39).
  stripped=$(printf '%s\n' "$heredoc_stripped" | awk '
    function normalize(line,    i, n, out, c, nc, buf, q) {
      n = length(line)
      out = ""
      i = 1
      while (i <= n) {
        c = substr(line, i, 1)
        if (c == "$" && substr(line, i + 1, 1) == sq) {
          i += 2
          buf = ""
          while (i <= n) {
            c = substr(line, i, 1)
            if (c == "\\" && i < n) {
              nc = substr(line, i + 1, 1)
              if (nc == "n" || nc == "r" || nc == "t") { buf = buf " " }
              else if (nc == ";") { buf = buf ";" }
              else { buf = buf nc }
              i += 2
              continue
            }
            if (c == sq) { i += 1; break }
            if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")" || c == "{" || c == "}" || c == "`") {
              buf = buf " "
              i += 1
              continue
            }
            buf = buf c
            i += 1
          }
          out = out buf
          continue
        }
        if (c == "\"" || c == sq) {
          q = c
          i += 1
          buf = ""
          while (i <= n) {
            c = substr(line, i, 1)
            if (c == q) { i += 1; break }
            buf = buf c
            i += 1
          }
          if (buf ~ /^[A-Za-z0-9_.\/-]+$/) out = out buf
          continue
        }
        out = out c
        i += 1
      }
      return out
    }
    BEGIN { sq = sprintf("%c", 39) }
    { print normalize($0) }
  ')

  # (3) Newlines become command separators (Spec 632 R1), not spaces. A `\n`/`\r` decoded out
  #     of a $'...' span in step 2 becomes a literal space there (not a newline), so it never
  #     reaches this conversion — see step 2's comment for why.
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

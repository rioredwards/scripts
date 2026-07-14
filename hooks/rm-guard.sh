#!/usr/bin/env bash
# rm-guard.sh — Rio prefers `trash` over `rm`. This is the deliberate exception to
# the global bypassPermissions mode: every `rm` invocation still forces a conscious
# confirmation, while leaving the agent free to proceed if rm really is the right call.
#
# Fires from a PreToolUse hook on the Bash tool. If the command invokes `rm` as a
# command, it emits a PreToolUse "ask" decision (stdout JSON, exit 0) so Claude Code
# surfaces an "are you sure?" prompt with Rio's preference. Non-rm commands pass
# through silently.
#
# Detection is intentionally biased to OVER-warn (an extra confirm is cheap; a
# silently-deleted file is not). It matches `rm` in command position and skips the
# common substring traps (alarm, charm, perm, npm, format, confirm, arm) and `rmdir`.
# It will also fire on `git rm`, `echo rm ...`, and rm inside quotes/comments — all
# acceptable: the reminder is the whole point.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$CMD" ] || exit 0

# `rm` in command position: preceded by start-of-line, whitespace, a shell operator,
# or a path slash (/bin/rm); followed by whitespace or end. `rmdir` is not matched
# (the char after "rm" would be 'd', not whitespace/end).
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:];&|(){}`/])rm([[:space:]]|$)'; then
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Rio prefers `trash` over `rm`. Are you sure you want to use `rm`? Use `trash <file>` unless rm is genuinely appropriate (CI cleanup, temp/build artifacts, or a path Trash can't handle)."
  }
}
JSON
fi

exit 0

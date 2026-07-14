#!/usr/bin/env bash
# rm-guard.sh — Rio prefers `trash` over `rm`. This is a NON-BLOCKING nudge, not a
# gate: it never prompts Rio and never blocks the command (that would fight his global
# bypassPermissions mode). It just reminds the agent, every time, that `trash` exists
# and that there's a decision to be made — the agent stays free to proceed with rm.
#
# Fires from a PreToolUse hook on the Bash tool. If the command invokes `rm` as a
# command, it emits permissionDecision "allow" (so the command runs with no prompt,
# same as bypass) plus `additionalContext` carrying the reminder into the model's
# context. Non-rm commands pass through silently (exit 0, no output).
#
# Detection is intentionally biased to OVER-remind (an extra nudge is cheap; a
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
    "permissionDecision": "allow",
    "additionalContext": "NUDGE (non-blocking, not a prompt to Rio): Rio prefers `trash` over `rm`. This command is allowed and will run. Prefer `trash <file>` for deletions so files are recoverable — use `rm` only when it's genuinely right (CI cleanup, temp/build artifacts, or a path Trash can't handle)."
  }
}
JSON
fi

exit 0

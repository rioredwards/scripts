#!/usr/bin/env bash
# task-start.sh: UserPromptSubmit. Rio's task-start rules, delivered when a task starts
# instead of from the global file, where they fade (L-0213). The agent judges whether the
# prompt starts a task or asks about past sessions' work (mid-conversation too, L-0008). Delegates get their task from an agent: no output.
#
# Fails open: no jq → exit 0 with no output.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
. "$HOME/scripts/hooks/lib/delegate.sh"

INPUT="$(cat)"
hook_is_delegate "$INPUT" && exit 0
# Background events (task notifications, reminders) arrive as prompts too; they start nothing.
case "$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)" in '<task-notification'*|'<system-reminder'*) exit 0 ;; esac

# Detached HEAD: work built here lands on no branch (I-167). One loud line, once per session;
# silent on a branch, outside a git repo, or after the first warning.
WARN=""
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)"
if [ -n "$CWD" ] && [ -d "$CWD" ] && git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1 \
  && ! git -C "$CWD" symbolic-ref -q HEAD >/dev/null 2>&1; then
  M="${TMPDIR:-/tmp}/detached-head-warned-${SID:-nosession}"
  if [ ! -e "$M" ]; then
    : >"$M"
    WARN="WARNING: this session is on a DETACHED HEAD (no branch) at $(git -C "$CWD" rev-parse --short HEAD 2>/dev/null). Tell Rio in your first reply, and do not build or commit work on it until he picks a base branch. "
  fi
fi

jq -nc --arg c "${WARN}If this message starts a task, or asks about work in other sessions (what was asked, decided, done, or why; follow-ups too): load the \`utils:sesh\` skill before other work or answering, using its \`--topic <task>\` mode for a task, and read at its depth, since how it was last done beats docs, defaults, and guesses. Not for replies or questions about this session alone. \`utils:sesh\` is a skill name, not a shell command; its CLI is \`session-handoff\`. Non-trivial task: suggest \`/core:loop\` first." \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'

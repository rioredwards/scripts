#!/usr/bin/env bash
# task-start.sh: UserPromptSubmit. Rio's task-start rules, delivered when a task starts
# instead of from the global file, where they fade (L-0213). The agent judges whether the
# prompt starts a task. Delegates get their task from an agent: no output.
#
# Fails open: no jq → exit 0 with no output.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
. "$HOME/scripts/hooks/lib/delegate.sh"

INPUT="$(cat)"
hook_is_delegate "$INPUT" && exit 0
# Background events (task notifications, reminders) arrive as prompts too; they start nothing.
case "$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)" in '<task-notification'*|'<system-reminder'*) exit 0 ;; esac

jq -nc --arg c "If this message starts a task (not a reply or a pure question about this session): load the \`utils:sesh\` skill and use its \`--topic <task>\` mode before other work; follow the skill's reading depth, since how it was last done beats docs, defaults, and guesses. \`utils:sesh\` is a skill name, not a shell command; its CLI is \`session-handoff\`. Non-trivial task: suggest \`/core:loop\` first." \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'

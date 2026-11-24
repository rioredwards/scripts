#!/usr/bin/env bash
# session-task.sh: UserPromptSubmit (Claude and Codex). Until the session has an Asana task tag (or `none`), every
# prompt hands the agent Rio's open tasks and the command to record one (issue #67). Usage: session-task.sh [claude|codex].
# Logic: ~/dev/project-manager/scripts/session_task.py.
set -uo pipefail
. "$HOME/scripts/hooks/lib/delegate.sh"

INPUT="$(cat)"
hook_is_delegate "$INPUT" && exit 0
printf '%s' "$INPUT" | python3 "$HOME/dev/project-manager/scripts/session_task.py" hook "${1:-claude}"

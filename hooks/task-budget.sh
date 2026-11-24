#!/usr/bin/env bash
# task-budget.sh: UserPromptSubmit. Scope guard (L-0053, tracer on the Railway task): a session whose first prompt
# matches a budgeted Asana task opens with its budget line (spent vs budget, due, done-when); at overrun the agent
# stops and asks Rio to extend, naming what waits. Logic: ~/dev/project-manager/scripts/pm_budget.py.
set -uo pipefail
. "$HOME/scripts/hooks/lib/delegate.sh"

INPUT="$(cat)"
hook_is_delegate "$INPUT" && exit 0
printf '%s' "$INPUT" | python3 "$HOME/dev/project-manager/scripts/pm_budget.py" hook

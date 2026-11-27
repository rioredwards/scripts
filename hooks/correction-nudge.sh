#!/usr/bin/env bash
# correction-nudge.sh: UserPromptSubmit, Claude and Codex. When Rio's prompt matches one of his saved
# past corrections (grumbo's case bank, agent-skills grumbo ref/cases.md), shows that correction in
# his words. Matching, limits and the shown log live in `grumbo-cases nudge`, so the noise measured
# by `grumbo-cases measure` is what this hook does. Delegates get their task from an agent: no output.
#
# Advisory: no jq, no python3 or no bank → exit 0 with no output. A missing grumbo-cases script is
# an infrastructure error and fails loud.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
. "$HOME/scripts/hooks/lib/delegate.sh"

CASES="${GRUMBO_CASES_SCRIPT:-$HOME/dev/agent-skills/plugins/utils/skills/grumbo/scripts/grumbo-cases}"
if [ ! -x "$CASES" ]; then
  echo "correction-nudge: $CASES is missing or not executable" >&2
  exit 1
fi

INPUT="$(cat)"
hook_is_delegate "$INPUT" && exit 0
printf '%s' "$INPUT" | "$CASES" nudge

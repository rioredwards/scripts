#!/usr/bin/env bash
# loc-budget.sh — enforce the LOC appetite set by `agent-budget`.
#
# Two events, one question: is the diff over the budget the plan set?
#   pre   (PreToolUse, Bash)  git commit/push while over → DENIED. Checkpoint
#                             with Rio first; `RIO_BUDGET_OK=1 git commit …`
#                             is the escape hatch once he has said yes.
#   post  (PostToolUse, edits) first edit that lands over → one nudge into
#                             context, then silence until the budget is reset.
#
# No budget set → silent. Not a repo → silent. jq missing → silent.
#   AGENT_LOC_BUDGET=off   disable
set -uo pipefail

MODE="${1:-}"
[ -f "$HOME/scripts/agent-hooks-env.sh" ] && . "$HOME/scripts/agent-hooks-env.sh"
[ "${AGENT_LOC_BUDGET:-on}" = "off" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
TOOL="$(jq -r '.tool_name // empty' <<<"$INPUT")"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT")"
CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT")"
# `cd <repo> && git commit …` runs in that repo, not the session cwd.
LEAD="$(sed -nE 's/^[[:space:]]*cd[[:space:]]+("([^"]+)"|'"'"'([^'"'"']+)'"'"'|([^[:space:];&|]+))[[:space:]]*(&&|;).*/\2\3\4/p' <<<"$CMD")"
[ -n "$LEAD" ] && CWD="${LEAD/#\~/$HOME}"
[ -n "$CWD" ] && cd "$CWD" 2>/dev/null || exit 0

GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
[ -r "$GIT_DIR/agent-budget" ] || exit 0

case "$MODE" in
  pre)
    [ "$TOOL" = "Bash" ] || exit 0
    grep -Eq '(^|[;&|(] *)git([[:space:]]+-[^[:space:]]+)*[[:space:]]+(commit|push)([[:space:]]|$)' <<<"$CMD" || exit 0
    grep -q 'RIO_BUDGET_OK=1' <<<"$CMD" && exit 0
    STATUS="$("$HOME/scripts/agent-budget" status 2>&1)"; RC=$?
    [ "$RC" -eq 1 ] || exit 0
    jq -n --arg r "BLOCKED: $STATUS. The plan's appetite is spent — this is the signal that the change grew past what was approved. Do not trim cosmetically to squeak under. Stop and checkpoint with Rio: what grew, why, and whether to raise the budget, split the work, or cut scope. If he raises it, run \`agent-budget set <loc>\` (base stays). Only if he explicitly says commit anyway, re-run prefixed with \`RIO_BUDGET_OK=1 \`." \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    ;;
  post)
    case "$TOOL" in Edit|Write|NotebookEdit|Bash) ;; *) exit 0 ;; esac
    # Delegates never get the checkpoint-with-Rio nudge — and must not consume
    # the once-per-budget warned marker the main agent relies on. The commit
    # gate in `pre` still binds everyone.
    . "$HOME/scripts/hooks/lib/delegate.sh"
    hook_is_delegate "$INPUT" && exit 0
    [ -e "$GIT_DIR/agent-budget-warned" ] && exit 0
    STATUS="$("$HOME/scripts/agent-budget" status 2>&1)"; RC=$?
    [ "$RC" -eq 1 ] || exit 0
    touch "$GIT_DIR/agent-budget-warned"
    jq -n --arg c "NUDGE (Rio was not asked): $STATUS. The diff just crossed the plan's LOC appetite. Commits are now gated. Before writing more, ask: is existing code being reinvented, is the solution disproportionate, or did the plan underestimate? Checkpoint with Rio in your next reply — one line on what grew and a recommendation." \
      '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
    ;;
esac
exit 0

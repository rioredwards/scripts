#!/usr/bin/env bash
# issue-skill-guard.sh: deterministic enforcement for the /core:issue skill.
#
# PreToolUse for shell and GitHub connector issue writes. Requires the skill
# marker, then validates priority provenance against current GitHub state:
#   /tmp/claude-issue-skill-<session_id>
#
# Read-only issue commands pass through untouched. Python starts only on writes.
# Fails open if jq is missing or input is malformed.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.cmd // empty' 2>/dev/null)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$SID" ] || exit 0

# Cheap prefilter, then the real check: an actual invocation, not a quoted mention.
MODE=issue
if [ -n "$CMD" ]; then
  case "$CMD" in
    'gh issue create --help'|'gh issue create -h'|'gh issue new --help'|'gh issue new -h'|'gh issue edit --help'|'gh issue edit -h') exit 0 ;;
  esac
  printf '%s' "$CMD" | grep -Eq 'gh[[:space:]]+(issue[[:space:]]+(create|new|edit)|api)' || exit 0
  printf '%s' "$CMD" | "$(dirname "$0")/lib/cmd-invokes" 'gh\s+issue\s+(create|new|edit)'
  invoked=$?
  if printf '%s' "$CMD" | "$(dirname "$0")/lib/cmd-invokes" 'gh\s+api'; then
    if printf '%s' "$CMD" | grep -Eq '(repos/[^[:space:]]+/issues(/[[:digit:]]+)?(/labels[^[:space:]]*)?([^/[:alnum:]_]|$)|createIssue|updateIssue|addLabelsToLabelable|removeLabelsFromLabelable)' &&
       printf '%s' "$CMD" | grep -Eq '(-[fF]|--(raw-)?field|--input|(-X|--method)[=[:space:]]*(POST|PATCH|PUT|DELETE))'; then
      MODE=api
    fi
  fi
  [ "$invoked" -eq 1 ] && [ "$MODE" != api ] && exit 0
else
  case "$TOOL" in
    *github*create_issue|*github*update_issue|*github*add_issue_labels|*github*remove_issue_label) ;;
    *) exit 0 ;;
  esac
fi

MARKER="/tmp/claude-issue-skill-${SID}"
[ -f "$MARKER" ] && {
  OUTPUT="$(printf '%s' "$INPUT" | python3 "$(dirname "$0")/lib/issue-priority.py" "$MODE")"
  if [ $? -eq 0 ]; then
    printf '%s' "$OUTPUT"
  else
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Issue priority validation failed. Fix issue-skill-guard before retrying this write."}}'
  fi
  exit 0
}

jq -n --arg marker "$MARKER" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("BLOCKED by issue-skill-guard: issue writes require core:issue this session. Load it, run: touch " + $marker + ", then retry. This is an automated gate, not a user denial.")
  }
}'
exit 0

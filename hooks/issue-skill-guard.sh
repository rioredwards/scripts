#!/usr/bin/env bash
# issue-skill-guard.sh — deterministic enforcement for the /core:issue skill.
#
# Fires from a PreToolUse hook on the Bash tool. If the command contains
# `gh issue create` or `gh issue edit`, the call is DENIED unless this session
# has confirmed the skill is loaded by touching a marker file:
#   /tmp/claude-issue-skill-<session_id>
#
# The deny reason tells the agent exactly how to unlock (load skill, touch
# marker, retry), so the worst case is one bounced tool call per session.
# Read-only issue commands (view/list/comment/close) pass through untouched.
# Fails open if jq is missing or input is malformed.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$CMD" ] && [ -n "$SID" ] || exit 0

printf '%s' "$CMD" | grep -Eq 'gh[[:space:]]+issue[[:space:]]+(create|edit)' || exit 0

MARKER="/tmp/claude-issue-skill-${SID}"
[ -f "$MARKER" ] && exit 0

jq -n --arg marker "$MARKER" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("BLOCKED by issue-skill-guard: `gh issue create`/`gh issue edit` requires the /core:issue skill this session. 1) Invoke the Skill tool with \"core:issue\" (skip if already loaded). 2) Run: touch " + $marker + "  3) Retry this command. This is an automated gate, not a user denial.")
  }
}'
exit 0

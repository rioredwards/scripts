#!/usr/bin/env bash
# loop-phase-tracker.sh — POC: track which core:loop phase is active for the statusline.
#
# Fires from a PreToolUse hook matched on the Skill tool. When the skill invoked is one
# of the core:loop phase skills, writes the bare phase name to a session-scoped marker
# file the statusline script reads:
#   /tmp/claude-loop-phase-<session_id>
#
# Never blocks the tool call — always exits 0. Fails open if jq is missing or input is
# malformed (same posture as issue-skill-guard.sh).
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
SKILL="$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$SKILL" ] && [ -n "$SID" ] || exit 0

case "$SKILL" in
  core:loop|core:git-cleanup|core:run-dev|core:explore|core:plan|core:implement|core:review|core:validate|core:ship|core:complete|core:retro)
    printf '%s' "${SKILL#core:}" > "/tmp/claude-loop-phase-${SID}"
    ;;
esac

exit 0

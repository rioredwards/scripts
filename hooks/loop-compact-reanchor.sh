#!/usr/bin/env bash
# loop-compact-reanchor.sh — restore core:loop state right after context compaction.
#
# SessionStart (matcher: compact). Compaction summaries preserve the task but drop the
# loop protocol, so agents stop invoking phase skills mid-loop. If this session has a
# loop-phase marker (/tmp/claude-loop-phase-<session_id>, written by
# loop-phase-tracker.sh), print the loop state to stdout — SessionStart stdout is added
# to context visible to the model.
#
# Fails open: no jq, no marker, malformed input → exit 0 with no output.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$SID" ] || exit 0

MARKER="/tmp/claude-loop-phase-${SID}"
[ -r "$MARKER" ] || exit 0
PHASE="$(cat "$MARKER" 2>/dev/null)"
[ -n "$PHASE" ] || exit 0

case "$PHASE" in
  complete|retro) exit 0 ;;
esac

# Declared composition (phases + routes) from $GIT_DIR/claude-loop-plan, if the loop wrote one.
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
COMP=""
if [ -n "$CWD" ]; then
  GD="$(git -C "$CWD" rev-parse --absolute-git-dir 2>/dev/null)" || GD=""
  [ -n "$GD" ] && [ -r "$GD/claude-loop-plan" ] && COMP="$(head -c 400 "$GD/claude-loop-plan" 2>/dev/null)"
fi

cat <<EOF
🚨 Context was just compacted mid-core:loop. Last phase skill loaded: ${PHASE}.${COMP:+ Declared composition: ${COMP} — hold the declared depth; re-route only with a stated reason.}
The loop protocol likely got lost in the summary — re-anchor before continuing:
1. Re-invoke core:loop (Skill tool) to reload the orchestration rules.
2. Every phase transition begins by invoking that phase's skill (core:<phase>) — never do phase work or spawn phase agents without it.
3. Re-read the issue (plan of record) per the loop's re-entry steps.
EOF
exit 0

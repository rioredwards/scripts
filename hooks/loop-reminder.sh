#!/usr/bin/env bash
# loop-reminder.sh — re-anchor the core:loop protocol while a loop is active.
#
# PostToolUse (all tools). If this session has a loop-phase marker
# (/tmp/claude-loop-phase-<session_id>, written by loop-phase-tracker.sh), inject a
# one-line additionalContext reminder to enter phases via their skills. Throttled to
# once per LOOP_REMINDER_INTERVAL_SECS (default 300) so it survives context bloat and
# compaction without spamming.
#
# Never blocks the tool call — always exits 0. Fails open if jq is missing or input is
# malformed (same posture as loop-phase-tracker.sh).
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$SID" ] || exit 0
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"

MARKER="/tmp/claude-loop-phase-${SID}"
[ -r "$MARKER" ] || exit 0
PHASE="$(cat "$MARKER" 2>/dev/null)"
[ -n "$PHASE" ] || exit 0

# Loop finished — stop reminding.
case "$PHASE" in
  complete|retro) exit 0 ;;
esac

INTERVAL="${LOOP_REMINDER_INTERVAL_SECS:-300}"
STAMP="/tmp/claude-loop-remind-${SID}"
now="$(date +%s)"
if [ -r "$STAMP" ]; then
  last="$(cat "$STAMP" 2>/dev/null)"
  case "$last" in *[!0-9]*|"") last=0 ;; esac
  [ $((now - last)) -lt "$INTERVAL" ] && exit 0
fi
printf '%s' "$now" > "$STAMP"

# Declared composition (phases + routes), written by the loop at contract time to
# $GIT_DIR/claude-loop-plan. When present, echo it back — the evidenced drift is toward
# MORE ceremony than agreed, not phase-skipping (L-0060).
COMP=""
if [ -n "$CWD" ]; then
  GD="$(git -C "$CWD" rev-parse --absolute-git-dir 2>/dev/null)" || GD=""
  [ -n "$GD" ] && [ -r "$GD/claude-loop-plan" ] && COMP="$(head -c 400 "$GD/claude-loop-plan" 2>/dev/null)"
fi
COMP_LINE=""
[ -n "$COMP" ] && COMP_LINE=" Declared composition: ${COMP} — hold the declared depth (no extra ceremony, no skipped floors); re-route only with a stated reason, announced and recorded."

jq -n --arg ctx "📌 core:loop active — last phase skill loaded: ${PHASE}.${COMP_LINE} Protocol: every phase transition begins by invoking that phase's skill (Skill tool, core:<phase>) before any phase work or delegation. If you have moved past '${PHASE}' without doing so, invoke the current phase's skill now. If context was compacted, re-invoke core:loop first." \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
exit 0

#!/usr/bin/env bash
# compact-reanchor.sh: re-add what compaction drops, right after it happens.
#
# SessionStart (matcher: compact). Compaction only happens deep into long work, so it is
# the trigger for Rio's scope checkpoint (agents can't sense elapsed time). Mid-core:loop
# (marker /tmp/claude-loop-phase-<session_id>, written by loop-phase-tracker.sh), it also
# restores the loop protocol the summary drops. SessionStart stdout is added to context.
# Delegates report to an agent, not Rio: no output.
#
# Fails open: no jq or malformed input → exit 0 with no output.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
. "$HOME/scripts/hooks/lib/delegate.sh"

INPUT="$(cat)"
hook_is_delegate "$INPUT" && exit 0
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$SID" ] || exit 0

cat <<'EOF'
📌 Context was just compacted, so this is long-running work. Rio's rule: big work needs his yes on
scope, size, and end point. If he hasn't okayed the current scope, or it grew past what he
approved, checkpoint with Rio now: what's done, what's left, how much more.
Under `attention: away` nobody answers: write the inbox `- ask:` line and stop at the approved scope.
EOF

MARKER="/tmp/claude-loop-phase-${SID}"
[ -r "$MARKER" ] || exit 0
PHASE="$(cat "$MARKER" 2>/dev/null)"
case "$PHASE" in
  ''|complete|retro) exit 0 ;;
esac

# Declared composition (phases + routes) from $GIT_DIR/claude-loop-plan, if the loop wrote one.
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
COMP=""
if [ -n "$CWD" ]; then
  GD="$(git -C "$CWD" rev-parse --absolute-git-dir 2>/dev/null)" || GD=""
  [ -n "$GD" ] && [ -r "$GD/claude-loop-plan" ] && COMP="$(head -c 400 "$GD/claude-loop-plan" 2>/dev/null)"
fi

cat <<EOF
🚨 Context was just compacted mid-core:loop. Last phase skill loaded: ${PHASE}.${COMP:+ Declared composition: ${COMP}. Hold the declared depth; re-route only with a stated reason.}
The loop protocol likely got lost in the summary, re-anchor before continuing:
1. Reload core:loop (Claude: Skill tool; Codex: read SKILL.md).
2. Load each phase's skill before phase work or delegation.
3. Re-read the issue (plan of record) per the loop's re-entry steps.
EOF
exit 0

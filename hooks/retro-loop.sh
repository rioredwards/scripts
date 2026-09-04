#!/usr/bin/env bash
# retro-loop.sh — occasional meta/system check-in for agent sessions.
#
# PostToolUse (all tools). Every Nth tool call IN THIS REPO it injects a
# non-blocking additionalContext note asking the agent: is Rio's system (skills,
# CLIs, hooks) working smoothly? The agent acknowledges, leaves a `[retro-loop]:`
# note in the transcript (recommendations, or "system is working well, no
# feedback"), and carries on — it must never stop its work.
#
# WHY THE COUNTER IS PER-REPO ($GIT_DIR/retro-loop-count), NOT PER-SESSION:
# epics are rolling streams spanning sessions and providers that never reach a
# terminal `complete`, so a session counter would never accumulate and the retro
# would never fire. Tool calls against the repo are the one clock that keeps
# ticking. Non-git cwd → skip. Counter resets on fire.
#
# Harvest path: `utils:system` triage sweeps transcripts for `[retro-loop]:` via
# sesh and feeds findings into ledger triage.
#
# Settings follow the agent-hooks convention (profile in
# ~/.dotfiles/zsh/profiles/agent-hooks.sh via agent-hooks-env.sh; env wins):
#
#   AGENT_RETRO_LOOP        on | off   (default on)
#   AGENT_RETRO_LOOP_EVERY  fire every Nth tool call per repo (default 500)
#
# Fails open: no jq, no git repo, unreadable/corrupt counter → exit 0, silent.
set -uo pipefail

[ -f "$HOME/scripts/agent-hooks-env.sh" ] && . "$HOME/scripts/agent-hooks-env.sh"

[ "${AGENT_RETRO_LOOP:-on}" = "on" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$CWD" ] || exit 0

GD="$(git -C "$CWD" rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
[ -n "$GD" ] && [ -d "$GD" ] || exit 0

EVERY="${AGENT_RETRO_LOOP_EVERY:-500}"
case "$EVERY" in *[!0-9]*|"") EVERY=500 ;; esac
[ "$EVERY" -gt 0 ] || exit 0

COUNT_FILE="$GD/retro-loop-count"
COUNT="$(cat "$COUNT_FILE" 2>/dev/null || echo 0)"
case "$COUNT" in *[!0-9]*|"") COUNT=0 ;; esac
COUNT=$((COUNT + 1))

if [ "$COUNT" -lt "$EVERY" ]; then
  printf '%s' "$COUNT" > "$COUNT_FILE" 2>/dev/null || true
  exit 0
fi

# Fire: reset the clock, inject the check-in (additionalContext — never blocks).
printf '0' > "$COUNT_FILE" 2>/dev/null || true

jq -n --arg ctx "🔄 [retro-loop] Occasional meta check-in (every ${EVERY} tool calls in this repo — not about your current task). Is Rio's system working smoothly: skills, CLIs, hooks, docs? Any friction, failures, or workarounds you hit using them? Do NOT stop your work — acknowledge in your next reply with a one-line transcript note: '[retro-loop]: <recommendations>' or '[retro-loop]: system is working well, no feedback'. Then continue exactly where you were." \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
exit 0

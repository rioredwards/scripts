#!/usr/bin/env bash
# Dynamic agent context — emitted at SessionStart for Claude Code and Codex.
#
# Prints a single JSON object on stdout:
#   {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}
#
# Two sources of context:
#   1. Derived — facts the shell can see right now (machine, SSH).
#   2. Declared — ~/scripts/agent-context/state.json, written by anything
#      (Apple Shortcuts, a CLI, an automation). Every key/value is emitted as-is.
#      Extension point: add a key there, no change needed here.

set -euo pipefail

STATE_FILE="${AGENT_CONTEXT_STATE:-$HOME/scripts/agent-context/state.json}"

# --- 1. derived: which Mac, and is Rio driving it directly? ---------------
host_id=$(scutil --get LocalHostName | tr '[:upper:]' '[:lower:]')
case "$host_id" in
  *mac-mini*) machine="Mac Mini" ;;
  *macbook*)  machine="MacBook Air" ;;
  *) echo "agent-context: unrecognized LocalHostName '$host_id'" >&2; exit 1 ;;
esac

if [ -n "${SSH_CONNECTION:-}" ]; then
  seat="SSH session from ${SSH_CONNECTION%% *}. Rio is NOT sitting at this Mac — \
GUI side effects (open, screenshots, notifications, Reminders, Shortcuts) land \
on $machine's screen, which he cannot see. Route anything visual to his machine."
else
  seat="Local session. Rio is sitting at this Mac — GUI side effects land on his screen."
fi

facts="Machine: $machine
Seat: $seat"

# --- 2. declared: whatever wrote state.json ------------------------------
if [ -f "$STATE_FILE" ]; then
  facts+=$'\n'$(jq -r 'to_entries[] | "\(.key): \(.value)"' "$STATE_FILE")
fi

jq -nc --arg c "$facts" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'

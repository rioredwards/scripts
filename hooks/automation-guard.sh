#!/usr/bin/env bash
# automation-guard.sh: put the fullscreen "hands off" cue up whenever an agent
# drives the GUI, and take it down when the agent is done.
#
# Rio can't tell, from across the room or from his phone, whether the mouse
# moving and windows opening is him or an agent. `~/scripts/automation-cue.sh`
# already draws that cue (Hammerspoon overlay), but until now every caller had
# to remember to wrap itself. This hook covers shell and native computer-control
# calls automatically.
#
# NON-BLOCKING by design: it never prompts and never denies (that would fight
# Rio's global bypassPermissions mode). It only makes GUI automation *visible*.
#
# Wiring: same script on four events, dispatching on hook_event_name:
#   PreToolUse  (matcher *) → cue up   if the command drives the GUI
#   PostToolUse (matcher *) → cue down when the last such command finishes
#   Stop / SessionEnd          → cue down unconditionally (crash safety net)
#
# In-flight tracking: parallel tool calls mean pre/post can interleave, so each
# matched call drops a marker file (tool-use ID, or command hash without an ID).
# The cue only
# comes down when the marker dir is empty. Markers older than the stale window
# are swept on every event. The cue also expires without another hook event.
#
# Settings follow the agent-hooks convention (profile vars in
# ~/.dotfiles/zsh/profiles/agent-hooks.sh, env wins over profile):
#
#   AGENT_AUTOMATION_CUE        on | off   (default on)
#   AGENT_AUTOMATION_CUE_STALE  minutes before an in-flight marker is swept
#                               (default 5)
#
# Disable for one run:  AGENT_AUTOMATION_CUE=off claude ...

set -uo pipefail

[ -f "$HOME/scripts/agent-hooks-env.sh" ] && . "$HOME/scripts/agent-hooks-env.sh"

[ "${AGENT_AUTOMATION_CUE:-on}" = "on" ] || exit 0

cue="$HOME/scripts/automation-cue.sh"
[ -x "$cue" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

inflight="$HOME/.cache/automation-guard/inflight"
stale_min="${AGENT_AUTOMATION_CUE_STALE:-5}"

INPUT="$(cat)"
EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.cmd // empty' 2>/dev/null)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
CALL_ID="$(printf '%s' "$INPUT" | jq -r '.tool_use_id // .tool_call_id // empty' 2>/dev/null)"

# A stranded overlay is worse than a missing one, so sweep on every event.
mkdir -p "$inflight"
expired="$(find "$inflight" -type f -mmin "+$stale_min" -print -delete 2>/dev/null)"
if [ -n "$expired" ] && [ -z "$(ls -A "$inflight" 2>/dev/null)" ]; then
  "$cue" stop >/dev/null 2>&1
fi

cue_down() {
  rm -f "$inflight"/* 2>/dev/null
  "$cue" stop >/dev/null 2>&1
  exit 0
}

case "$EVENT" in
  Stop | SessionEnd | SubagentStop) cue_down ;;
esac

# Does this command move the pointer, press keys, read the screen, or bring an
# app forward? Biased to over-match: a spurious overlay flash is cheap, an
# invisible agent taking over the screen is not. The cue script itself and
# anything that already wraps its own cue must not match.
drives_gui() {
  case "$1" in
    *automation-cue*) return 1 ;;
  esac

  invokes="$(dirname "$0")/lib/cmd-invokes"
  printf '%s' "$1" | "$invokes" \
    '(click-tool|cliclick|screencapture|ax-dialog|tbshot|sc)' && return 0

  # Shortcuts run headless-ish but can raise UI.
  printf '%s' "$1" | "$invokes" 'shortcuts\s+run' && return 0

  # Opening a file, app or deeplink can front another app. Arguments named
  # "open" are inert; the shared parser checks command position.
  printf '%s' "$1" | "$invokes" 'open' &&
    return 0

  # AppleScript that types, clicks, fronts an app, or throws up a dialog.
  # `display notification` is deliberately excluded: it steals nothing.
  printf '%s' "$1" | "$invokes" 'osascript' &&
    printf '%s' "$1" | grep -Eq 'System Events|keystroke|key code|display dialog|to activate|click at|perform action' && return 0

  return 1
}

# Native CUA input is JavaScript, not a shell command. Classify by the tool
# name so every native call raises the cue before the tool executes.
case "$TOOL" in
  mcp__cua_repl.js | mcp__cua_repl__js)
    CMD="$(printf '%s' "$INPUT" | jq -c '.tool_input // {}')"
    ;;
  *) [ -n "$CMD" ] && drives_gui "$CMD" || exit 0 ;;
esac

# IDs distinguish overlapping identical calls. Older hook payloads without an
# ID retain the command-based key used by the original guard.
key="${CALL_ID:+call:$CALL_ID}"
[ -n "$key" ] || key="command:$CMD"
marker="$inflight/$(printf '%s' "$key" | md5 -q 2>/dev/null || printf '%s' "$key" | md5sum | cut -d' ' -f1)"

case "$EVENT" in
  PreToolUse)
    : >"$marker"
    "$cue" start "$((stale_min * 60))" >/dev/null 2>&1
    ;;
  PostToolUse)
    rm -f "$marker" 2>/dev/null
    # Another GUI command may still be running in a parallel tool call.
    [ -z "$(ls -A "$inflight" 2>/dev/null)" ] && "$cue" stop >/dev/null 2>&1
    ;;
esac

exit 0

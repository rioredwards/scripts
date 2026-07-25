#!/usr/bin/env bash
# automation-guard.sh — put the fullscreen "hands off" cue up whenever an agent
# drives the GUI, and take it down when the agent is done.
#
# Rio can't tell, from across the room or from his phone, whether the mouse
# moving and windows opening is him or an agent. `~/scripts/automation-cue.sh`
# already draws that cue (Hammerspoon overlay), but until now every caller had
# to remember to wrap itself. This hook makes it automatic for agent Bash calls.
#
# NON-BLOCKING by design: it never prompts and never denies (that would fight
# Rio's global bypassPermissions mode). It only makes GUI automation *visible*.
#
# Wiring — same script on four events, dispatching on hook_event_name:
#   PreToolUse  (matcher Bash) → cue up   if the command drives the GUI
#   PostToolUse (matcher Bash) → cue down when the last such command finishes
#   Stop / SessionEnd          → cue down unconditionally (crash safety net)
#
# In-flight tracking: parallel Bash calls mean pre/post can interleave, so each
# matched command drops a marker file (hash of the command) and the cue only
# comes down when the marker dir is empty. Markers older than the stale window
# are swept on every event, so a killed agent can't strand the overlay.
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
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"

# A stranded overlay is worse than a missing one, so sweep on every event.
mkdir -p "$inflight"
find "$inflight" -type f -mmin "+$stale_min" -delete 2>/dev/null

cue_down() {
  rm -f "$inflight"/* 2>/dev/null
  "$cue" stop >/dev/null 2>&1
  exit 0
}

case "$EVENT" in
  Stop | SessionEnd | SubagentStop) cue_down ;;
esac

[ -n "$CMD" ] || exit 0

# Does this command move the pointer, press keys, read the screen, or bring an
# app forward? Biased to over-match: a spurious overlay flash is cheap, an
# invisible agent taking over the screen is not. The cue script itself and
# anything that already wraps its own cue must not match.
drives_gui() {
  case "$1" in
    *automation-cue*) return 1 ;;
  esac

  # Quoted text is data, not a command — `git commit -m 'fix screencapture'`
  # must not raise the overlay. Tool names are matched against the stripped
  # form; the argument patterns below need the original, since a deeplink or
  # app path is usually quoted.
  bare="$(printf '%s' "$1" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')"

  # Command-position match on the GUI tools Rio has on PATH.
  printf '%s' "$bare" | grep -Eq \
    '(^|[[:space:];&|(){}`/])(click-tool|cliclick|screencapture|ax-dialog|tbshot|sc)([[:space:]]|$)' && return 0

  # Shortcuts run headless-ish but can raise UI.
  printf '%s' "$bare" | grep -Eq '(^|[[:space:];&|(){}`])shortcuts[[:space:]]+run([[:space:]]|$)' && return 0

  # `open` that launches or fronts an app, or fires a deeplink. Plain
  # `open somefile.txt` is left alone — too common, rarely a takeover.
  printf '%s' "$bare" | grep -Eq '(^|[[:space:];&|(){}`/])open([[:space:]]|$)' &&
    printf '%s' "$1" | grep -Eq '(^|[[:space:];&|(){}`/])open[[:space:]]+.*(-[aRn][[:space:]]|[a-z][a-z0-9+.-]*://|\.app)' && return 0

  # AppleScript that types, clicks, fronts an app, or throws up a dialog.
  # `display notification` is deliberately excluded — it steals nothing.
  printf '%s' "$bare" | grep -Eq 'osascript' &&
    printf '%s' "$1" | grep -Eq 'System Events|keystroke|key code|display dialog|to activate|click at|perform action' && return 0

  return 1
}

drives_gui "$CMD" || exit 0

marker="$inflight/$(printf '%s' "$CMD" | md5 -q 2>/dev/null || printf '%s' "$CMD" | md5sum | cut -d' ' -f1)"

case "$EVENT" in
  PreToolUse)
    : >"$marker"
    "$cue" start >/dev/null 2>&1
    ;;
  PostToolUse)
    rm -f "$marker" 2>/dev/null
    # Another GUI command may still be running in a parallel tool call.
    [ -z "$(ls -A "$inflight" 2>/dev/null)" ] && "$cue" stop >/dev/null 2>&1
    ;;
esac

exit 0

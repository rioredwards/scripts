#!/usr/bin/env bash
# Show/hide a fullscreen automation cue via Hammerspoon.
# Usage: automation-cue.sh start [timeout-seconds] | stop

set -euo pipefail

cmd="${1:-}"
ttl="${2:-300}"
case "$ttl" in
  ''|*[!0-9]*|0) echo "Timeout must be a positive number of seconds" >&2; exit 1 ;;
esac

if ! pgrep -x Hammerspoon >/dev/null 2>&1; then
  if [[ "$cmd" == "start" ]]; then
    osascript -e 'display notification "Automation running, hands off" with title "Automation"'
  fi
  exit 0
fi

case "$cmd" in
  start)
    # Hammerspoon owns the timeout, so a denied tool or dead agent cannot strand it.
    osascript -e "tell application \"Hammerspoon\" to execute lua code \"if G_automationCueExpiry then G_automationCueExpiry:stop() end; G_automationCueShow(); G_automationCueExpiry = hs.timer.doAfter($ttl, G_automationCueHide)\"" >/dev/null
    ;;
  stop)
    osascript -e 'tell application "Hammerspoon" to execute lua code "if G_automationCueExpiry then G_automationCueExpiry:stop(); G_automationCueExpiry = nil end; G_automationCueHide()"' >/dev/null
    ;;
  tune)
    osascript -e 'tell application "Hammerspoon" to execute lua code "G_automationCueTune()"' >/dev/null
    ;;
  *)
    echo "Usage: automation-cue.sh {start|stop|tune}" >&2
    exit 1
    ;;
esac

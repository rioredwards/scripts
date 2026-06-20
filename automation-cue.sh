#!/usr/bin/env bash
# Show/hide a fullscreen automation cue via Hammerspoon.
# Usage: automation-cue.sh start | stop

set -euo pipefail

cmd="${1:-}"

if ! pgrep -x Hammerspoon >/dev/null 2>&1; then
  if [[ "$cmd" == "start" ]]; then
    osascript -e 'display notification "Automation running — hands off" with title "Automation"'
  fi
  exit 0
fi

case "$cmd" in
  start)
    osascript -e 'tell application "Hammerspoon" to execute lua code "G_automationCueShow()"' >/dev/null
    ;;
  stop)
    osascript -e 'tell application "Hammerspoon" to execute lua code "G_automationCueHide()"' >/dev/null
    ;;
  tune)
    osascript -e 'tell application "Hammerspoon" to execute lua code "G_automationCueTune()"' >/dev/null
    ;;
  *)
    echo "Usage: automation-cue.sh {start|stop|tune}" >&2
    exit 1
    ;;
esac

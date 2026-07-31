#!/usr/bin/env bash
# Which Mac this session runs on, and whether Rio is sitting at it.
# One provider, because "where am I running" and "can Rio see this screen"
# are the same question — the second is meaningless without the first.

set -euo pipefail

host=$(scutil --get LocalHostName | tr '[:upper:]' '[:lower:]')
case "$host" in
  *mac-mini*) machine="Mac Mini" ;;
  *macbook*)  machine="MacBook Air" ;;
  *) echo "unrecognized LocalHostName: $host" >&2; exit 1 ;;
esac

echo "Machine: $machine"

if [ -n "${SSH_CONNECTION:-}" ]; then
  echo "Seat: SSH session from ${SSH_CONNECTION%% *}. Rio is NOT at this Mac. \
GUI side effects (open, screenshots, notifications, Reminders, Shortcuts) land \
on $machine's screen where he cannot see them — route anything visual to his machine."
else
  echo "Seat: Local. Rio is sitting at this Mac — GUI side effects land on his screen."
fi

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

# Seat detection. SSH_CONNECTION alone is NOT enough: agents usually run in a
# herdr pane, and the herdr daemon is long-lived. Panes inherit the daemon's
# environment — whatever was set when it first started, often weeks ago from a
# local iTerm window — not the environment of the client attached right now.
# So an SSH-driven pane looks local, and the provider confidently reported
# "Rio is sitting at this Mac" while he was on the other one. Process ancestry
# fails the same way: the pane's parent is herdr, not sshd. (tmux has this
# exact bug; the multiplexer is the reason, not the specific tool.)
#
# The screen lock is the signal that survives, because it answers the real
# question directly — not "how did this shell get here" but "can anyone see
# this Mac's screen". A locked Mac cannot show Rio anything, no matter which
# process tree asked.

# Deliberately no `ioreg | grep -q`: grep exits the moment it matches, ioreg
# takes SIGPIPE, and `pipefail` turns that into a failed pipeline — so a LOCKED
# screen reads as unlocked. Same trap as the bug above, one layer down. Capture
# first, match in-shell. Every pipeline here takes `|| true` for that reason,
# and first-line picks use parameter expansion rather than `head`.
console=$(/usr/sbin/ioreg -n Root -d1 -k IOConsoleUsers 2>/dev/null || true)
locked=no
case "$console" in *'CGSSessionScreenIsLocked"=Yes'*) locked=yes ;; esac

# Active remote logins, resolved to a machine name when the tailnet knows one.
# `who` marks remote sessions with a parenthesized origin; local ttys have none.
remote_origin=""
remote_ips=$(who 2>/dev/null | sed -n 's/.*(\([0-9][0-9.]*\))$/\1/p' || true)
remote_ip=${remote_ips%%$'\n'*}
if [ -n "$remote_ip" ]; then
  tailscale_bin=$(command -v tailscale || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)
  if [ -x "$tailscale_bin" ]; then
    names=$("$tailscale_bin" status --json 2>/dev/null \
      | jq -r --arg ip "$remote_ip" \
          '.Peer[] | select(.TailscaleIPs[0]==$ip) | .HostName' 2>/dev/null || true)
    remote_origin=${names%%$'\n'*}
  fi
  remote_origin="${remote_origin:-$remote_ip}"
fi

gui_warning="GUI side effects (open, screenshots, notifications, Reminders, \
Shortcuts) land on $machine's screen where he cannot see them — route anything \
visual to his machine. If a macOS permission prompt (TCC: calendar, \
automation, screen recording, etc.) blocks a command on this Mac, it is NOT a \
serious blocker: Rio can approve it in seconds via Screen Sharing from his \
machine. Prefer approaches that need no prompt, but if one appears, tell Rio \
and wait — do not hang silently or build workarounds."

if [ "$locked" = yes ]; then
  echo "Seat: Remote. $machine's screen is LOCKED, so Rio is NOT at this Mac\
${remote_origin:+ (active login from $remote_origin)}. $gui_warning"
elif [ -n "${SSH_CONNECTION:-}" ]; then
  echo "Seat: SSH session from ${SSH_CONNECTION%% *}. Rio is NOT at this Mac. $gui_warning"
elif [ -n "$remote_origin" ]; then
  echo "Seat: Uncertain. $machine is unlocked, but something is logged in from \
$remote_origin — Rio may be driving this Mac from there. Confirm before \
anything visual; if he is elsewhere, $gui_warning"
else
  echo "Seat: Local. Rio is sitting at this Mac — GUI side effects land on his screen."
fi

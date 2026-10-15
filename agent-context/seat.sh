#!/usr/bin/env bash
# Where Rio is replying from: this Mac, the other Mac, or his phone.
# Runs at SessionStart (via providers/10-machine.sh) and on every prompt
# (UserPromptSubmit), because he moves between devices mid-session.
#
#   seat.sh            one "Seat:" line
#   seat.sh --machine  "Machine:" line first (the SessionStart provider)
#   seat.sh --hook     the Seat line as UserPromptSubmit hook JSON
#
# Signal: keyboard/mouse idle time per Mac. Typing or clicking the prompt
# resets it to ~0 on the Mac he is at, so it answers "who just sent this"
# directly. Neither Mac touched recently while a prompt arrived = phone.
# Nothing else carries the device: transcripts and the desktop app stamp a
# phone prompt exactly like a desktop one (checked 10k+ entries, agent-skills#47).
#
# Replaced the old screen-lock + `who` check: an unlocked Mac said "Rio is
# here" for hours after he left, and it never saw the phone.
#
# Test seams: SEAT_HOST, SEAT_LOCAL_IDLE, SEAT_REMOTE_IDLE, SEAT_REMOTE_ERR.

set -euo pipefail

THRESHOLD=60 # seconds of idle after which Rio is not at that Mac

mode="${1:-}"
case "$mode" in ''|--machine|--hook) ;; *) echo "seat.sh: unknown flag: $mode" >&2; exit 1 ;; esac

host=${SEAT_HOST:-$(scutil --get LocalHostName)}
host=$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')
case "$host" in
  *mac-mini*) machine="Mac Mini";    other="MacBook Air"; other_ssh=macbook ;;
  *macbook*)  machine="MacBook Air"; other="Mac Mini";    other_ssh=mini ;;
  *) echo "seat.sh: unrecognized LocalHostName: $host" >&2; exit 1 ;;
esac

# Captured whole, then matched in-shell: piping ioreg into grep/awk under
# pipefail turns grep's early exit into SIGPIPE and a failed pipeline.
idle_from_ioreg() {
  local line=${1#*'"HIDIdleTime" = '}
  line=${line%%$'\n'*}
  [[ "$line" =~ ^[0-9]+$ ]] || { echo "no HIDIdleTime in ioreg output" >&2; return 1; }
  echo $((line / 1000000000))
}

ioreg_cmd="/usr/sbin/ioreg -r -c IOHIDSystem -k HIDIdleTime -d1"
local_idle=${SEAT_LOCAL_IDLE:-$(idle_from_ioreg "$($ioreg_cmd)")}

gui_warning="GUI side effects (open, screenshots, notifications, Reminders, \
Shortcuts) land on $machine's screen where he cannot see them. Route anything \
visual to his device. A macOS permission prompt (TCC) blocking a command on \
this Mac is not a serious blocker: tell Rio and wait, he approves it via \
Screen Sharing. Do not hang silently or build workarounds."

if [ "$local_idle" -lt "$THRESHOLD" ]; then
  seat="Seat: $machine. Rio is typing here, GUI side effects land on his screen."
else
  remote_idle=${SEAT_REMOTE_IDLE:-}
  remote_err=${SEAT_REMOTE_ERR:-}
  if [ -z "$remote_idle" ] && [ -z "$remote_err" ]; then
    # MACBOOK_NO_WAKE: the Mini's ssh config runs macbook-wake before connecting,
    # which probes for 5s and waits up to 30s on a sleeping MacBook (past the hook
    # timeout). A sleeping MacBook should read as Unknown, not be woken per prompt.
    if out=$(MACBOOK_NO_WAKE=1 ssh -n -o BatchMode=yes -o ConnectTimeout=2 "$other_ssh" "$ioreg_cmd" 2>&1); then
      remote_idle=$(idle_from_ioreg "$out" 2>&1) || { remote_err=$remote_idle; remote_idle=""; }
    else
      rc=$?
      remote_err=${out##*$'\n'}
      remote_err=${remote_err:-ssh exited $rc with no output}
    fi
  fi
  if [ -n "$remote_err" ]; then
    seat="Seat: Unknown. Could not check $other ($remote_err), so Rio may be \
there or on his phone. $machine has had no input for $((local_idle / 60))m. $gui_warning"
  elif [ "$remote_idle" -lt "$THRESHOLD" ]; then
    seat="Seat: $other. Rio is typing on the $other, not this Mac. $gui_warning"
  else
    away=$(( (local_idle < remote_idle ? local_idle : remote_idle) / 60 ))
    seat="Seat: Phone (likely). Neither Mac has had keyboard or mouse input \
for ${away}m. Keep replies short and skimmable, links tappable. $gui_warning"
  fi
fi

case "$mode" in
  --machine) printf 'Machine: %s\n%s\n' "$machine" "$seat" ;;
  --hook) jq -nc --arg c "$seat" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}' ;;
  *) echo "$seat" ;;
esac

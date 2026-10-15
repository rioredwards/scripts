#!/bin/sh
# Behavioural tests for agent-context/seat.sh (agent-skills#47).
# Idle times and the host are stubbed through env, so no ioreg or SSH runs.
#   sh tests/agent-context-seat-test.sh
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
seat="$here/agent-context/seat.sh"

fail=0
check() { # name, expected-substring-or-!substring, output
  case "$2" in
    !*) if printf '%s' "$3" | grep -qF -- "${2#!}"; then echo "FAIL $1: found '${2#!}'"; fail=1; else echo "ok   $1"; fi ;;
    *)  if printf '%s' "$3" | grep -qF -- "$2"; then echo "ok   $1"; else echo "FAIL $1: missing '$2'"; echo "$3" | sed 's/^/     /'; fail=1; fi ;;
  esac
}

export SEAT_HOST=rios-mac-mini

out="$(SEAT_LOCAL_IDLE=4 "$seat")"
check "typing here: this Mac"        "Seat: Mac Mini. Rio is typing here" "$out"
check "typing here: no SSH needed"   "!MacBook" "$out"

out="$(SEAT_LOCAL_IDLE=600 SEAT_REMOTE_IDLE=3 "$seat")"
check "other Mac: named"             "Seat: MacBook Air" "$out"
check "other Mac: GUI warning"       "land on Mac Mini's screen" "$out"

out="$(SEAT_LOCAL_IDLE=600 SEAT_REMOTE_IDLE=900 "$seat")"
check "both idle: phone"             "Seat: Phone (likely)" "$out"
check "both idle: minutes shown"     "for 10m" "$out"

out="$(SEAT_LOCAL_IDLE=600 SEAT_REMOTE_ERR="ssh: connect timed out" SEAT_REMOTE_ONLINE=true "$seat")"
check "unreachable: loud unknown"    "Seat: Unknown. Could not check MacBook Air (ssh: connect timed out)" "$out"

out="$(SEAT_LOCAL_IDLE=600 SEAT_REMOTE_ERR="ssh: connect timed out" SEAT_REMOTE_ONLINE=false "$seat")"
check "other Mac asleep: phone"      "Seat: Phone (likely). MacBook Air is asleep" "$out"

# Real SSH path with a stub ssh on PATH: ioreg parsing, error capture, no wake.
stub="$(mktemp -d)"
trap 'rm -rf "$stub"' EXIT
cat >"$stub/ssh" <<'EOF'
#!/bin/sh
[ "${MACBOOK_NO_WAKE:-}" = 1 ] || { echo "wake not disabled" >&2; exit 9; }
case "$STUB_SSH" in
  idle) printf '+-o IOHIDSystem  <class IOHIDSystem>\n  {\n    "HIDIdleTime" = 900000000000\n  }\n' ;;
  down) printf 'Warning: noise\nssh: connect to host macbook port 22: Operation timed out\n' >&2; exit 255 ;;
  silent) exit 1 ;;
esac
EOF
chmod +x "$stub/ssh"

out="$(PATH="$stub:$PATH" STUB_SSH=idle SEAT_LOCAL_IDLE=600 "$seat")"
check "ssh: ioreg parsed, phone"     "Seat: Phone (likely). Neither Mac has had keyboard or mouse input for 10m" "$out"

out="$(PATH="$stub:$PATH" STUB_SSH=down SEAT_REMOTE_ONLINE=true SEAT_LOCAL_IDLE=600 "$seat")"
check "ssh down: last error line"    "Could not check MacBook Air (ssh: connect to host macbook port 22: Operation timed out)" "$out"

out="$(PATH="$stub:$PATH" STUB_SSH=silent SEAT_REMOTE_ONLINE=true SEAT_LOCAL_IDLE=600 "$seat")"
check "ssh silent fail: not phone"   "Could not check MacBook Air (ssh exited 1 with no output)" "$out"

out="$(SEAT_HOST=rios-macbook-air SEAT_LOCAL_IDLE=600 SEAT_REMOTE_IDLE=2 "$seat")"
check "from MacBook: Mini named"     "Seat: Mac Mini" "$out"

out="$(SEAT_LOCAL_IDLE=4 "$seat" --machine)"
check "--machine: Machine line"      "Machine: Mac Mini" "$out"
check "--machine: Seat line"         "Seat: Mac Mini" "$out"

out="$(SEAT_LOCAL_IDLE=4 "$seat" --hook)"
check "--hook: event name"           '"hookEventName":"UserPromptSubmit"' "$out"
check "--hook: context"              '"additionalContext":"Seat: Mac Mini' "$out"

if SEAT_HOST=raspberrypi SEAT_LOCAL_IDLE=4 "$seat" >/dev/null 2>&1; then
  echo "FAIL unknown host: should exit non-zero"; fail=1
else
  echo "ok   unknown host fails loud"
fi

exit $fail

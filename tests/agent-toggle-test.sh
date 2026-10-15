#!/bin/sh
# agent-toggle: registry-driven knobs, machine vs per-session scope (agent-skills#46).
# Throwaway HOME so no real knob is touched.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
HOME="$tmp"; export HOME
mkdir -p "$tmp/scripts"
ln -s "$root/agent-hooks-env.sh" "$tmp/scripts/agent-hooks-env.sh"
AGENT_HOOKS_PROFILE="$tmp/profile.sh"; export AGENT_HOOKS_PROFILE
echo 'export AGENT_REPLY_MAX_WORDS=200' > "$AGENT_HOOKS_PROFILE"
unset AGENT_SESSION_ID AGENT_REPLY_MAX_WORDS AGENT_ATTENTION 2>/dev/null || true
t="$root/agent-toggle"

fail() { echo "FAIL: $1"; exit 1; }
want() { case "$2" in *"$3"*) ;; *) fail "$1: got '$2', want '$3'" ;; esac; }

# registry knobs resolve, aliases too, and new knobs fall back to their default
want "default attention" "$("$t" attention)" "attention: foreground (default)"
want "alias" "$("$t" words)" "words: 200 (profile)"
"$t" set budget off >/dev/null
want "toggle alias" "$("$t" loc-budget)" "loc-budget: off"

# an option outside the registry's list is refused
"$t" set attention sideways >/dev/null 2>&1 && fail "bad option accepted"

# session scope overrides the machine value for that session only
"$t" set reply-cap 300 >/dev/null
"$t" --session s1 set reply-cap 100 >/dev/null
want "session value" "$("$t" --session s1 reply-cap)" "reply-cap: 100 (session)"
want "other session" "$("$t" --session s2 reply-cap)" "reply-cap: 300 (local)"
want "machine" "$("$t" reply-cap)" "reply-cap: 300 (local)"

# hooks see the session layer when AGENT_SESSION_ID is set
v="$(AGENT_SESSION_ID=s1 sh -c '. "$HOME/scripts/agent-hooks-env.sh"; printf %s "$AGENT_REPLY_MAX_WORDS"')"
[ "$v" = 100 ] || fail "loader session: got '$v'"
v="$(sh -c '. "$HOME/scripts/agent-hooks-env.sh"; printf %s "$AGENT_REPLY_MAX_WORDS"')"
[ "$v" = 300 ] || fail "loader machine: got '$v'"

# unset drops only the session override
"$t" --session s1 unset reply-cap >/dev/null
want "session unset" "$("$t" --session s1 reply-cap)" "reply-cap: 300 (local)"

# a session id that could escape the sessions dir is refused
"$t" --session ../x set attention away >/dev/null 2>&1 && fail "bad session id accepted"

# --json carries options and the session flag the band renders from
"$t" --session s1 set attention away >/dev/null
j="$("$t" --session s1 --json)"
printf '%s' "$j" | jq -e '.[] | select(.name=="attention") | .value=="away" and .source=="session" and .session==true and (.options|index("background"))' >/dev/null \
  || fail "json attention row: $j"
printf '%s' "$j" | jq -e '.[] | select(.name=="reply-cap") | .options==["off","100","200","300"]' >/dev/null \
  || fail "json reply-cap options"
printf '%s' "$j" | jq -e '.[] | select(.name=="text") | .kind=="toggle" and .session==false' >/dev/null \
  || fail "json toggle row"

# help is generated from the registry, so it lists every knob
want "help" "$("$t" help)" "tokens"

echo "agent-toggle: ok"

#!/bin/sh
# Session knobs reach the agent: at SessionStart, again when they change
# mid-session, and the reply cap enforces per session (agent-skills#46).
# Throwaway HOME so no real knob is touched.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
HOME="$tmp"; export HOME
ln -s "$root" "$tmp/scripts"
mkdir -p "$tmp/.claude" && echo '"reply-cap"' > "$tmp/.claude/settings.json"
AGENT_HOOKS_PROFILE="$tmp/profile.sh"; export AGENT_HOOKS_PROFILE
echo 'export AGENT_REPLY_MAX_WORDS=200' > "$AGENT_HOOKS_PROFILE"
unset AGENT_SESSION_ID AGENT_REPLY_MAX_WORDS AGENT_ATTENTION AGENT_DELEGATE 2>/dev/null || true
t="$root/agent-toggle"
k="$root/agent-context/knobs.sh"

fail() { echo "FAIL: $1"; exit 1; }
want() { case "$2" in *"$3"*) ;; *) fail "$1: got '$2', want '$3'" ;; esac; }
hook() { printf '{"session_id":"%s"}' "$1" | bash "$k" --hook; }

# SessionStart provider: cap line plus every session knob with its meaning
out="$(bash "$root/agent-context/providers/30-knobs.sh")"
want "cap line" "$out" "Reply cap: 200 prose words"
want "knob line" "$out" "- attention: foreground. Rio is here"
want "auto knob" "$out" "- tokens: auto."

# provider stamps the session, so its first prompt does not repeat the block
AGENT_SESSION_ID=s1 bash "$root/agent-context/providers/30-knobs.sh" >/dev/null
[ -z "$(hook s1)" ] || fail "unchanged knobs re-injected"

# a mid-session change is injected once, on the next prompt
"$t" --session s1 set attention away >/dev/null
"$t" --session s1 set reply-cap 100 >/dev/null
out="$(hook s1)"
want "hook event" "$out" '"hookEventName":"UserPromptSubmit"'
want "changed knob" "$out" "attention: away. Rio is away"
want "session cap" "$out" "Reply cap: 100"
[ -z "$(hook s1)" ] || fail "same change injected twice"

# another session keeps the machine values
want "other session" "$(hook s2)" "attention: foreground"

# reply cap enforces the session's value, not the machine's
words="$(yes word | head -150 | tr '\n' ' ')"
bounce() {
  printf '{"session_id":"%s","last_assistant_message":"%s"}' "$1" "$words" > "$tmp/p.json"
  bash -c '. "$HOME/scripts/hooks/lib/reply-cap-lib.sh"; reply_will_bounce "$(cat "$1")" && echo "bounce $REPLY_CAP"' _ "$tmp/p.json" || true
}
want "session cap bounces" "$(bounce s1)" "bounce 100"
[ -z "$(bounce s2)" ] || fail "machine cap 200 bounced a 150-word reply"

echo "agent-context-knobs: ok"

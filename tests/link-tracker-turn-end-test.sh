#!/bin/sh
# claude-turn-end feeds the Stop payload to link-tracker.sh, which writes the
# statusline marker file /tmp/claude-links-<session> with an OSC-8 link, and
# statusline-command.sh renders it. Subagent turns do not write it.
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
sid="linktest-$$"
trap 'rm -rf "$tmp" "/tmp/claude-links-$sid"' EXIT

HOME="$tmp/home"; export HOME
mkdir -p "$HOME/dev/agent-sessions/bin"
printf '#!/bin/sh\n' > "$HOME/dev/agent-sessions/bin/index-session"
sr="$tmp/scripts"; export SCRIPTS="$sr"
mkdir -p "$sr/hooks/turn-end" "$sr/hooks/lib"
cp "$repo/hooks/turn-end/dispatch" "$repo/hooks/turn-end/claude-turn-end" "$sr/hooks/turn-end/"
cp "$repo/hooks/link-tracker.sh" "$sr/hooks/"
printf '#!/bin/sh\n' > "$sr/agent-hooks-env.sh"
chmod +x "$HOME/dev/agent-sessions/bin/index-session"

fail() { echo "FAIL: $1"; exit 1; }

printf '{"session_id":"%s","cwd":"%s","last_assistant_message":"See [the PR](https://github.com/o/r/pull/7)."}' "$sid" "$tmp" \
  | sh "$sr/hooks/turn-end/claude-turn-end" >/dev/null 2>&1 || true
[ -s "/tmp/claude-links-$sid" ] || fail "no marker written for a reply with a link"
grep -q 'https://github.com/o/r/pull/7' "/tmp/claude-links-$sid" || fail "marker lacks the link"

: > "/tmp/claude-links-$sid"
printf '{"session_id":"%s","agent_id":"a1","cwd":"%s","last_assistant_message":"https://example.com/x"}' "$sid" "$tmp" \
  | sh "$sr/hooks/turn-end/claude-turn-end" >/dev/null 2>&1 || true
[ ! -s "/tmp/claude-links-$sid" ] || fail "subagent turn wrote the marker"
echo PASS

#!/bin/sh
# Every turn indexes the sessions DB exactly once, before dispatch decides to
# skip it: empty replies and delegate (subagent) turns index but notify nothing
# (agent-sessions#13). Real dispatch, stubbed scripts_root, fake HOME.
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

HOME="$tmp/home"; export HOME
idx="$HOME/dev/agent-sessions/bin/index-session"
mkdir -p "$(dirname "$idx")"
printf '#!/bin/sh\necho run >> "%s/indexed"\n' "$tmp" > "$idx"

sr="$tmp/scripts"; export SCRIPTS="$sr"
mkdir -p "$sr/hooks/turn-end"
cp "$repo/hooks/turn-end/dispatch" "$sr/hooks/turn-end/"
printf '#!/bin/sh\n' > "$sr/agent-hooks-env.sh"
for stub in sc aitt; do
  printf '#!/bin/sh\necho %s >> "%s/notified"\n' "$stub" "$tmp" > "$sr/$stub"
done
chmod +x "$idx" "$sr/agent-hooks-env.sh" "$sr/sc" "$sr/aitt"

fail() { echo "FAIL: $1"; exit 1; }
runs() { cat "$tmp/indexed" 2>/dev/null | wc -l | tr -d ' '; }
# index-session is detached: wait (up to 5s) for it to land, then long enough
# to catch a second, duplicate run.
indexed() {
  i=0
  while [ "$(runs)" -lt "$1" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  sleep 0.5
  [ "$(runs)" -eq "$1" ]
}

printf '' | HOOK_AGENT=claude AGENT_DELEGATE='' sh "$sr/hooks/turn-end/dispatch"
indexed 1 || fail "empty reply: want 1 index run, got $(runs)"

printf 'a reply' | HOOK_AGENT=claude AGENT_DELEGATE=1 sh "$sr/hooks/turn-end/dispatch"
indexed 2 || fail "delegate turn: want 2 index runs, got $(runs)"

[ ! -e "$tmp/notified" ] || fail "skipped turn notified: $(cat "$tmp/notified")"

# A normal reply, with the narration pipeline stubbed to succeed.
for s in narration-context agent-toggle; do printf '#!/bin/sh\nexit 0\n' > "$sr/$s"; done
for s in narration-spoken narration-body narration-render; do printf '#!/bin/sh\ncat\n' > "$sr/$s"; done
printf '#!/bin/sh\nhead -1\n' > "$sr/narration-title"
printf '#!/bin/sh\nprintf "TITLE: t\\nfine narration\\n"\n' > "$sr/aitt"
chmod +x "$sr"/narration-* "$sr/agent-toggle" "$sr/aitt"
printf 'a reply' | HOOK_AGENT=claude AGENT_DELEGATE='' AGENT_SPEAK=off AGENT_AUDIO_FILE=off \
  AGENT_WEBVIEW=off AGENT_TEXT=off sh "$sr/hooks/turn-end/dispatch"
indexed 3 || fail "normal reply: want 3 index runs, got $(runs)"

echo "PASS turn-end-index-test"

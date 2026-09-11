#!/bin/sh
# Every turn indexes the sessions DB exactly once, before dispatch decides to
# skip it, and names the session that ended: empty replies and delegate
# (subagent) turns index but notify nothing (agent-sessions#13). Real dispatch
# and claude-turn-end, stubbed scripts_root, fake HOME.
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

HOME="$tmp/home"; export HOME
idx="$HOME/dev/agent-sessions/bin/index-session"
mkdir -p "$(dirname "$idx")"
cat > "$idx" <<EOF
#!/bin/sh
printf '%s|%s|%s\n' "\$1" "\$2" "\$3" >> "$tmp/indexed"
EOF

sr="$tmp/scripts"; export SCRIPTS="$sr"
mkdir -p "$sr/hooks/turn-end" "$sr/hooks/lib"
cp "$repo/hooks/turn-end/dispatch" "$repo/hooks/turn-end/claude-turn-end" "$sr/hooks/turn-end/"
printf '#!/bin/sh\n' > "$sr/agent-hooks-env.sh"
for stub in sc aitt; do
  printf '#!/bin/sh\necho %s >> "%s/notified"\n' "$stub" "$tmp" > "$sr/$stub"
done
chmod +x "$idx" "$sr/agent-hooks-env.sh" "$sr/sc" "$sr/aitt"

fail() { echo "FAIL: $1"; exit 1; }
runs() { cat "$tmp/indexed" 2>/dev/null | wc -l | tr -d ' '; }
# index-session is detached: wait (up to 5s) for it to land, then long enough
# to catch a second, duplicate run. $2 is the provider|id|path it must receive.
indexed() {
  i=0
  while [ "$(runs)" -lt "$1" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  sleep 0.5
  [ "$(runs)" -eq "$1" ] || fail "$3: want $1 index runs, got $(runs)"
  got="$(tail -1 "$tmp/indexed")"
  [ "$got" = "$2" ] || fail "$3: index-session got '$got', want '$2'"
}

printf '' | HOOK_AGENT=claude HOOK_SESSION_ID=s1 HOOK_TRANSCRIPT_PATH=/t/s1.jsonl \
  AGENT_DELEGATE='' sh "$sr/hooks/turn-end/dispatch"
indexed 1 'claude|s1|/t/s1.jsonl' "empty reply"

printf 'a reply' | HOOK_AGENT=codex HOOK_SESSION_ID=s2 HOOK_TRANSCRIPT_PATH=/t/s2.jsonl \
  AGENT_DELEGATE=1 sh "$sr/hooks/turn-end/dispatch"
indexed 2 'codex|s2|/t/s2.jsonl' "delegate turn"

# A Claude subagent: SubagentStop names the parent session, so the subagent's
# own id and file must win. The reply cap never applies to a delegate, so a cap
# that would bounce the reply must not stop the index.
printf 'reply_will_be_rewritten() { return 0; }\n' > "$sr/hooks/lib/reply-cap-lib.sh"
printf '%s' '{"session_id":"parent","transcript_path":"/t/parent.jsonl","agent_id":"abc","agent_transcript_path":"/t/parent/subagents/agent-abc.jsonl","last_assistant_message":"sub reply"}' |
  AGENT_DELEGATE=1 sh "$sr/hooks/turn-end/claude-turn-end"
indexed 3 'claude|agent-abc|/t/parent/subagents/agent-abc.jsonl' "subagent turn"

[ ! -e "$tmp/notified" ] || fail "skipped turn notified: $(cat "$tmp/notified")"
[ ! -e "$HOME/.cache/note-on-turn/perf.log" ] || fail "skipped turn reached the notify pipeline"

# A normal reply, with the narration pipeline stubbed to succeed.
for s in narration-context agent-toggle; do printf '#!/bin/sh\nexit 0\n' > "$sr/$s"; done
for s in narration-spoken narration-body narration-render; do printf '#!/bin/sh\ncat\n' > "$sr/$s"; done
printf '#!/bin/sh\nhead -1\n' > "$sr/narration-title"
printf '#!/bin/sh\nprintf "TITLE: t\\nfine narration\\n"\n' > "$sr/aitt"
chmod +x "$sr"/narration-* "$sr/agent-toggle" "$sr/aitt"
printf 'a reply' | HOOK_AGENT=claude HOOK_SESSION_ID=s4 HOOK_TRANSCRIPT_PATH=/t/s4.jsonl \
  AGENT_DELEGATE='' AGENT_SPEAK=off AGENT_AUDIO_FILE=off \
  AGENT_WEBVIEW=off AGENT_TEXT=off sh "$sr/hooks/turn-end/dispatch"
indexed 4 'claude|s4|/t/s4.jsonl' "normal reply"

echo "PASS turn-end-index-test"

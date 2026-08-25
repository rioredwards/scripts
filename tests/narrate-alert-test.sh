#!/bin/sh
# Repeated narrate-turn failures must text the phone (scripts#8).
# Runs the real note-from-reply against a stubbed scripts_root and a fake HOME,
# so no real Shortcuts, LLMs, or logs are touched.
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Fake HOME so log_dir/counters land in the sandbox.
HOME="$tmp/home"; export HOME
mkdir -p "$HOME"

# Stub scripts_root: real note-from-reply, everything it calls stubbed.
sr="$tmp/scripts"; export SCRIPTS="$sr"
mkdir -p "$sr/hooks/note-on-turn"
cp "$repo/hooks/note-on-turn/note-from-reply" "$sr/hooks/note-on-turn/"
printf '#!/bin/sh\n' > "$sr/agent-hooks-env.sh"
printf '#!/bin/sh\nexit 0\n' > "$sr/narration-context"
printf '#!/bin/sh\ncat\n' > "$sr/narration-spoken"
printf '#!/bin/sh\ncat\n' > "$sr/narration-body"
printf '#!/bin/sh\ncat\n' > "$sr/narration-render"
printf '#!/bin/sh\nhead -1\n' > "$sr/narration-title"
printf '#!/bin/sh\nexit 0\n' > "$sr/agent-toggle"
# sc records every invocation: args + stdin, one block per call.
cat > "$sr/sc" <<EOF
#!/bin/sh
{ printf 'CALL %s :: ' "\$*"; cat; printf '\n'; } >> "$tmp/sc.log"
EOF
# aitt: mode controlled by a file so the test flips failure/success.
cat > "$sr/aitt" <<EOF
#!/bin/sh
if [ -f "$tmp/aitt-ok" ]; then printf 'TITLE: t\nfine narration\n'; else
  echo 'Anthropic API 400: credit balance too low' >&2; exit 1; fi
EOF
chmod +x "$sr"/agent-hooks-env.sh "$sr"/narration-* "$sr"/agent-toggle "$sr"/sc "$sr"/aitt

run_turn() { printf 'a reply' | HOOK_AGENT=claude AGENT_DELEGATE= \
  AGENT_SPEAK=off AGENT_AUDIO_FILE=off AGENT_WEBVIEW=off AGENT_TEXT=off \
  AGENT_NARRATE_ALERT_AFTER=3 AGENT_NARRATE_ALERT_EVERY=1800 \
  sh "$sr/hooks/note-on-turn/note-from-reply"; }

fail() { echo "FAIL: $1"; cat "$tmp/sc.log" 2>/dev/null; exit 1; }
calls() { grep -c 'CALL' "$tmp/sc.log" 2>/dev/null || echo 0; }

run_turn; run_turn
[ "$(calls)" -eq 0 ] || fail "alerted before threshold"

run_turn
[ "$(calls)" -eq 1 ] || fail "no alert on 3rd consecutive failure"
grep -q '🔴' "$tmp/sc.log" || fail "alert text missing 🔴"
grep -q 'aitt narrate-turn' "$tmp/sc.log" || fail "alert missing stage"
grep -q 'credit balance too low' "$tmp/sc.log" || fail "alert missing stderr detail"

run_turn
[ "$(calls)" -eq 1 ] || fail "debounce ignored — alerted twice in window"

touch "$tmp/aitt-ok"; run_turn
[ "$(calls)" -eq 2 ] || fail "no recovery notice"
grep -q '🟢' "$tmp/sc.log" || fail "recovery text missing 🟢"
[ ! -f "$HOME/.cache/note-on-turn/narrate-failed.count" ] || fail "counter not reset"

# A fresh single failure after recovery: quiet again.
rm -f "$tmp/aitt-ok"; run_turn
[ "$(calls)" -eq 2 ] || fail "alerted on first failure of new streak"

echo PASS

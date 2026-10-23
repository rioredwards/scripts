#!/bin/sh
# reply-options: generate writes a validated state file with engine-fixed
# colors, dedupes per reply, skips Codex suggestions, fails loud on a bad
# model answer; get adds title/stale. Stubs curl and keyfor; no model call.
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho sk-test\n' > "$tmp/bin/keyfor"
printf '#!/bin/sh\necho call >> "%s/calls"\ncat "%s/resp"\n' "$tmp" "$tmp" > "$tmp/bin/curl"
chmod +x "$tmp/bin/keyfor" "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH" REPLY_OPTIONS_DIR="$tmp/state" OPENAI_CALL_COUNT_DIR="$tmp/counts"
t="$tmp/t.jsonl"
printf '{"type":"user","timestamp":"2020-01-01T00:00:00Z","message":{"content":"fix the cache"}}\n' > "$t"

fail() { echo "FAIL: $1"; exit 1; }
answer() { jq -nc --argjson o "$1" '{output:[{type:"message",content:[{type:"output_text",text:($o|tojson)}]}]}' > "$tmp/resp"; echo 200 >> "$tmp/resp"; }
calls() { cat "$tmp/calls" 2>/dev/null | wc -l | tr -d ' '; }
gen() { printf '%s' "$1" | "$repo/reply-options" generate --agent claude --session "$2" --cwd /x --transcript "$t"; }

answer '{"options":[{"category":"accept","label":"Ship it","text":"yes ship the cache fix"},{"category":"verify","label":"Prove it","text":"run the tests first"}],"skip_reason":null}'
gen "Ship the cache fix?" s1 || fail "ready generate exited non-zero"
f="$tmp/state/claude-s1.json"; [ "$(jq -c '[.status, .options[0].id, .options[0].color, .options[1].color]' "$f")" = '["ready","o1","green","purple"]' ] || fail "ready state: $(cat "$f")"
[ -f "$tmp/counts/$(date -u +%Y-%m-%d).reply-options" ] || fail "call not charged to the reply-options bucket"
gen "Ship the cache fix?" s1; [ "$(calls)" = 1 ] || fail "same reply called the model again"

gen '{"suggestion":"Can we?"}' s2 2>/dev/null; [ "$(calls)" = 1 ] && [ ! -e "$tmp/state/claude-s2.json" ] || fail "suggestion reached the model"

answer '{"options":[{"category":"accept","label":"Ok","text":"ok"}],"skip_reason":null}'
if gen "one option" s3 2>"$tmp/err"; then fail "one option should fail"; fi
grep -q "1 options" "$tmp/err" && [ "$(jq -r .status "$tmp/state/claude-s3.json")" = error ] || fail "bad answer not an error file"

answer '{"options":[],"skip_reason":"pure report"}'
gen "Done, all green." s4 && [ "$(jq -r .status "$tmp/state/claude-s4.json")" = skipped ] || fail "skip not recorded"

out="$("$repo/reply-options" get --session s1)"
[ "$(printf '%s' "$out" | jq -c '[.title, .stale]')" = '[null,false]' ] || fail "get: $out"
[ "$("$repo/reply-options" get --recent 2 | jq length)" = 2 ] || fail "recent count"
printf '{"type":"user","timestamp":"2999-01-01T00:00:00Z","message":{"content":"yes"}}\n' >> "$t"
[ "$("$repo/reply-options" get --session s1 | jq .stale)" = true ] || fail "Rio's newer reply not stale"
[ "$("$repo/reply-options" get --recent | jq length)" = 0 ] || fail "recent kept stale sessions"
echo "PASS reply-options-test"

#!/bin/sh
# attention-judge.sh: pass is silent, each predicate over threshold bounces,
# failures pass with a warning, skips never call the API.
# Stubs curl and keyfor so no model is called; state goes to a temp TMPDIR.
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/state"
cat > "$tmp/bin/keyfor" <<'STUB'
#!/bin/sh
echo sk-test
STUB
cat > "$tmp/bin/curl" <<STUB
#!/bin/sh
echo call >> "$tmp/calls"
cat "$tmp/resp"
STUB
chmod +x "$tmp/bin/keyfor" "$tmp/bin/curl"
printf '{"type":"user","message":{"role":"user","content":"fix the flaky test"}}\n' > "$tmp/t.jsonl"

answers() { # needless unclear noise [code] [type of first answer]
  printf '{"answers":[{"type":"%s","name":"needless_ask","probability":%s},{"type":"predicate","name":"unclear","probability":%s},{"type":"predicate","name":"noise","probability":%s}]}\n%s' \
    "${5:-predicate}" "$1" "$2" "$3" "${4:-200}"
}

fail=0
n=0
# usage: check <label> <expected exit> <stdout/stderr must contain> <expected calls> [jq payload edits]
check() {
  n=$((n + 1))
  rm -f "$tmp/calls"; touch "$tmp/calls"
  rc=0
  jq -nc --arg t "$tmp/t.jsonl" --arg r "Should I use waitFor or bump the timeout? ($n)" \
    "{session_id:\"s1\", transcript_path:\$t, last_assistant_message:\$r, stop_hook_active:false} ${5:-}" \
    | PATH="$tmp/bin:$PATH" TMPDIR="$tmp/state" HOME="$HOME" AGENT_ATTENTION_JUDGE=on AGENT_DELEGATE='' \
      JUDGE_LOG="$tmp/log.jsonl" bash "$repo/hooks/attention-judge.sh" >"$tmp/out" 2>&1 || rc=$?
  calls="$(wc -l < "$tmp/calls" | tr -d ' ')"
  if [ -z "$3" ]; then [ ! -s "$tmp/out" ]; else grep -q -- "$3" "$tmp/out"; fi && seen=1 || seen=0
  if [ "$rc" -ne "$2" ] || [ "$seen" -ne 1 ] || [ "$calls" -ne "$4" ]; then
    echo "FAIL: $1: exit $rc (want $2), calls $calls (want $4)"; sed 's/^/  | /' "$tmp/out"; fail=1
  fi
}

answers 0.1 0.1 0.1 > "$tmp/resp";        check "clean reply passes" 0 "" 1
answers 0.95 0.1 0.1 > "$tmp/resp";       check "needless ask bounces" 2 "decide yourself" 1
answers 0.1 0.9 0.1 > "$tmp/resp";        check "unclear bounces" 2 "one skim" 1
answers 0.1 0.1 0.85 > "$tmp/resp";       check "noise bounces" 2 "say done and stop" 1
answers 0.1 0.1 0.1 500 > "$tmp/resp";    check "HTTP error warns, passes" 0 "systemMessage" 1
answers 0.1 0.1 0.1 200 refusal > "$tmp/resp"; check "refusal warns, passes" 0 "refusal on needless_ask" 1
answers 0.95 0.1 0.1 > "$tmp/resp"
check "rewrite pass skips" 0 "" 0 '| .stop_hook_active=true'
check "delegate skips" 0 "" 0 '| .agent_id="a1"'
check "codex suggestion skips" 0 "" 0 '| .last_assistant_message="{\"suggestion\":\"Can we?\"}"'

# Same reply twice in one session: second caller reads the stored verdict.
rm -f "$tmp/calls"; touch "$tmp/calls"
for _ in 1 2; do
  jq -nc --arg t "$tmp/t.jsonl" '{session_id:"s2", transcript_path:$t, last_assistant_message:"same"}' \
    | PATH="$tmp/bin:$PATH" TMPDIR="$tmp/state" AGENT_ATTENTION_JUDGE=on AGENT_DELEGATE='' \
      JUDGE_LOG="$tmp/log.jsonl" bash "$repo/hooks/attention-judge.sh" >/dev/null 2>&1 || true
done
[ "$(wc -l < "$tmp/calls" | tr -d ' ')" -eq 1 ] || { echo "FAIL: verdict not shared, $(wc -l < "$tmp/calls") calls"; fail=1; }
grep -q '"prompt":"fix the flaky test"' "$tmp/log.jsonl" || { echo "FAIL: log missing prompt"; fail=1; }

[ "$fail" -eq 0 ] && echo "attention-judge-test: ok"
exit "$fail"

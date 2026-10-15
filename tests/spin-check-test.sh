#!/bin/sh
# spin-check.sh: only a flag the second look confirms with a quote from the input is injected.
# Stubs curl (Decisions screen + second look) and keyfor, so no model is called;
# state goes to a temp TMPDIR.
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/state"
cat > "$tmp/bin/curl" <<STUB
#!/bin/sh
cat > /dev/null
case "\$*" in
  *v1/responses*)
    jq -c '{output: [{type: "message", content: [{type: "output_text", text: tojson}]}]}' "$tmp/confirm.json" ;;
  *)
    jq -nc --argjson p "\$(cat "$tmp/p")" '{answers: [("overrun", "unasked_change", "loop", "drift")
      | {type: "predicate", name: ., probability: (if . == "overrun" then \$p else 0 end)}]}' ;;
esac
printf '\n200'
STUB
printf '#!/bin/sh\necho sk-test\n' > "$tmp/bin/keyfor"
chmod +x "$tmp/bin/curl" "$tmp/bin/keyfor"

cat > "$tmp/t.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"do the thing"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working on it"},{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
JSONL

fail=0
# usage: check <screen probability> <verdict> <quote> <expected exit code> <label>
check() {
  printf '%s' "$1" > "$tmp/p"
  jq -nc --arg v "$2" --arg q "$3" '{category: "OVERRUN", quote: $q, evidence: "Rio asked for less.", verdict: $v}' > "$tmp/confirm.json"
  rm -rf "$tmp/state/claude-spin-check"
  rc=0
  printf '{"session_id":"s1","hook_event_name":"PostToolUse","transcript_path":"%s","cwd":"/x"}' "$tmp/t.jsonl" \
    | PATH="$tmp/bin:$PATH" TMPDIR="$tmp/state" AGENT_SPIN_CHECK=on AGENT_SPIN_CHECK_EVERY=1 \
      AGENT_SPIN_CHECK_LOG=off AGENT_DELEGATE='' bash "$repo/hooks/spin-check.sh" >/dev/null 2>"$tmp/err" || rc=$?
  if [ "$rc" -ne "$4" ]; then
    echo "FAIL: $5: expected exit $4, got $rc"; sed 's/^/  | /' "$tmp/err"; fail=1
  fi
}

check 0.1 confirm "working on it" 0 "screen passes: no second look"
check 0.9 deny "working on it" 0 "second look denies"
check 0.9 confirm "working on it" 2 "confirmed with a real quote"
check 0.9 confirm "  Working   ON it. " 2 "quote matched ignoring case, spacing and a trailing period"
check 0.9 confirm "rewrote the database" 0 "quote not in the input"
check 0.9 confirm "" 0 "confirm with no quote"

[ "$fail" -eq 0 ] && echo "spin-check-test: ok"
exit "$fail"

#!/bin/sh
# spin-check.sh: an "on track" verdict in any case is silent; a course-correction is injected.
# Stubs agent-router so no reviewer model is called; state goes to a temp TMPDIR.
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/state"
cat > "$tmp/bin/agent-router" <<STUB
#!/bin/sh
cat "$tmp/verdict"
STUB
chmod +x "$tmp/bin/agent-router"

cat > "$tmp/t.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"do the thing"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working on it"},{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
JSONL

fail=0
# usage: check <verdict> <expected exit code> <label>
check() {
  printf '%s\n' "$1" > "$tmp/verdict"
  rm -f "$tmp/state"/claude-spin-check/*
  rc=0
  printf '{"session_id":"s1","hook_event_name":"PostToolUse","transcript_path":"%s","cwd":"/x"}' "$tmp/t.jsonl" \
    | PATH="$tmp/bin:$PATH" TMPDIR="$tmp/state" AGENT_SPIN_CHECK=on AGENT_SPIN_CHECK_EVERY=1 \
      AGENT_SPIN_CHECK_LOG=off AGENT_DELEGATE='' bash "$repo/hooks/spin-check.sh" >/dev/null 2>"$tmp/err" || rc=$?
  if [ "$rc" -ne "$2" ]; then
    echo "FAIL: $3 (verdict '$1'): expected exit $2, got $rc"; sed 's/^/  | /' "$tmp/err"; fail=1
  fi
}

check "ON TRACK" 0 "upper case"
check "On track" 0 "title case"
check "on track." 0 "lower case"
check "COURSE-CORRECT: you are looping on ls" 2 "course-correct injected"
check "Course-correct: looping" 2 "title-case course-correct still injected"

[ "$fail" -eq 0 ] && echo "spin-check-test: ok"
exit "$fail"

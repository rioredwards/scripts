#!/bin/sh
# issue-skill-guard: real `gh issue create/edit` runs are gated; quoted
# mentions (jq/grep patterns, messages) pass. Runs the real hook, no agent.
set -u

hook="$(cd "$(dirname "$0")/.." && pwd)/hooks/issue-skill-guard.sh"
sid="test-$$-$(date +%s)"
pass=0 fail=0

run() { jq -n --arg c "$1" --arg s "$sid" '{session_id: $s, tool_input: {command: $c}}' | bash "$hook"; }
check() {
  if run "$2" | grep -q '"deny"'; then got=blocked; else got=allowed; fi
  if [ "$got" = "$1" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL: want $1, got $got: $2" >&2; fi
}

check blocked 'gh issue create --title x --body y'
check blocked 'gh issue edit 12 --add-label bug'
check blocked 'cd ~/dev/app && gh issue create -t x -b y'
check blocked 'URL=$(gh issue create -t x -b y)'
check blocked 'echo "$(gh issue create -t x -b y)"'
check blocked 'RIO_X=1 gh issue edit 3 --body-file -'
check blocked "bash -c 'gh issue create -t x'"
check blocked "ssh mini 'cd app && gh issue edit 4 -b y'"
check blocked 'if true; then gh issue create -t x; fi'

check allowed "jq -r 'select(.command | test(\"gh issue create\"))' log.jsonl"
check allowed "jq 'select(.cmd | test(\"(gh issue create|gh issue edit)\"))' f"
check allowed 'grep -n "gh issue create" hooks/*.sh'
check allowed "rg 'x; gh issue edit' ."
check allowed 'git commit -m "guard: ignore quoted gh issue create mentions"'
check allowed 'gh issue view 12'

touch "/tmp/claude-issue-skill-$sid"
check allowed 'gh issue create --title x --body y'
rm -f "/tmp/claude-issue-skill-$sid"

echo "issue-skill-guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

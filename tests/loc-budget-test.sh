#!/bin/bash
# loc-budget: `pre` denies git commit/push while `agent-budget status` is over,
# for the main agent and for subagents (agent_id), through a `cd <repo> &&`
# lead from a cwd with no budget. Also: hooklog reports the hook's own exit
# code when the knob is off and the hook never reads a big payload.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/loc-budget.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "  FAIL: $*" >&2; }

git init -q "$work/over" && git -C "$work/over" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
git init -q "$work/main"
(cd "$work/over" && "$root/agent-budget" set 1 >/dev/null && seq 1 5 > f.txt)

# run <command> <extra payload json> [knob]: prints the decision, or "none".
run() {
  local out
  out="$(jq -n --arg c "$1" --arg cwd "$work/main" --argjson x "$2" \
    '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$c}} + $x' \
    | AGENT_LOC_BUDGET="${3:-on}" bash "$hook" pre | jq -r '.hookSpecificOutput.permissionDecision // empty')"
  echo "${out:-none}"
}
want() { [ "$1" = "$2" ] && ok || bad "want $1, got $2: $3"; }

for x in '{}' '{"agent_id":"a1","agent_type":"general-purpose"}'; do
  want deny "$(run "cd $work/over && agent-budget status; git add -A && git commit -q -m x" "$x")" "add && commit ($x)"
  want deny "$(run "cd $work/over && git add -A && git commit -q --amend --no-edit 2>&1 | tail -3" "$x")" "amend ($x)"
  want deny "$(run "cd $work/over && git push" "$x")" "push ($x)"
  want none "$(run "cd $work/over && git status" "$x")" "status ($x)"
  want none "$(run "cd $work/over && RIO_BUDGET_OK=1 git commit -m x" "$x")" "escape hatch ($x)"
  want none "$(run "git commit -m x" "$x")" "cwd without a budget ($x)"
done
want none "$(run "cd $work/over && git commit -m x" '{}' off)" "knob off"

# hooklog passthrough: knob off + payload bigger than the pipe buffer.
big="$work/big.json"
jq -n --arg s "$(head -c 200000 /dev/zero | tr '\0' a)" '{tool_name:"mcp__x",cwd:"/tmp",tool_input:{code:$s}}' > "$big"
AGENT_LOC_BUDGET=off AGENT_HOOK_LOG=off "$root/hooks/lib/hooklog" PostToolUse "bash '$hook' post" < "$big"
want 0 "$?" "hooklog exit code with big payload"

echo "loc-budget: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

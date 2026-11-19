#!/bin/bash
# agent-skills-publish: attribution and commit scope against a temp repo; no plugins,
# no other Mac, no real agent-skills checkout.
set -u
P="$(cd "$(dirname "$0")/.." && pwd)/hooks/turn-end/agent-skills-publish"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "  ok: $1"; else echo "  FAIL: $1 (want '$3', got '$2')" >&2; fail=1; fi; }
export HOME="$tmp/home"; mkdir "$HOME" # a failing publish must not reach the real PM inbox

git init -q --bare "$tmp/remote.git"
git clone -q "$tmp/remote.git" "$tmp/repo" 2>/dev/null
R="$tmp/repo"
git -C "$R" config user.email t@t; git -C "$R" config user.name t
printf 'a\n' >"$R/mine.md"; printf 'b\n' >"$R/theirs.md"; printf 'l\n' >"$R/LEDGER.md"; printf 'g\n' >"$R/GOALS.md"
git -C "$R" add -A; git -C "$R" commit -qm init; git -C "$R" push -q origin HEAD 2>/dev/null
export AGENT_SKILLS_REPO="$R" AGENT_SKILLS_PUBLISH_STATE="$tmp/state" AGENT_SKILLS_PUBLISH_OTHER=""

# Claude: Edit/Write calls on repo paths; LEDGER implies GOALS.
cat >"$tmp/claude.jsonl" <<J
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$R/mine.md"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"$R/LEDGER.md"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"$R/theirs.md"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/elsewhere/x.md"}}]}}
J
check "claude attribution" "$("$P" --touched claude "$tmp/claude.jsonl" | tr '\n' ' ')" "GOALS.md LEDGER.md mine.md "

# Codex: apply_patch headers in the rollout and in a subagent rollout naming it as parent.
mkdir -p "$tmp/codex/2026/11/16"
cat >"$tmp/codex/2026/11/16/rollout-main.jsonl" <<J
{"type":"session_meta","payload":{"id":"main-1"}}
{"type":"response_item","payload":{"name":"apply_patch","input":"*** Begin Patch\n*** Update File: $R/mine.md\n@@\n"}}
J
cat >"$tmp/codex/2026/11/16/rollout-child.jsonl" <<J
{"type":"session_meta","payload":{"id":"child-1","parent_thread_id":"main-1"}}
{"type":"response_item","payload":{"name":"exec","input":"tools.apply_patch(\"*** Begin Patch\\\\n*** Add File: $R/new.md\\\\n+x\")"}}
J
check "codex attribution with subagent" \
  "$("$P" --touched codex "$tmp/codex/2026/11/16/rollout-main.jsonl" | tr '\n' ' ')" "mine.md new.md "

# Publish: only this turn's dirty files commit; another session's staged file stays staged.
printf 'a2\n' >>"$R/mine.md"; printf 'b2\n' >>"$R/theirs.md"; git -C "$R" add theirs.md
"$P" claude abcdef123456 "$tmp/claude.jsonl"; check "publish exit" "$?" "0"
check "commit has only mine" "$(git -C "$R" show --name-only --format= HEAD | tr '\n' ' ')" "mine.md "
check "pushed" "$(git -C "$R" rev-parse HEAD)" "$(git -C "$tmp/remote.git" rev-parse HEAD)"
check "theirs still staged" "$(git -C "$R" status --porcelain theirs.md)" "M  theirs.md"
check "marker at head" "$(cat "$tmp/state/published-head")" "$(git -C "$R" rev-parse HEAD)"
before="$(git -C "$R" rev-parse HEAD)"
"$P" claude abcdef123456 "$tmp/claude.jsonl"; check "rerun is a no-op" "$(git -C "$R" rev-parse HEAD)" "$before"

# Worktree session (HOOK_CWD in a linked worktree): commits there and lands on origin, other
# uncommitted files stay put, main checkout fast-forwards. A second transcript (a subagent's
# own, own session id) publishes the same way.
export SCRIPTS="$(dirname "$P")/../.."
printf '**Class:** `personal`\n' >"$R/AGENTS.md"; git -C "$R" add AGENTS.md; git -C "$R" commit -qm class; git -C "$R" push -q origin HEAD
git -C "$R" worktree add -qb feat "$tmp/wt"; W="$(cd "$tmp/wt" && pwd -P)" # git reports real paths
printf 'w\n' >"$W/wt.md"; printf 'o\n' >"$W/other.md"; printf 'sub\n' >"$W/sub.md"
for f in wt sub; do
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s/%s.md"}}]}}\n' "$W" "$f" >"$tmp/$f.jsonl"
done
HOOK_CWD="$W" "$P" claude abcdef123456 "$tmp/wt.jsonl"; check "worktree publish exit" "$?" "0"
check "worktree commit has only wt.md" "$(git -C "$W" show --name-only --format= HEAD | tr '\n' ' ')" "wt.md "
check "worktree landed on origin" "$(git -C "$W" rev-parse HEAD)" "$(git -C "$tmp/remote.git" rev-parse HEAD)"
check "main checkout fast-forwarded" "$(git -C "$R" rev-parse HEAD)" "$(git -C "$tmp/remote.git" rev-parse HEAD)"
check "other file stays uncommitted" "$(git -C "$W" status --porcelain other.md)" "?? other.md"
check "marker at main head" "$(cat "$tmp/state/published-head")" "$(git -C "$R" rev-parse HEAD)"
HOOK_CWD="$W" "$P" claude agent-a1b2c3d4e5 "$tmp/sub.jsonl"; check "subagent transcript publish exit" "$?" "0"
check "subagent commit has only sub.md" "$(git -C "$W" show --name-only --format= HEAD | tr '\n' ' ')" "sub.md "
check "subagent landed" "$(git -C "$R" rev-parse HEAD)" "$(git -C "$tmp/remote.git" rev-parse HEAD)"

# Worktree session that also wrote a main-checkout path: the worktree file lands, the main file
# is pushed from the main checkout. A land rejected once (exit 5) is retried once.
printf 'w2\n' >>"$W/wt.md"; printf 'm\n' >>"$R/mine.md"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s"}}]}}\n' "$W/wt.md" "$R/mine.md" >"$tmp/both.jsonl"
mkdir "$tmp/stub"
printf '#!/bin/bash\n[ -e "%s/stub/once" ] || { : >"%s/stub/once"; exit 5; }\nexec "%s/land" "$@"\n' "$tmp" "$tmp" "$SCRIPTS" >"$tmp/stub/land"
chmod +x "$tmp/stub/land"
HOOK_CWD="$W" SCRIPTS="$tmp/stub" "$P" claude b0th0000 "$tmp/both.jsonl"; check "both checkouts publish exit" "$?" "0"
check "rejected land retried once" "$([ -e "$tmp/stub/once" ] && echo yes)" "yes"
check "main file pushed from main" "$(git -C "$R" show --name-only --format= HEAD | tr '\n' ' ')" "mine.md "
check "worktree file landed first" "$(git -C "$R" show --name-only --format= HEAD~1 | tr '\n' ' ')" "wt.md "
check "both on origin" "$(git -C "$R" rev-parse HEAD)" "$(git -C "$tmp/remote.git" rev-parse HEAD)"
check "both clean" "$(git -C "$R" status --porcelain mine.md)$(git -C "$W" status --porcelain wt.md)" ""

# Detached worktree: fails loud before committing; the edit stays uncommitted.
git -C "$R" worktree add -q --detach "$tmp/det"; D="$(cd "$tmp/det" && pwd -P)"
printf 'd\n' >"$D/det.md"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s/det.md"}}]}}\n' "$D" >"$tmp/det.jsonl"
before="$(git -C "$tmp/remote.git" rev-parse HEAD)"
HOOK_CWD="$D" "$P" claude de7ac4ed "$tmp/det.jsonl"; check "detached worktree fails" "$?" "1"
check "detached: edit uncommitted" "$(git -C "$D" status --porcelain det.md)" "?? det.md"
check "detached: remote unchanged" "$(git -C "$tmp/remote.git" rev-parse HEAD)" "$before"
check "detached: failure logged" "$(grep -c 'detached HEAD' "$tmp/state/publish.log")" "1"
exit $fail

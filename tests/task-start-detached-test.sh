#!/bin/sh
# task-start.sh warns once on a detached HEAD; silent on a branch, outside git, and in a branch worktree.
set -eu
root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/task-start.sh"
td="$(mktemp -d)"; trap 'rm -rf "$td"' EXIT
export TMPDIR="$td" HOME="${HOME}"
mkdir "$td/repo" "$td/plain"
git -C "$td/repo" init -q -b main
git -C "$td/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
git -C "$td/repo" worktree add -q -b feat "$td/wt"
git -C "$td/repo" worktree add -q --detach "$td/det"
run() { printf '{"session_id":"%s","cwd":"%s","prompt":"fix it"}' "$1" "$2" | bash "$hook"; }
fail() { echo "FAIL: $*"; exit 1; }
out="$(run s1 "$td/det")"
echo "$out" | grep -q "DETACHED HEAD" || fail "no warning on detached HEAD"
out="$(run s1 "$td/det")"
echo "$out" | grep -q "DETACHED HEAD" && fail "warned twice in one session"
for d in repo plain wt; do
  out="$(run "q-$d" "$td/$d")"
  echo "$out" | grep -q "DETACHED HEAD" && fail "warned in quiet case: $d"
done
echo "ok"

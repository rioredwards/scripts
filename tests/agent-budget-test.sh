#!/bin/sh
# agent-budget: normal over/under, #9 (a branch tracking origin/dev must refresh its
# split point after a rebase), #11 (commits pulled in are not "mine").
# Real git, local bare remote, throwaway repos.
set -eu

budget="$(cd "$(dirname "$0")/.." && pwd)/agent-budget"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_GLOBAL
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

fail() { echo "FAIL: $1"; exit 1; }
lines() { i=0; while [ "$i" -lt "$2" ]; do echo "$1 $i"; i=$((i + 1)); done; }
# commit <repo> <file> <nlines> : add a file of N lines and commit it
commit() { lines "$2" "$3" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -qm "$2"; }
# check <name> <repo> <want-exit> <want-text> : run status, compare exit code and output
check() {
  out="$(cd "$2" && "$budget" status 2>&1)" && rc=0 || rc=$?
  [ "$rc" -eq "$3" ] || fail "$1: exit $rc, want $3 ($out)"
  case "$out" in *"$4"*) ;; *) fail "$1: got '$out', want '$4'" ;; esac
}
# world <name>: bare remote with main+dev, "me" and "cow" clones, both on dev
world() {
  w="$tmp/$1"; mkdir -p "$w"
  git init -q --bare -b main "$w/remote.git"
  git clone -q "$w/remote.git" "$w/me" 2>/dev/null
  commit "$w/me" seed 3; git -C "$w/me" push -q origin HEAD:main
  git -C "$w/me" push -q origin HEAD:refs/heads/dev
  git clone -q -b dev "$w/remote.git" "$w/cow" 2>/dev/null
  git -C "$w/me" fetch -q; git -C "$w/me" checkout -q -b dev origin/dev 2>/dev/null
  git -C "$w/me" remote set-head origin main >/dev/null
}

# --- normal: under, then over ---------------------------------------------
world normal; me="$w/me"
(cd "$me" && "$budget" set 50 >/dev/null)
commit "$me" a 10
check "under budget" "$me" 0 "within budget: 10/50"
commit "$me" b 60
check "over budget" "$me" 1 "OVER BUDGET: 70/50"
(cd "$me" && "$budget" clear >/dev/null)
check "no budget" "$me" 3 "no budget set"

# --- #11: budget set on dev, then pull 400 lines of someone else's work ----
world pull; me="$w/me"; cow="$w/cow"
(cd "$me" && "$budget" set 100 >/dev/null)
commit "$me" mine 20
commit "$cow" theirs 400; git -C "$cow" push -q origin dev
git -C "$me" pull -q --ff-only 2>/dev/null && fail "setup: pull should diverge" || true
git -C "$me" pull -q --no-rebase --no-edit
check "pull merge keeps only mine" "$me" 0 "within budget: 20/100"
commit "$me" more 5
check "work after the pull still counts" "$me" 0 "within budget: 25/100"
commit "$me" big 90
check "own work still trips the gate" "$me" 1 "OVER BUDGET: 115/100"

# fast-forward pull of an already-pushed own commit plus theirs
world ff; me="$w/me"; cow="$w/cow"
(cd "$me" && "$budget" set 100 >/dev/null)
commit "$me" mine 30; git -C "$me" push -q origin dev
git -C "$cow" pull -q; commit "$cow" theirs 500; git -C "$cow" push -q origin dev
git -C "$me" pull -q --ff-only
check "ff pull keeps earlier own commit" "$me" 0 "within budget: 30/100"

# pull --rebase with a local commit on an own remote branch
world rebase; me="$w/me"; cow="$w/cow"
git -C "$me" checkout -q -b feat; git -C "$me" push -q -u origin feat
(cd "$me" && "$budget" set 100 >/dev/null)
commit "$me" mine 15
git -C "$cow" fetch -q; git -C "$cow" checkout -q -b feat origin/feat 2>/dev/null
commit "$cow" theirs 310; git -C "$cow" push -q origin feat
git -C "$me" pull -q --rebase
check "pull --rebase counts only the replayed commit" "$me" 0 "within budget: 15/100"

# a raise keeps what was already excluded
(cd "$me" && "$budget" set 200 >/dev/null)
check "raise keeps the pull excluded" "$me" 0 "within budget: 15/200"

# in-place history rewrite is not an arrival
world amend; me="$w/me"
(cd "$me" && "$budget" set 100 >/dev/null)
commit "$me" a 10; commit "$me" b 10
git -C "$me" reset -q --soft HEAD~2; git -C "$me" commit -qm squashed
check "squash keeps both" "$me" 0 "within budget: 20/100"

# --- #9: a branch made from origin/dev (tracks it) refreshes after a rebase --
world split; me="$w/me"; cow="$w/cow"
git -C "$me" checkout -q -b feat origin/dev 2>/dev/null
[ "$(git -C "$me" rev-parse --abbrev-ref 'feat@{upstream}')" = origin/dev ] || fail "setup: feat should track origin/dev"
(cd "$me" && "$budget" set 100 >/dev/null)
commit "$me" mine 7
commit "$cow" theirs 900; git -C "$cow" push -q origin dev
git -C "$me" fetch -q; git -C "$me" rebase -q origin/dev
# the reflog alone must not be what saves this: drop it and rely on the split point
git -C "$me" reflog expire --expire=now --all
check "tracking branch refreshes the split point" "$me" 0 "within budget: 7/100"

# working ON dev: pushed work keeps counting (the split point would swallow it)
world ondev; me="$w/me"
(cd "$me" && "$budget" set 100 >/dev/null)
commit "$me" mine 40; git -C "$me" push -q origin dev
git -C "$me" reflog expire --expire=now --all
check "on dev, pushed work still counts" "$me" 0 "within budget: 40/100"

echo "agent-budget tests: ok"

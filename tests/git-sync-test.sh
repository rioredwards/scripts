#!/usr/bin/env bash
# Exercise rebase outcomes against a real local remote, without network access.
set -eu
sync_script="$(cd "$(dirname "$0")/.." && pwd)/git-sync"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
fail() { echo "FAIL: $*"; exit 1; }

for scenario in duplicate ahead conflict; do
  root="$tmp/$scenario"
  mkdir -p "$root"
  git init -q --bare -b main "$root/remote"
  git clone -q "$root/remote" "$root/local" 2>/dev/null
  cd "$root/local"
  echo base > shared
  git add shared
  git commit -qm seed
  git push -q -u origin main
  git config branch.main.sync true
  git clone -q "$root/remote" "$root/other"

  echo changed > shared
  git add shared
  git commit -qm local
  case "$scenario" in
    duplicate) echo changed > "$root/other/shared" ;;
    ahead) echo remote > "$root/other/other-file" ;;
    conflict) echo conflicting > "$root/other/shared" ;;
  esac
  git -C "$root/other" add .
  git -C "$root/other" commit -qm remote
  git -C "$root/other" push -q
  rc=0
  bash "$sync_script" sync > "$root/output" 2>&1 || rc=$?
  if [ "$scenario" = conflict ]; then
    [ "$rc" -eq 1 ] || fail "conflict must stop with exit 1, got $rc"
    [ -n "$(git diff --name-only --diff-filter=U)" ] || fail "conflict was lost"
    [ -d .git/rebase-merge ] || fail "conflicted rebase was not preserved"
  else
    [ "$rc" -eq 0 ] || { cat "$root/output"; fail "$scenario exited $rc"; }
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "$scenario not synced"
    [ -z "$(git status --porcelain)" ] || fail "$scenario left changes"
    [ "$(cat shared)" = changed ] || fail "$scenario lost local change"
    if [ "$scenario" = ahead ]; then
      [ "$(cat other-file)" = remote ] || fail "remote change lost"
    fi
  fi
  echo "PASS: $scenario"
done

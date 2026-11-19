#!/bin/bash
# land: throwaway repos with a local bare origin; never touches a real remote.
set -u
L="$(cd "$(dirname "$0")/.." && pwd)/land"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "  ok: $1"; else echo "  FAIL: $1 (want '$3', got '$2')" >&2; fail=1; fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -C "$1" "${@:2}"; }

# mkrepo NAME CLASSLINE: repo NAME with origin NAME.git on main
mkrepo() {
  git init -q --bare -b main "$tmp/$1.git"; git init -q -b main "$tmp/$1"
  printf 'x\n' >"$tmp/$1/f"; printf '%s\n' "$2" >"$tmp/$1/AGENTS.md"
  g "$tmp/$1" add -A; g "$tmp/$1" commit -qm init
  g "$tmp/$1" remote add origin "$tmp/$1.git"; g "$tmp/$1" push -q origin main
}
R="$tmp/r"; mkrepo r '**Class:** `personal`'
g "$R" worktree add -qb feat "$tmp/wt"; W="$tmp/wt"
printf 'w\n' >"$W/w.md"; g "$W" add -A; g "$W" commit -qm work

# 1. Worktree lands on origin/main and the main checkout follows.
(cd "$W" && "$L" >/dev/null 2>&1); check "worktree land exit" "$?" "0"
check "remote has work" "$(g "$tmp/r.git" show --name-only --format= main | tr '\n' ' ')" "w.md "
check "main checkout matches" "$(g "$R" rev-parse HEAD)" "$(g "$tmp/r.git" rev-parse main)"
check "main checkout has file" "$(cat "$R/w.md")" "w"
(cd "$W" && "$L" >/dev/null 2>&1); check "second land is a no-op" "$?" "0"

# 2. Dirty tracked tree refuses unchanged; --autostash lands, keeps the edit, leaves the stash list alone.
printf 'v\n' >"$W/v.md"; g "$W" add -A; g "$W" commit -qm more
printf 'dirty\n' >>"$W/w.md"; printf 'u\n' >"$W/untracked"
before="$(g "$tmp/r.git" rev-parse main)"
(cd "$W" && "$L" >/dev/null 2>&1); check "dirty refused" "$?" "1"
check "dirty: remote unchanged" "$(g "$tmp/r.git" rev-parse main)" "$before"
printf 'other\n' >"$R/o.md"; g "$R" add o.md; g "$R" commit -qm other; g "$R" push -q origin main
stash_before="$(g "$W" stash list)"
(cd "$W" && "$L" --autostash >/dev/null 2>&1); check "autostash land exit" "$?" "0"
check "autostash: edit kept" "$(tail -1 "$W/w.md")" "dirty"
check "autostash: stash list untouched" "$(g "$W" stash list)" "$stash_before"
check "autostash: rebased onto other work" "$(g "$tmp/r.git" log --format=%s -3 main | tr '\n' ' ')" "more other work "
check "autostash: main checkout matches" "$(g "$R" rev-parse HEAD)" "$(g "$tmp/r.git" rev-parse main)"
g "$W" checkout -q -- w.md; rm "$W/untracked"

# 2b. --autostash with a dirty file origin also changed refuses up front: no conflict markers,
# nothing parked on the shared stash list, remote unchanged.
printf 'up\n' >"$R/f"; g "$R" commit -qam up; g "$R" push -q origin main
printf 'local\n' >"$W/f"; before="$(g "$tmp/r.git" rev-parse main)"
(cd "$W" && "$L" --autostash >/dev/null 2>&1); check "autostash overlap refused" "$?" "1"
check "autostash overlap: edit kept" "$(cat "$W/f")" "local"
check "autostash overlap: stash list untouched" "$(g "$W" stash list)" "$stash_before"
check "autostash overlap: remote unchanged" "$(g "$tmp/r.git" rev-parse main)" "$before"
g "$W" checkout -q -- f

# 3. Conflict: aborts, remote unchanged, branch intact, no rebase left behind.
printf 'mine\n' >"$W/c.md"; g "$W" add -A; g "$W" commit -qm mine
printf 'theirs\n' >"$R/c.md"; g "$R" add c.md; g "$R" commit -qm theirs; g "$R" push -q origin main
remote="$(g "$tmp/r.git" rev-parse main)"; head="$(g "$W" rev-parse HEAD)"
(cd "$W" && "$L" >/dev/null 2>&1); check "conflict exit" "$?" "4"
check "conflict: remote unchanged" "$(g "$tmp/r.git" rev-parse main)" "$remote"
check "conflict: branch intact" "$(g "$W" rev-parse HEAD)" "$head"
check "conflict: no rebase in progress" "$(g "$W" status | grep -c 'rebase in progress')" "0"
g "$W" reset -q --hard HEAD~1

# 4. Production and unlabeled repos refuse and change nothing on the remote.
i=0
for c in '**Class:** `production`' '**Class:** `personal-prod`' 'no class line'; do
  i=$((i + 1)); n="p$i"; mkrepo "$n" "$c"
  g "$tmp/$n" checkout -qb feat; printf 'z\n' >"$tmp/$n/z"; g "$tmp/$n" add -A; g "$tmp/$n" commit -qm z
  rem="$(g "$tmp/$n.git" rev-parse main)"
  (cd "$tmp/$n" && "$L" >/dev/null 2>&1); check "refuses: $c" "$?" "1"
  check "refuses: $c remote unchanged" "$(g "$tmp/$n.git" rev-parse main)" "$rem"
done

# 5. Main checkout: lands from main itself (nothing to fast-forward).
printf 'm\n' >"$R/m.md"; g "$R" add m.md; g "$R" commit -qm direct
(cd "$R" && "$L" >/dev/null 2>&1); check "main checkout land" "$?" "0"
check "main checkout land: pushed" "$(g "$R" rev-parse HEAD)" "$(g "$tmp/r.git" rev-parse main)"
exit $fail

#!/bin/bash
# pr-for-branch: URL/--json output, cache hit skips gh, "no PR" is empty not an
# error, real gh failures are loud and never cached, --async serves stale and
# refreshes in the background. Stubbed gh, throwaway repo.
set -eu

pfb="$(cd "$(dirname "$0")/.." && pwd)/pr-for-branch"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

repo="$tmp/repo"; mkdir -p "$repo" "$tmp/bin"
GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_GLOBAL
git -C "$repo" init -q -b feat/x
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m seed
cache="$repo/.git/statusline-pr-feat_x"

# gh stub: $GH_MODE = pr | none | fail; every call appends to $tmp/calls.
cat > "$tmp/bin/gh" <<'STUB'
#!/bin/sh
echo call >> "$GH_CALLS"
case "$GH_MODE" in
  pr) echo '{"isDraft":false,"number":7,"reviewDecision":"APPROVED","url":"https://github.com/o/r/pull/7"}' ;;
  none) echo 'no pull requests found for branch "feat/x"' >&2; exit 1 ;;
  fail) echo 'error connecting to api.github.com' >&2; exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" GH_CALLS="$tmp/calls"
calls() { if [ -e "$GH_CALLS" ]; then wc -l < "$GH_CALLS" | tr -d ' '; else echo 0; fi; }
run() { (cd "$repo" && "$pfb" "$@"); }

# no PR: empty output, exit 0, cached as none
GH_MODE=none; export GH_MODE
out=$(run) || fail "no PR exited non-zero"
[ -z "$out" ] || fail "no PR printed '$out'"
[ "$(cat "$cache")" = none ] || fail "no PR not cached as none"

# stale cache + PR: URL, and --json carries the number
touch -t 200001010000 "$cache"
GH_MODE=pr
[ "$(run)" = "https://github.com/o/r/pull/7" ] || fail "url mismatch"
n=$(calls)
[ "$(run --json | jq -r .number)" = 7 ] || fail "--json number mismatch"
[ "$(calls)" = "$n" ] || fail "cache hit still called gh"

# directory argument works from elsewhere
[ "$("$pfb" "$repo")" = "https://github.com/o/r/pull/7" ] || fail "dir arg"

# not a repo / detached HEAD: empty, exit 0
out=$(cd "$tmp" && "$pfb") || fail "non-repo exited non-zero"
[ -z "$out" ] || fail "non-repo printed '$out'"
git -C "$repo" checkout -q --detach
out=$(run) || fail "detached exited non-zero"
[ -z "$out" ] || fail "detached printed '$out'"
git -C "$repo" checkout -q feat/x

# real failure: loud, cache untouched
touch -t 200001010000 "$cache"
GH_MODE=fail
if err=$(run 2>&1 >/dev/null); then fail "gh failure exited 0"; fi
case "$err" in *"error connecting"*) ;; *) fail "stderr lost the reason: $err" ;; esac
grep -q '"number":7' "$cache" || fail "failure overwrote the cache"

# async: serves stale immediately, refreshes in the background; failure backs off
touch -t 200001010000 "$cache"; rm -f "$cache.err"
GH_MODE=none
[ "$(run --async)" = "https://github.com/o/r/pull/7" ] || fail "async should serve stale"
i=0; while [ "$(cat "$cache")" != none ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
[ "$(cat "$cache")" = none ] || fail "async never refreshed"

touch -t 200001010000 "$cache"; rm -f "$cache.err"
GH_MODE=fail; n=$(calls)
run --async >/dev/null
i=0; while [ ! -e "$cache.err" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
[ -e "$cache.err" ] || fail "async failure left no .err"
n=$(calls); run --async >/dev/null; sleep 0.3
[ "$(calls)" = "$n" ] || fail "async retried inside the backoff window"

# gh missing: loud
if err=$(PATH=/usr/bin:/bin run 2>&1); then fail "missing gh exited 0"; fi
case "$err" in *"gh not found"*) ;; *) fail "missing gh message: $err" ;; esac

echo "pr-for-branch: ok"

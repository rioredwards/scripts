#!/bin/sh
# usage-pace: weekly Claude usage -> frugal | normal | generous, with why
# (agent-skills#51). Throwaway HOME so the real cache is untouched.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
HOME="$tmp"; export HOME
p="$root/usage-pace"
cache="$tmp/.cache/agent-usage/claude-week.json"
day=86400

fail() { echo "FAIL: $1"; exit 1; }
want() { case "$2" in *"$3"*) ;; *) fail "$1: got '$2', want '$3'" ;; esac; }
# pace <used %> <seconds to reset>
pace() { "$p" record "$1" $(($(date +%s) + $2)) && "$p"; }

want "generous" "$(pace 20 $((day * 7 / 2)))" "$(printf 'generous\tweek 20%% used, 3.5 days to reset, on pace for 40%%')"
want "normal" "$(pace 45 $((day * 7 / 2)))" "$(printf 'normal\t')"
want "frugal on pace" "$(pace 60 $((day * 7 / 2)))" "frugal"
want "frugal near cap" "$(pace 91 $((day / 2)))" "frugal"
# the first day counts as a full day, so an early reading is not over-read
want "early week" "$(pace 10 $((day * 7 - 3600)))" "on pace for 70%"
want "fraction pct" "$(pace 12.6 $((day * 7 / 2)))" "week 12% used"

# no reading, a stale one, or last week's: fail with the reason
rm "$cache"
"$p" 2>"$tmp/err" && fail "no cache passed"
want "missing" "$(cat "$tmp/err")" "no weekly usage reading"
now=$(date +%s)
printf '{"pct":20,"resets_at":%s,"at":%s}' $((now + day)) $((now - 7 * 3600)) > "$cache"
"$p" 2>"$tmp/err" && fail "stale cache passed"
want "stale" "$(cat "$tmp/err")" "7h old"
printf '{"pct":20,"resets_at":%s,"at":%s}' $((now - 60)) $((now - 120)) > "$cache"
"$p" 2>"$tmp/err" && fail "pre-reset reading passed"
want "reset passed" "$(cat "$tmp/err")" "week has reset"

"$p" record 20 2>/dev/null && fail "record took one arg"
"$p" record abc $now 2>/dev/null && fail "record took a non-number"

echo "usage-pace: ok"

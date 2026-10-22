#!/bin/sh
# call-budget-lib.sh: a per-day, per-machine ceiling on paid model calls, shared
# by decisions-lib.sh and llm-lib.sh. On 2026-10-15 two one-off replays made
# about 6,000 Decisions and 1,500 Responses calls in a day (the hooks alone make
# about 600 and 150) and nothing stopped them. Every call appends one line to
# today's counter; past the cap the libs return an error instead of calling,
# which the hooks report loudly.
#
#   OPENAI_DAILY_CALL_CAP   calls per API per day (default 1500). Raise it on
#                           purpose for a replay or eval: OPENAI_DAILY_CALL_CAP=20000
#   OPENAI_CALL_COUNT_DIR   where the counters live (default ~/.cache/openai-calls);
#                           tests point it at a temp dir
#
# call_budget_take API
#   Records one call to API (decisions, responses). Prints nothing and returns 0
#   under the cap; past it, prints why and returns 1. The call is recorded
#   either way, so the counter shows how far over the day went. Each line names
#   the calling script, so the next spike can be attributed from the counter.
set -u

call_budget_take() {
  _cb_dir="${OPENAI_CALL_COUNT_DIR:-$HOME/.cache/openai-calls}"
  _cb_cap="${OPENAI_DAILY_CALL_CAP:-1500}"
  _cb_file="$_cb_dir/$(date -u +%Y-%m-%d).$1"
  mkdir -p "$_cb_dir" 2>/dev/null || { echo "cannot write call counter dir $_cb_dir"; return 1; }
  find "$_cb_dir" -maxdepth 1 -type f -mtime +14 -delete 2>/dev/null
  printf '%s %s %s\n' "$(date -u +%H:%M:%S)" "$$" "${0##*/}" >> "$_cb_file"
  _cb_n="$(wc -l < "$_cb_file" | tr -d ' ')"
  [ "$_cb_n" -le "$_cb_cap" ] && return 0
  echo "$1 daily cap: $_cb_n calls today, cap $_cb_cap (counter $_cb_file; raise OPENAI_DAILY_CALL_CAP on purpose for a replay)"
  return 1
}

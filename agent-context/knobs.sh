#!/usr/bin/env bash
# Session knobs: what Rio set for this session (attention, quality, appetite,
# tokens, reply cap) and what each value means, so the agent acts on it.
#
#   knobs.sh         the knob lines (SessionStart, via providers/30-knobs.sh)
#   knobs.sh --hook  UserPromptSubmit hook JSON, only when they changed since
#                    last injected, so a mid-session dropdown change lands on
#                    the next prompt and an unchanged one costs nothing
#
# Values come through the same loader the enforcing hooks use; AGENT_SESSION_ID
# (from the hook payload) selects this session's layer. Meanings come from
# agent-knobs.json, so the band, the CLI and the agent read one source.

set -euo pipefail

mode="${1:-}"
case "$mode" in ''|--hook) ;; *) echo "knobs.sh: unknown flag: $mode" >&2; exit 1 ;; esac
# A UserPromptSubmit hook exiting 2 blocks Rio's prompt, and jq exits 2 on a
# missing file. Fail as a plain, non-blocking error instead.
if [ "$mode" = --hook ]; then trap 'exit 1' ERR; fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stamps="$HOME/.cache/agent-knobs"

if [ "$mode" = --hook ]; then
  AGENT_SESSION_ID="$(jq -r '.session_id // empty')"
  export AGENT_SESSION_ID
fi

# shellcheck source=/dev/null
. "$root/hooks/lib/reply-cap-lib.sh"
if cap="$(reply_cap_value)"; then
  echo_cap="Reply cap: $cap prose words (fenced code excluded), $SHORT_ASK_CAP when Rio's prompt is $SHORT_ASK_WORDS words or fewer. A hook bounces anything over."
else
  echo_cap="Reply cap: off. No hook enforcement right now, stay brief anyway."
fi

# shellcheck source=/dev/null
. "$HOME/scripts/agent-hooks-env.sh"
knobs="$(jq -r '
  .knobs[] | select(.session and .name != "reply-cap")
  | ((env[.key] // "") | if . == "" then null else . end) as $set
  | ($set // .default) as $v
  | "- \(.name): \($v). \(.options[$v] // "Unknown value: agent-knobs.json gives it no meaning, ask Rio.")"
' "$root/agent-knobs.json")"

out="$echo_cap
Session knobs (Rio's picks for this session; any value but auto settles that choice, never re-ask):
$knobs"

# Remember what this session was last told. No session id (a manual run) means
# nothing to remember.
stamp=""
case "${AGENT_SESSION_ID:-}" in
  ''|*[!A-Za-z0-9_-]*) ;;
  *) stamp="$stamps/$AGENT_SESSION_ID" ;;
esac

if [ "$mode" = --hook ]; then
  [ -n "$stamp" ] || exit 0
  [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$out" ] && exit 0
  mkdir -p "$stamps" && printf '%s' "$out" > "$stamp"
  find "$stamps" -type f -mtime +30 -delete 2>/dev/null || true
  jq -nc --arg c "Knobs changed (these replace earlier knob lines):
$out" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
else
  [ -z "$stamp" ] || { mkdir -p "$stamps" && printf '%s' "$out" > "$stamp"; }
  echo "$out"
fi

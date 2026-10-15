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
# tokens=auto resolves from weekly Claude usage pace (usage-pace); Codex
# sessions keep plain auto, Claude's limits are not theirs.

set -euo pipefail

mode="${1:-}"
case "$mode" in ''|--hook) ;; *) echo "knobs.sh: unknown flag: $mode" >&2; exit 1 ;; esac
# Exit 2 would block Rio's prompt (jq exits 2 on a missing file): fail with 1.
if [ "$mode" = --hook ]; then trap 'exit 1' ERR; fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stamps="$HOME/.cache/agent-knobs"

if [ "$mode" = --hook ]; then
  payload="$(cat)"
  AGENT_SESSION_ID="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
  AGENT_TRANSCRIPT_PATH="$(printf '%s' "$payload" | jq -r '.transcript_path // empty')"
  export AGENT_SESSION_ID AGENT_TRANSCRIPT_PATH
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
pace="" pace_err=""
case "${AGENT_TRANSCRIPT_PATH:-}" in
  */.codex/*) ;;
  *) pace="$("$root/usage-pace" 2>&1)" || { pace_err="${pace#usage-pace: }"; pace=""; } ;;
esac
knobs="$(jq -r --arg pace "$pace" --arg err "$pace_err" '
  ($pace | split("\t")) as [$lvl, $why]
  | .knobs[] | select(.session and .name != "reply-cap")
  | ((env[.key] // "") | if . == "" then null else . end) as $set
  | ($set // .default) as $v
  | if .name == "tokens" and $v == "auto" and $lvl then "- tokens: auto → \($lvl) (\($why)). \(.options[$lvl])"
    elif .name == "tokens" and $v == "auto" and $err != "" then "- tokens: auto (no usage pace: \($err)). \(.options.auto)"
    else "- \(.name): \($v). \(.options[$v] // "Unknown value: agent-knobs.json gives it no meaning, ask Rio.")" end
' "$root/agent-knobs.json")"

out="$echo_cap
Session knobs (Rio's picks for this session; any value but auto settles that choice, never re-ask):
$knobs"

# Remember what this session was last told, minus the pace numbers: a new
# level re-injects, a usage percent ticking up does not. No session id (a
# manual run) means nothing to remember.
key="$(printf '%s' "$out" | sed -E '/^- tokens: auto/ s/ \([^)]*\)//')"
stamp=""
case "${AGENT_SESSION_ID:-}" in
  ''|*[!A-Za-z0-9_-]*) ;;
  *) stamp="$stamps/$AGENT_SESSION_ID" ;;
esac

if [ "$mode" = --hook ]; then
  [ -n "$stamp" ] || exit 0
  [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$key" ] && exit 0
  mkdir -p "$stamps" && printf '%s' "$key" > "$stamp"
  find "$stamps" -type f -mtime +30 -delete 2>/dev/null || true
  jq -nc --arg c "Knobs changed (these replace earlier knob lines):
$out" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
else
  [ -z "$stamp" ] || { mkdir -p "$stamps" && printf '%s' "$key" > "$stamp"; }
  echo "$out"
fi

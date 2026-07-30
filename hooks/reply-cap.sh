#!/usr/bin/env bash
# reply-cap.sh — Stop hook. Bounces a final reply that runs long.
#
# One rule, checked on every turn: prose word count, with fenced code blocks
# excluded so a legitimate snippet never trips it. No schema, no vocabulary
# files, nothing that can drift out of sync. The version this replaces enforced
# a report format that nothing ever asked an agent to produce, so it could pass
# its own tests and still never fire on a real reply.
#
#   AGENT_REPLY_MAX_WORDS   word cap, or `off` to disable (default 250)
#
# Register in the Stop array of ~/.dotfiles/.claude/settings.json:
#   { "hooks": [ { "type": "command",
#                  "command": "bash \"$HOME/scripts/hooks/reply-cap.sh\"",
#                  "timeout": 5 } ] }
# ⚠️ Never "async" — an async Stop hook cannot block a stop, so it would find
# long replies, print that nowhere, and let them through.
set -uo pipefail

[ -f "$HOME/scripts/agent-hooks-env.sh" ] && . "$HOME/scripts/agent-hooks-env.sh"

CAP="${AGENT_REPLY_MAX_WORDS:-250}"
[ "$CAP" = "off" ] && exit 0
case "$CAP" in ''|*[!0-9]*) printf 'reply-cap: AGENT_REPLY_MAX_WORDS is "%s", not a number or "off".\n' "$CAP" >&2; exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD="$(cat)"
REPLY="$(printf '%s' "$PAYLOAD" | jq -r '.last_assistant_message // empty')"
[ -n "$REPLY" ] || exit 0

# Blocked once already this turn — let it through rather than loop forever.
[ "$(printf '%s' "$PAYLOAD" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

PROSE="$(printf '%s\n' "$REPLY" | awk '/^[[:space:]]*```/{f=!f; next} !f')"
WORDS="$(printf '%s' "$PROSE" | wc -w | tr -d ' ')"
[ "$WORDS" -le "$CAP" ] && exit 0

printf 'Reply is %s words of prose; the cap is %s.\n' "$WORDS" "$CAP" >&2
printf 'Rio reads all of it, so length is his cost, not yours. Keep the outcome, what he would notice, and any decision that needs him. Cut everything else — options not taken, reasoning he did not ask for, restatements of what he just said. Then stop again.\n' >&2
exit 2

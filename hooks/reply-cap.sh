#!/usr/bin/env bash
# reply-cap.sh — Stop hook. Bounces a final reply that runs long.
#
# One rule, checked on every turn: prose word count, with fenced code blocks
# excluded so a legitimate snippet never trips it. No schema, no vocabulary
# files, nothing that can drift out of sync.
#
# Removed once (2026-08-06) because a bounce re-runs the whole Stop chain, so
# every long reply cost Rio two phone texts and two audio clips. That is fixed
# on the other side now: hooks with real side effects share the predicate in
# lib/reply-cap-lib.sh and skip the pass that is about to be rewritten. The
# chain still fires twice; each side effect happens once.
#
#   AGENT_REPLY_MAX_WORDS   word cap, or `off` to disable (default 200)
#
# Register in the Stop array of ~/.dotfiles/.claude/settings.json:
#   { "hooks": [ { "type": "command",
#                  "command": "bash \"$HOME/scripts/hooks/reply-cap.sh\"",
#                  "timeout": 5 } ] }
# ⚠️ Never "async" — an async Stop hook cannot block a stop, so it would find
# long replies, print that nowhere, and let them through.
set -uo pipefail

. "$HOME/scripts/hooks/lib/reply-cap-lib.sh"

PAYLOAD="$(cat)"
reply_will_bounce "$PAYLOAD" || exit 0

printf 'Reply is %s words of prose; the cap is %s.\n' "$REPLY_WORDS" "$REPLY_CAP" >&2
printf 'Rio reads all of it, so length is his cost, not yours. Keep the outcome, what he would notice, and any decision that needs him. Cut everything else — options not taken, reasoning he did not ask for, restatements of what he just said. Cut whole items, in plain English; never squeeze under the cap by compressing sentences into dense jargon fragments — a short reply Rio cannot read is worse than a long one. Open the retry with a `---` line and `🔄 Trimmed reply:` so Rio can tell the two apart. Then stop again.\n' >&2
exit 2

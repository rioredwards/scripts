#!/usr/bin/env bash
# response-contract-check.sh — Stop hook that holds an agent's final reply to
# the six-field response contract (see `response-contract`).
#
# The validator is a standalone CLI on purpose; this file is only the Claude
# Code adapter. Hooks are the most harness-coupled thing in the stack and this
# one is deliberately thin, so the same rules can run from Codex, a Makefile, or
# CI without being rewritten.
#
# On a violation it exits 2 with the violations on stderr, which for a Stop hook
# blocks the stop and hands the feedback back to the agent — it rewrites the
# reply and tries again. That bounce is the whole mechanism: prose asking for
# altitude decays over a session, a non-zero exit does not.
#
#   AGENT_RESPONSE_CONTRACT  off | check | require   (default off)
#     off      dormant.
#     check    validate only replies that already carry contract fields.
#              Ordinary conversation passes untouched.
#     require  every final reply must carry a contract. Strict; intended for
#              unattended/delegated runs, not for chatting.
#   AGENT_RESPONSE_CONTRACT_MAX_BOUNCES  give up after N rejections (default 2)
#
# NOT REGISTERED YET. To wire it, add this to the Stop array in
# ~/.dotfiles/.claude/settings.json:
#
#   { "hooks": [ { "type": "command",
#                  "command": "bash \"$HOME/scripts/hooks/response-contract-check.sh\"",
#                  "timeout": 10 } ] }
#
# ⚠️ Do NOT set "async": true on it. Every other Stop hook here is async, which
# is right for them — they only need to fire. An async hook cannot block a stop,
# so an async contract check would validate, find violations, print them where
# nothing reads them, and let the reply through. That is the silent-failure
# shape this whole exercise is about.
#
# Try it before registering:  AGENT_RESPONSE_CONTRACT=check claude ...
# (the toggle alone does nothing until the hook is in settings.json)
set -uo pipefail

[ -f "$HOME/scripts/agent-hooks-env.sh" ] && . "$HOME/scripts/agent-hooks-env.sh"

MODE="${AGENT_RESPONSE_CONTRACT:-off}"
[ "$MODE" = "check" ] || [ "$MODE" = "require" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

VALIDATOR="${SCRIPTS:-$HOME/scripts}/response-contract"
if [ ! -x "$VALIDATOR" ]; then
  printf '⚠️ AGENT_RESPONSE_CONTRACT is %s but the validator is missing — replies are NOT being checked.\n' "$MODE" >&2
  exit 0
fi

PAYLOAD="$(cat)"
REPLY="$(printf '%s' "$PAYLOAD" | jq -r '.last_assistant_message // empty')"
[ -n "$REPLY" ] || exit 0

# Re-entry guard. Claude sets stop_hook_active when the stop was already blocked
# once; blocking again from inside that state is how a hook turns into an
# infinite rewrite loop. Belt and braces: a per-session bounce budget, so a
# reply the agent simply cannot get right costs a couple of retries rather than
# the whole session.
STOP_ACTIVE="$(printf '%s' "$PAYLOAD" | jq -r '.stop_hook_active // false')"
SESSION_ID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "unknown"')"
STATE_DIR="${TMPDIR:-/tmp}/claude-response-contract"
mkdir -p "$STATE_DIR"
find "$STATE_DIR" -type f -mtime +1 -delete 2>/dev/null
BOUNCE_FILE="$STATE_DIR/${SESSION_ID}.bounces"
BOUNCES="$(cat "$BOUNCE_FILE" 2>/dev/null || echo 0)"
MAX_BOUNCES="${AGENT_RESPONSE_CONTRACT_MAX_BOUNCES:-2}"

VIOLATIONS="$(printf '%s' "$REPLY" | "$VALIDATOR" 2>&1 >/dev/null)"
RC=$?

case "$RC" in
  0) : > "$BOUNCE_FILE"; exit 0 ;;                      # clean reply — reset the budget
  3) [ "$MODE" = "require" ] || exit 0 ;;               # no contract; only strict mode cares
  2) # No enum, or a broken one. Say so once and get out of the way — a
     # misconfigured validator must not hold the session hostage.
     printf '⚠️ response-contract is misconfigured, so replies are NOT being checked:\n%s\n' "$VIOLATIONS" >&2
     exit 0 ;;
esac

if [ "$STOP_ACTIVE" = "true" ]; then
  printf '⚠️ Response contract unmet, but the stop was already blocked once — letting it through rather than looping.\n' >&2
  : > "$BOUNCE_FILE"
  exit 0
fi
if [ "$BOUNCES" -ge "$MAX_BOUNCES" ]; then
  printf '⚠️ Response contract still unmet after %s rewrite attempt(s) — letting it through. Not silent, just not blocking.\n' "$BOUNCES" >&2
  : > "$BOUNCE_FILE"
  exit 0
fi

printf '%s' "$(( BOUNCES + 1 ))" > "$BOUNCE_FILE"

if [ "$RC" = "3" ]; then
  printf '❌ RESPONSE CONTRACT REQUIRED — this reply carries no contract.\n' >&2
  printf 'Restate the outcome in the six fields, then stop.\n' >&2
else
  printf '%s\n' "$VIOLATIONS" >&2
fi
printf '\nRewrite the final reply so it satisfies the contract, then stop again. (Attempt %s of %s.)\n' \
  "$(( BOUNCES + 1 ))" "$MAX_BOUNCES" >&2
exit 2

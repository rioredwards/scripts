#!/bin/sh
# reply-cap-lib.sh — shared brains for the reply-length cap.
#
# Two hooks need the same answer to one question: "is this reply about to be
# bounced for length?" reply-cap.sh asks so it can block. The note-on-turn
# adapter asks so it can skip a turn that is about to be rewritten — otherwise
# a bounced reply costs Rio two phone texts, two audio clips and two summarizer
# runs, which is exactly why the cap got removed the first time.
#
# Stateless on purpose. Both hooks compute the same predicate from the same
# payload, so there is no marker file to coordinate, no ordering requirement,
# and nothing to clean up when a turn dies mid-flight.
#
#   AGENT_REPLY_MAX_WORDS   word cap, or `off` to disable (default 200)
set -u

# The cap, or empty when disabled / nonsense / jq missing.
reply_cap_value() {
  [ -f "$HOME/scripts/agent-hooks-env.sh" ] && . "$HOME/scripts/agent-hooks-env.sh"
  cap="${AGENT_REPLY_MAX_WORDS:-200}"
  [ "$cap" = "off" ] && return 1
  case "$cap" in ''|*[!0-9]*) return 1 ;; esac
  command -v jq >/dev/null 2>&1 || return 1
  printf '%s' "$cap"
}

# Prose words in a reply, fenced code blocks excluded so a legitimate snippet
# never trips the cap.
reply_prose_words() {
  printf '%s\n' "$1" | awk '/^[[:space:]]*```/{f=!f; next} !f' | wc -w | tr -d ' '
}

# True when this reply will be bounced: over cap, and not already the rewrite.
# stdin-free — pass the raw hook payload as $1.
reply_will_bounce() {
  payload="$1"

  # The cap prices Rio's reading time. A delegate's reply is another agent's
  # input, not Rio's reading — it must arrive whole.
  . "$HOME/scripts/hooks/lib/delegate.sh"
  hook_is_delegate "$payload" && return 1

  cap="$(reply_cap_value)" || return 1

  # No cap hook registered means nobody will ask for a rewrite, so callers must
  # not skip work waiting on one that never comes.
  grep -q 'reply-cap' "$HOME/.claude/settings.json" "$HOME/.codex/hooks.json" 2>/dev/null || return 1

  # Already bounced once this turn — the cap lets it through, so does everyone.
  [ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')" = "true" ] && return 1

  reply="$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty')"
  [ -n "$reply" ] || return 1

  words="$(reply_prose_words "$reply")"
  [ "$words" -gt "$cap" ] || return 1

  REPLY_WORDS="$words"
  REPLY_CAP="$cap"
  return 0
}

# --- rules.json response rules -----------------------------------------------
#
# `hooks/rules/run.sh response` bounces a reply that trips an `on: response`
# rule. It is a second reason a turn gets rewritten, so it needs the same
# skip-this-pass treatment the length cap gets.

# True when a response rule will bounce this reply. Delegates to run.sh instead
# of re-reading rules.json, so the matching logic lives in exactly one place and
# cannot drift from what actually fires.
reply_rules_will_bounce() {
  payload="$1"
  runner="${AGENT_RULES_RUNNER:-$HOME/scripts/hooks/rules/run.sh}"
  [ -r "$runner" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  # Not registered on Stop means nobody will ask for a rewrite, so callers must
  # not skip work waiting on one that never comes. Same guard as the cap's.
  registered=1
  for f in "$HOME/.claude/settings.json" "$HOME/.codex/hooks.json"; do
    jq -e '[.hooks.Stop[]?.hooks[]?.command] | any(test("rules/run\\.sh.*response"))' \
      "$f" >/dev/null 2>&1 && { registered=0; break; }
  done
  [ "$registered" -eq 0 ] || return 1

  # run.sh exits 2 exactly when it bounces, and already returns 0 on the
  # rewrite pass (stop_hook_active), so no second guard is needed here.
  printf '%s' "$payload" | sh "$runner" response >/dev/null 2>&1
  [ "$?" -eq 2 ]
}

# True when this reply is about to be rewritten for ANY reason — over the length
# cap, or tripping a response rule. This is the predicate a hook with real side
# effects wants; `reply_will_bounce` alone now covers only half the reasons.
reply_will_be_rewritten() {
  reply_will_bounce "$1" && return 0
  reply_rules_will_bounce "$1"
}

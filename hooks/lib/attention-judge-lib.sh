#!/bin/sh
# attention-judge-lib.sh: does this reply deserve Rio's attention as written?
#
# OpenAI's Decisions API (/v1/decisions, gpt-6-luna) answers three yes/no
# questions about the final reply, each as a probability. Over its threshold,
# the reply would bounce back for a rewrite (agent-skills#48).
#
# Watch mode (the default) only logs: calibration on 80 real replies found no
# threshold that catches bad replies without bouncing good ones, so bouncing
# waits on Rio rating a week of logged verdicts.
#
# A model verdict is not repeatable, so the first caller stores it per reply
# and any later caller reads it: one API call, one answer. A bouncing judge
# needs this so the turn-end adapters can skip a pass about to be rewritten.
#
#   AGENT_ATTENTION_JUDGE   watch | bounce | off (default watch)
#
# judge_verdict prints one line: skip | pass | bounce <names> | error <why>
set -u

JUDGE_THRESHOLDS='{"needless_ask":0.8,"unclear":0.8,"noise":0.8}'
JUDGE_LOG="${JUDGE_LOG:-$HOME/.cache/attention-judge/verdicts.jsonl}"

. "$HOME/scripts/hooks/lib/reply-cap-lib.sh"
. "$HOME/scripts/hooks/lib/decisions-lib.sh"

_judge_questions() {
  jq -n '[
    {name:"needless_ask", instructions:"True if the AGENT REPLY asks Rio to decide or answer something the agent could settle itself (an obvious, standard, or easily reversed engineering call it could look up or just make) or could safely defer. False if it asks nothing, or the decision is genuinely his: hard to undo, risky (merging, losing work, spending money, production data), or a product or taste call with no standard answer."},
    {name:"unclear", instructions:"True if a busy reader skimming the AGENT REPLY once would struggle to tell what happened and what, if anything, they must do: jargon where plain words would do, file, branch, or function names instead of what they mean, a decision buried mid-text, or vague about what matters (how big, what changes for him). False if it is plain and the point comes first."},
    {name:"noise", instructions:"True if a meaningful part of the AGENT REPLY spends his attention on things he does not need: restating his own request back, narrating steps taken, listing options considered and rejected, or tacking on offers, ideas, or next tasks he did not ask for. A one-line flag of a bug, risk, or design problem the agent noticed is not noise. False if nearly every sentence carries the outcome, what he would notice, a decision he must make, or a noticed problem flagged in one line."}
  ]'
}

_judge_input() {
  printf 'Rio is a solo developer. AI agents write his code; he steers at the decision level and his attention is his scarcest resource. Judge only the AGENT REPLY.\n\nRIO LATEST MESSAGE:\n%s\n\nAGENT REPLY:\n%s\n' "$1" "$2"
}

# Every verdict, errors included, lands in the log Rio's ratings are drawn from.
_judge_log() { # verdict ms probabilities-json
  mkdir -p "$(dirname "$JUDGE_LOG")"
  jq -nc --arg s "$session" --arg p "$prompt" --arg r "$reply" --arg v "$1" \
    --argjson ms "$2" --argjson a "$3" \
    '{ts:(now|todate), session:$s, verdict:$v, ms:$ms, p:$a, prompt:$p, reply:$r}' \
    >> "$JUDGE_LOG" 2>/dev/null
  echo "$1"
}

# One API call. Prints `pass`, `bounce <names>`, or `error <why>`; logs it.
_judge_call() {
  prompt="$1"; reply="$2"; session="$3"
  res="$(decisions_ask "$(_judge_input "$prompt" "$reply")" "$(_judge_questions)" 4)"
  verdict="$(decisions_over "$res" "$JUDGE_THRESHOLDS")"
  case "$verdict" in
    over*) verdict="bounce ${verdict#over }" ;;
    refused*) verdict="error refusal on ${verdict#refused }" ;;
  esac
  _judge_log "$verdict" "$(printf '%s' "$res" | jq '.ms // 0')" "$(printf '%s' "$res" | jq -c '.p // null')"
}

judge_verdict() {
  payload="$1"
  [ -f "$HOME/scripts/agent-hooks-env.sh" ] && . "$HOME/scripts/agent-hooks-env.sh"
  [ "${AGENT_ATTENTION_JUDGE:-watch}" = off ] && { echo skip; return; }
  reply="$(reply_for_review "$payload")" || { echo skip; return; }
  session="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
  reply_once attention-judge "$session" "$reply" 6 \
    _judge_call "$(reply_last_prompt "$payload" commands)" "$reply" "$session" \
    || echo "error timed out waiting for another caller's verdict"
}


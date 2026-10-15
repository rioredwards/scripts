#!/bin/sh
# attention-judge-lib.sh: does this reply deserve Rio's attention as written?
#
# OpenAI's Decisions API (/v1/decisions, gpt-6-luna) answers three yes/no
# questions about the final reply, each as a probability. Over its threshold,
# the reply bounces back for a rewrite (agent-skills#48).
#
# Two hooks ask: attention-judge.sh (to bounce) and the turn-end adapters (to
# skip a pass that is about to be rewritten). A model verdict is not
# repeatable, so the first caller stores it per reply and the second reads it:
# one API call, one answer, whoever runs first.
#
#   AGENT_ATTENTION_JUDGE   on | off (default on)
#
# judge_verdict prints one line: skip | pass | bounce <names> | error <why>
set -u

JUDGE_MODEL=gpt-6-luna
JUDGE_URL="${JUDGE_URL:-https://api.openai.com/v1/decisions}"
JUDGE_THRESHOLD_needless_ask=0.8
JUDGE_THRESHOLD_unclear=0.8
JUDGE_THRESHOLD_noise=0.8
JUDGE_LOG="${JUDGE_LOG:-$HOME/.cache/attention-judge/verdicts.jsonl}"

# Codex fires Stop for its prompt-suggestion pass too; the "reply" is a JSON
# suggestion Rio never reads as a message.
reply_is_suggestion() {
  printf '%s' "$1" | grep -Eq '^[[:space:]]*\{"suggestion":'
}

_judge_questions() {
  jq -n '[
    {type:"predicate", name:"needless_ask", instructions:"True if the AGENT REPLY asks Rio to decide or answer something the agent could settle itself (an obvious, standard, or easily reversed engineering call it could look up or just make) or could safely defer. False if it asks nothing, or the decision is genuinely his: hard to undo, risky (merging, losing work, spending money, production data), or a product or taste call with no standard answer."},
    {type:"predicate", name:"unclear", instructions:"True if a busy reader skimming the AGENT REPLY once would struggle to tell what happened and what, if anything, they must do: jargon where plain words would do, file, branch, or function names instead of what they mean, a decision buried mid-text, or vague about what matters (how big, what changes for him). False if it is plain and the point comes first."},
    {type:"predicate", name:"noise", instructions:"True if a meaningful part of the AGENT REPLY spends his attention on things he does not need: restating his own request back, narrating steps taken, listing options considered and rejected, or tacking on offers, ideas, or next tasks he did not ask for. False if nearly every sentence carries the outcome, what he would notice, or a decision he must make."}
  ]'
}

_judge_input() {
  printf 'Rio is a solo developer. AI agents write his code; he steers at the decision level and his attention is his scarcest resource. Judge only the AGENT REPLY.\n\nRIO LATEST MESSAGE:\n%s\n\nAGENT REPLY:\n%s\n' "$1" "$2"
}

# One API call. Prints `pass`, `bounce <names>`, or `error <why>`; logs it.
_judge_call() {
  prompt="$1"; reply="$2"; session="$3"
  key="$(keyfor OPENAI_API_KEY 2>/dev/null)" || { echo "error keyfor OPENAI_API_KEY failed"; return; }
  body="$(jq -n --arg m "$JUDGE_MODEL" --arg i "$(_judge_input "$prompt" "$reply")" \
    --argjson q "$(_judge_questions)" '{model:$m, input:$i, questions:$q}')"
  start="$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')"
  resp="$(printf '%s' "$body" | curl -sS --max-time 4 -w '\n%{http_code}' "$JUDGE_URL" \
    -H "Authorization: Bearer $key" -H 'Content-Type: application/json' -d @- 2>&1)" || {
    echo "error $(printf '%s' "$resp" | head -n 1 | cut -c1-120)"; return; }
  ms=$(( $(perl -MTime::HiRes=time -e 'printf "%d", time*1000') - start ))
  code="$(printf '%s' "$resp" | tail -n 1)"
  json="$(printf '%s' "$resp" | sed '$d')"
  if [ "$code" != 200 ]; then
    echo "error HTTP $code $(printf '%s' "$json" | jq -r '.error.message // empty' 2>/dev/null | cut -c1-120)"
    return
  fi
  verdict="$(printf '%s' "$json" | jq -r \
    --argjson t "{\"needless_ask\":$JUDGE_THRESHOLD_needless_ask,\"unclear\":$JUDGE_THRESHOLD_unclear,\"noise\":$JUDGE_THRESHOLD_noise}" '
    (.answers // []) as $a
    | if ($a | length) != 3 then "error expected 3 answers, got \($a | length)"
      elif ($a | any(.type != "predicate")) then "error refusal on \($a | map(select(.type != "predicate") | .name) | join(","))"
      else ($a | map(select(.probability >= $t[.name])) | map(.name)) as $hit
        | if ($hit | length) == 0 then "pass" else "bounce " + ($hit | join(",")) end
      end' 2>/dev/null)" || verdict="error unreadable response"
  mkdir -p "$(dirname "$JUDGE_LOG")"
  jq -nc --arg s "$session" --arg p "$prompt" --arg r "$reply" --arg v "$verdict" \
    --argjson ms "$ms" --argjson a "$(printf '%s' "$json" | jq -c '.answers // []' 2>/dev/null || echo '[]')" \
    '{ts:(now|todate), session:$s, verdict:$v, ms:$ms, p:($a|map({(.name):.probability})|add), prompt:$p, reply:$r}' \
    >> "$JUDGE_LOG" 2>/dev/null
  echo "$verdict"
}

judge_verdict() {
  payload="$1"
  [ -f "$HOME/scripts/agent-hooks-env.sh" ] && . "$HOME/scripts/agent-hooks-env.sh"
  [ "${AGENT_ATTENTION_JUDGE:-on}" = off ] && { echo skip; return; }
  . "$HOME/scripts/hooks/lib/delegate.sh"
  hook_is_delegate "$payload" && { echo skip; return; }
  [ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')" = true ] && { echo skip; return; }
  reply="$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty')"
  [ -n "$reply" ] || { echo skip; return; }
  reply_is_suggestion "$reply" && { echo skip; return; }

  session="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
  dir="${TMPDIR:-/tmp}/attention-judge"; mkdir -p "$dir"
  id="$(printf '%s\n%s' "$session" "$reply" | shasum -a 256 | cut -c1-32)"
  out="$dir/$id"
  if mkdir "$out.lock" 2>/dev/null; then
    . "$HOME/scripts/hooks/lib/reply-cap-lib.sh"
    _judge_call "$(reply_last_prompt "$payload")" "$reply" "$session" > "$out.tmp"
    mv "$out.tmp" "$out"
  else
    n=0
    while [ ! -f "$out" ] && [ "$n" -lt 60 ]; do sleep 0.1; n=$((n + 1)); done
  fi
  [ -f "$out" ] && cat "$out" || echo "error timed out waiting for another caller's verdict"
}

# For side-effect hooks: true when attention-judge.sh will bounce this reply.
reply_judge_will_bounce() {
  jq -e '[.hooks.Stop[]?.hooks[]?.command] | any(test("attention-judge"))' \
    "$HOME/.claude/settings.json" >/dev/null 2>&1 \
    || jq -e '[.hooks.Stop[]?.hooks[]?.command] | any(test("attention-judge"))' \
    "$HOME/.codex/hooks.json" >/dev/null 2>&1 || return 1
  case "$(judge_verdict "$1")" in bounce*) return 0 ;; *) return 1 ;; esac
}

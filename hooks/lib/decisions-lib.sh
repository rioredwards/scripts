#!/bin/sh
# decisions-lib.sh: the one client for OpenAI's Decisions API (/v1/decisions).
# It answers yes/no questions about a text, each as a probability, with no
# reason. Typical latency well under 1s. Shared by every hook that judges with
# it (attention-judge, spin-check), so the key, endpoint, timeout and error
# handling live here once.
#
#   DECISIONS_URL   endpoint (default OpenAI; tests point it at a stub)
#   Every call counts against the daily cap in call-budget-lib.sh; past it the
#   call is not made and the result is an error naming the cap.
#
# decisions_ask INPUT QUESTIONS_JSON [MAX_SECS]
#   QUESTIONS_JSON: [{name, instructions}, ...] (sent as predicates)
#   Prints one JSON line: {"ms":N,"p":{name:probability,...},"refused":[name,...]}
#   or {"ms":N,"error":"why"}. A refused question has no probability; the
#   model declines a few inputs (about 1 in 25 in spin-check replays), so a
#   refusal is per input, not a broken API. A missing answer is an error.
# decisions_over RESULT THRESHOLDS_JSON
#   Prints `over <name,name>` (any answered question at or over its threshold),
#   else `refused <name,name>`, else `pass`; or `error <why>`. Each caller
#   decides what a refusal means.
set -u

. "$HOME/scripts/hooks/lib/call-budget-lib.sh"

DECISIONS_MODEL=gpt-6-luna
DECISIONS_URL="${DECISIONS_URL:-https://api.openai.com/v1/decisions}"

_decisions_ms() { perl -MTime::HiRes=time -e 'printf "%d", time*1000'; }

decisions_ask() {
  _d_start="$(_decisions_ms)"
  _d_err() { jq -nc --arg e "$1" --argjson ms "$(( $(_decisions_ms) - _d_start ))" '{ms:$ms, error:$e}'; }
  _d_over="$(call_budget_take decisions)" || { _d_err "$_d_over"; return; }
  _d_key="$(keyfor OPENAI_API_KEY 2>/dev/null)" || { _d_err "keyfor OPENAI_API_KEY failed"; return; }
  _d_body="$(jq -n --arg m "$DECISIONS_MODEL" --arg i "$1" --argjson q "$2" \
    '{model:$m, input:$i, questions:($q | map({type:"predicate"} + .))}')"
  _d_resp="$(printf '%s' "$_d_body" | curl -sS --max-time "${3:-4}" -w '\n%{http_code}' "$DECISIONS_URL" \
    -H "Authorization: Bearer $_d_key" -H 'Content-Type: application/json' -d @- 2>&1)" || {
    _d_err "$(printf '%s' "$_d_resp" | head -n 1 | cut -c1-120)"; return; }
  _d_ms=$(( $(_decisions_ms) - _d_start ))
  _d_code="$(printf '%s' "$_d_resp" | tail -n 1)"
  _d_json="$(printf '%s' "$_d_resp" | sed '$d')"
  if [ "$_d_code" != 200 ]; then
    _d_err "HTTP $_d_code $(printf '%s' "$_d_json" | jq -r '.error.message // empty' 2>/dev/null | cut -c1-120)"
    return
  fi
  printf '%s' "$_d_json" | jq -c --argjson ms "$_d_ms" --argjson q "$2" '
    (.answers // []) as $a
    | if ($a | length) != ($q | length) then {ms:$ms, error:"expected \($q | length) answers, got \($a | length)"}
      else {ms:$ms, p:($a | map(select(.type == "predicate") | {(.name):.probability}) | add // {}),
            refused:($a | map(select(.type != "predicate") | .name))} end' 2>/dev/null \
    || _d_err "unreadable response"
}

decisions_over() {
  printf '%s' "$1" | jq -r --argjson t "$2" '
    if .error then "error " + .error
    else [.p | to_entries[] | select(.value >= $t[.key]) | .key] as $hit
      | if ($hit | length) > 0 then "over " + ($hit | join(","))
        elif ((.refused // []) | length) > 0 then "refused " + (.refused | join(","))
        else "pass" end
    end' 2>/dev/null || echo "error unreadable result"
}

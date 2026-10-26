#!/bin/sh
# llm-lib.sh: the one client for a short structured answer from an OpenAI model
# (Responses API, strict JSON schema, no reasoning). Sibling of decisions-lib.sh:
# Decisions screens cheaply with a probability and no reason; this answers with
# quoted evidence when a screen needs a second look. Key, endpoint, timeout and
# error handling live here once.
#
#   LLM_URL   endpoint (default OpenAI; tests point it at a stub)
#   Every call counts against the daily cap in call-budget-lib.sh; past it the
#   call is not made and the result is an error naming the cap.
#
# llm_json MODEL INSTRUCTIONS INPUT PROPS_JSON [MAX_SECS] [BUCKET] [STORE]
#   PROPS_JSON: {name: json-schema, ...}; every property is required.
#   BUCKET: the call-budget counter to charge (default responses).
#   STORE: optional false to disable API storage; omitted retains API default.
#   Prints one JSON line: {"ms":N,"out":{...}} or {"ms":N,"error":"why"}.
set -u

. "$HOME/scripts/hooks/lib/call-budget-lib.sh"

LLM_URL="${LLM_URL:-https://api.openai.com/v1/responses}"

_llm_ms() { perl -MTime::HiRes=time -e 'printf "%d", time*1000'; }

llm_json() {
  _l_start="$(_llm_ms)"
  _l_err() { jq -nc --arg e "$1" --argjson ms "$(( $(_llm_ms) - _l_start ))" '{ms:$ms, error:$e}'; }
  _l_over="$(call_budget_take "${6:-responses}")" || { _l_err "$_l_over"; return; }
  _l_key="$(keyfor OPENAI_API_KEY 2>/dev/null)" || { _l_err "keyfor OPENAI_API_KEY failed"; return; }
  _l_body="$(jq -n --arg m "$1" --arg s "$2" --arg i "$3" --argjson p "$4" --arg store "${7:-}" '
    {model:$m, instructions:$s, input:$i, max_output_tokens:1000, reasoning:{effort:"none"},
     text:{format:{type:"json_schema", name:"answer", strict:true,
       schema:{type:"object", additionalProperties:false, required:($p | keys_unsorted), properties:$p}}}}
    | if $store == "false" then .store = false else . end')"
  _l_resp="$(printf '%s' "$_l_body" | curl -sS --max-time "${5:-8}" -w '\n%{http_code}' "$LLM_URL" \
    -H "Authorization: Bearer $_l_key" -H 'Content-Type: application/json' -d @- 2>&1)" || {
    _l_err "$(printf '%s' "$_l_resp" | head -n 1 | cut -c1-120)"; return; }
  _l_ms=$(( $(_llm_ms) - _l_start ))
  _l_code="$(printf '%s' "$_l_resp" | tail -n 1)"
  _l_json="$(printf '%s' "$_l_resp" | sed '$d')"
  if [ "$_l_code" != 200 ]; then
    _l_err "HTTP $_l_code $(printf '%s' "$_l_json" | jq -r '.error.message // empty' 2>/dev/null | cut -c1-120)"
    return
  fi
  printf '%s' "$_l_json" | jq -c --argjson ms "$_l_ms" '
    [.output[]? | select(.type == "message") | .content[]? | select(.type == "output_text") | .text] | join("")
    | if . == "" then {ms:$ms, error:"no answer text"} else {ms:$ms, out:fromjson} end' 2>/dev/null \
    || _l_err "unreadable response"
}

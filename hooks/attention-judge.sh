#!/usr/bin/env bash
# attention-judge.sh: Stop hook. An outside model judges whether the final
# reply deserves Rio's attention as written. Watch mode logs the verdict only;
# bounce mode sends a failing reply back once.
#
# Questions and thresholds live in lib/attention-judge-lib.sh. Verdicts and
# probabilities land in ~/.cache/attention-judge/verdicts.jsonl for
# re-calibration.
#
# When OpenAI fails (error, timeout, refusal), the reply goes through and Rio
# sees a warning line on every failed turn (Claude: the agent relays it next
# turn). Approved on agent-skills#48: loud, but an outage never stalls every
# session on both Macs.
#
#   AGENT_ATTENTION_JUDGE   watch | bounce | off (default watch)
#
# Registered async and last in the Stop array (Claude settings, Codex
# hooks.json), so watching adds no wait. Codex trusts hooks by position: a new
# one goes last, then gets trusted in Codex's /hooks. ⚠️ Bounce mode needs a
# blocking registration (timeout 6, not async) and reply_will_be_rewritten
# wired to the stored verdict.
set -uo pipefail

. "$HOME/scripts/hooks/lib/attention-judge-lib.sh"

PAYLOAD="$(cat)"
verdict="$(judge_verdict "$PAYLOAD")"

case "$verdict" in
  skip|pass) exit 0 ;;
  bounce*) [ "${AGENT_ATTENTION_JUDGE:-watch}" = bounce ] || exit 0 ;;
  error*)
    # Async: Claude hands systemMessage to the agent, not Rio, so it asks for a relay.
    jq -nc --arg m "⚠️ attention-judge failed, reply not judged: ${verdict#error }. Agent: tell Rio this in one line." \
      '{systemMessage:$m}'
    exit 0 ;;
esac

names=",${verdict#bounce },"
printf 'The attention judge bounced this reply before Rio saw it.\n' >&2
case "$names" in *,needless_ask,*)
  printf -- '- It asks Rio something you could decide yourself (obvious, standard, or reversible) or defer. Make the call, act on it, report it in one line. Ask only when it is hard to undo, risky, or pure taste, with a `Why you:` line.\n' >&2 ;; esac
case "$names" in *,unclear,*)
  printf -- '- It is hard to follow on one skim. Lead with the outcome or the ask, in plain words; name things by what they mean to Rio, not file or branch names; say how big a deal it is.\n' >&2 ;; esac
case "$names" in *,noise,*)
  printf -- '- It spends his attention on things he does not need: restating his request, narrating steps, rejected options, offers or next tasks he did not ask for. Cut them. If the work is done, say done and stop.\n' >&2 ;; esac
printf 'If the judge is wrong, send the same reply again; it only bounces once. Open the retry with a `---` line and `\xf0\x9f\x94\x84 Revised reply:` so Rio can tell the two apart. Then stop again.\n' >&2
exit 2

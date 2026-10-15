#!/usr/bin/env bash
# attention-judge.sh: Stop hook. An outside model judges whether the final
# reply deserves Rio's attention as written; if not, the reply bounces once.
#
# Questions and thresholds live in lib/attention-judge-lib.sh. Verdicts and
# probabilities land in ~/.cache/attention-judge/verdicts.jsonl for
# re-calibration.
#
# When OpenAI fails (error, timeout, refusal), the reply goes through and Rio
# sees a warning line on every failed turn. Approved on agent-skills#48: loud,
# but an outage never stalls every session on both Macs.
#
#   AGENT_ATTENTION_JUDGE   on | off (default on)
#
# Register in the Stop array (Claude settings, Codex hooks.json), timeout 6.
# ⚠️ Never "async": an async Stop hook cannot block a stop.
set -uo pipefail

. "$HOME/scripts/hooks/lib/attention-judge-lib.sh"

PAYLOAD="$(cat)"
verdict="$(judge_verdict "$PAYLOAD")"

case "$verdict" in
  skip|pass) exit 0 ;;
  error*)
    jq -nc --arg m "⚠️ attention-judge failed, reply not judged: ${verdict#error }" '{systemMessage:$m}'
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

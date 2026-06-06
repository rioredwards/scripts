#!/usr/bin/env bash
# claude-token-audit.sh — show where Claude Code token/quota burn went.
#
# Scans ~/.claude/projects/**/*.jsonl, sums token usage per session for
# messages inside a time window, and cost-weights each so you can see what
# actually ate your 5h limit (the limit tracks ~cost, not raw tokens, and
# Opus weighs ~15-20x Haiku per token).
#
# Usage:
#   claude-token-audit.sh [MINUTES]   # default 300 (the 5h rolling window)
#
# Notes:
#   - Cost is an ESTIMATE using public per-Mtok prices; it mirrors how the
#     limit weights models, not your exact bill.
#   - macOS `date` only (uses -v). Rio's machine is darwin.

set -euo pipefail

MINS="${1:-300}"
ROOT="${CLAUDE_PROJECTS:-$HOME/.claude/projects}"
CUTOFF="$(date -v-"${MINS}"M +%s)"

[ -d "$ROOT" ] || { echo "no project dir: $ROOT" >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Per-file aggregation. One JSON object per session emitted to $tmp.
find "$ROOT" -name '*.jsonl' -mmin -"$MINS" 2>/dev/null | while read -r f; do
  jq -s --argjson cutoff "$CUTOFF" --arg f "$f" '
    def price(m):
      if   (m|test("opus"))   then {in:15,  cw:18.75, cr:1.5,  out:75}
      elif (m|test("sonnet")) then {in:3,   cw:3.75,  cr:0.30, out:15}
      elif (m|test("haiku"))  then {in:1,   cw:1.25,  cr:0.10, out:5}
      else {in:0,cw:0,cr:0,out:0} end;
    [ .[]
      | select(.message.usage != null and .timestamp != null)
      | select((.timestamp | sub("\\.[0-9]+";"") | fromdateiso8601) >= $cutoff)
    ] as $rows
    | if ($rows|length) == 0 then empty else
      { file:   $f,
        msgs:   ($rows|length),
        models: ($rows|map(.message.model)|unique),
        in:     ($rows|map(.message.usage.input_tokens // 0)|add),
        cc:     ($rows|map(.message.usage.cache_creation_input_tokens // 0)|add),
        cr:     ($rows|map(.message.usage.cache_read_input_tokens // 0)|add),
        out:    ($rows|map(.message.usage.output_tokens // 0)|add),
        cost:   ($rows|map(
                   .message.usage as $u | price(.message.model) as $p
                   | ( ($u.input_tokens // 0)                * $p.in
                     + ($u.cache_creation_input_tokens // 0) * $p.cw
                     + ($u.cache_read_input_tokens // 0)     * $p.cr
                     + ($u.output_tokens // 0)               * $p.out
                     ) / 1e6 ) | add)
      } end' "$f"
done > "$tmp"

if ! [ -s "$tmp" ]; then
  echo "no sessions with usage in last ${MINS}m."
  exit 0
fi

{
  printf 'COST$\t%%\tMODEL\tMSGS\tIN\tCACHE_W\tCACHE_R\tOUT\tSESSION\n'
  jq -rs '
    sort_by(-.cost)
    | (map(.cost)|add) as $T
    | ( .[]
        | [ (.cost*100|round/100),
            (if $T>0 then (.cost/$T*100|round) else 0 end),
            (.models|map(sub("claude-";"")|sub("-[0-9].*$";""))|unique|join(",")),
            .msgs, .in, .cc, .cr, .out,
            ((.file|split("/")|.[-2]) + "/" + (.file|split("/")|.[-1]|.[0:8]))
          ] | @tsv ),
      ( "—\t—\t—\t—\t—\t—\t—\t—\t—" ),
      ( [ ($T*100|round/100), 100, "TOTAL", "", "", "", "", "", "" ] | @tsv )
  ' "$tmp"
} | column -t -s "$(printf '\t')"

echo
echo "window: last ${MINS}m  |  cost = estimate (mirrors quota weighting, not your bill)"

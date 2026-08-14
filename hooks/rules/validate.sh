#!/bin/sh
# validate.sh — fail loudly here so run.sh can fail open there.
#
# Checks the schema and compiles every regex against a sample string, so a typo
# is caught at edit time instead of silently never matching at runtime. This is
# the job Rio wanted TypeScript + zod for; a schema check and a doc do it
# without putting a Node cold start in front of every tool call.
#
#   usage:  validate.sh [rules.json]
set -eu

RULES="${1:-$HOME/scripts/hooks/rules/rules.json}"
command -v jq >/dev/null 2>&1 || { echo "FAIL jq is required" >&2; exit 2; }
[ -r "$RULES" ] || { echo "FAIL not readable: $RULES" >&2; exit 2; }
jq -e . "$RULES" >/dev/null 2>&1 || { echo "FAIL not valid JSON: $RULES" >&2; exit 2; }

fail=0
note() { printf '%s\n' "$1" >&2; fail=1; }

# Schema. Every constraint the runner silently depends on, stated once.
errs="$(jq -r '
  def err($id; $m): "FAIL " + $id + ": " + $m;
  (.rules // null) as $rules
  | if $rules == null then ["FAIL top level: missing `rules` array"]
    elif ($rules | type) != "array" then ["FAIL top level: `rules` is not an array"]
    else
      [ $rules[]
        | (.id // "<no id>") as $id | (.on) as $on | (.do) as $do
        | [ (if (.id // "") == "" then err("<no id>"; "missing id") else empty end),
            (if (["tool","response"] | index($on)) == null
               then err($id; "`on` must be \"tool\" or \"response\", got \($on|tojson)") else empty end),
            (if (["remind","deny"] | index($do)) == null
               then err($id; "`do` must be \"remind\" or \"deny\", got \($do|tojson)") else empty end),
            (if .do == "deny" and .on == "response"
               then err($id; "cannot deny a reply that already happened; use `remind`") else empty end),
            (if (.text // "") == "" then err($id; "missing text — the agent needs to be told what to do") else empty end),
            (if (.match | type) != "object" then err($id; "missing `match` object") else empty end),
            (if .on == "tool" and ((.match.tool // "") == "") and ((.match.input // "") == "")
               then err($id; "on=tool needs match.tool and/or match.input") else empty end),
            (if .on == "response" and ((.match.text // "") == "")
               then err($id; "on=response needs match.text") else empty end) ]
        | .[] ]
      + ( [ $rules[] | .id ] | group_by(.) | map(select(length > 1) | "FAIL duplicate id: " + .[0]) )
    end | .[]' "$RULES")"
if [ -n "$errs" ]; then note "$errs"; fi

# Regexes must actually compile. jq shares Oniguruma with the runner, so a
# pattern that survives here is a pattern the runner can use.
re_errs="$(
  jq -r '.rules[]? | .id as $i
         | (.match.tool, .match.input, .match.text, .unless)
         | select(. != null and . != "") | $i + "\t" + .' "$RULES" \
  | while IFS="$(printf '\t')" read -r id re; do
      jq -n -e --arg re "$re" '"sample" | test($re) | true' >/dev/null 2>&1 \
        || printf 'FAIL %s: regex does not compile: %s\n' "$id" "$re"
    done
)"
if [ -n "$re_errs" ]; then note "$re_errs"; fi

[ "$fail" -eq 0 ] || exit 1
printf 'PASS %s rule(s) in %s\n' "$(jq '.rules | length' "$RULES")" "$RULES"

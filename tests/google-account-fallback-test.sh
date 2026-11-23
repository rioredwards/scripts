#!/bin/sh
# google-account-fallback-test.sh: a Google permission/not-found failure on one
# account tells the agent to try the other; successes and mere mentions stay silent.
set -u
hook="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)/hooks/google-account-fallback.sh"
fail=0

run() { # tool command response -> additionalContext or empty
  jq -cn --arg t "$1" --arg c "$2" --arg r "$3" \
    '{tool_name:$t, tool_input:{command:$c}, tool_response:{stdout:$r}}' |
    bash "$hook" | jq -r '.hookSpecificOutput.additionalContext // empty'
}
expect() { # name want-substring-or-EMPTY got
  if [ "$2" = EMPTY ]; then [ -z "$3" ] && return; else case "$3" in *"$2"*) return ;; esac; fi
  echo "FAIL $1: want [$2] got [$3]"; fail=1
}

gws403='{"error":{"code":403,"message":"The caller does not have permission"}}'
expect "gws 403 suggests gog" "retry the same read with gog" "$(run Bash 'gws sheets spreadsheets get --params x' "$gws403")"
expect "chained gws 403" "retry the same read with gog" "$(run Bash 'cd x && out=$(gws drive files get)' "$gws403")"
expect "gog 404 suggests gws" "retry the same read with gws" "$(run Bash 'gog --readonly sheets metadata ID' 'Error: Requested entity was not found.')"
expect "gws success silent" EMPTY "$(run Bash 'gws sheets spreadsheets get' '{"properties":{"title":"x"}}')"
expect "mention silent" EMPTY "$(run Bash 'grep -n gws README.md' "$gws403")"
expect "other command silent" EMPTY "$(run Bash 'curl -s example.com' '403 Forbidden')"
expect "connector denial" "retry the same read with gws" "$(run mcp__abc__get_spreadsheet '' 'The caller does not have permission')"
expect "non-Google connector silent" EMPTY "$(run mcp__abc__slack_read_channel '' 'permission denied')"

[ "$fail" = 0 ] && echo "google-account-fallback: ok"
exit "$fail"

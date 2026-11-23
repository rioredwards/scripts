#!/usr/bin/env bash
# google-account-fallback.sh: Rio's Google access spans two accounts. When a
# Google read fails on one with a permission or not-found error, tell the agent
# to retry on the other before calling the file blocked or using a substitute.
#
# Why: 2026-11-23 a captain session got a gws 403 on the Wine Tracker, called it
# blocked, and forecast Roma Spritz from depletions instead. gog (personal)
# opened it fine. The rule already lived in the straightaway-ad-hoc skill, which
# the session never loaded; the failing tool result is the one moment every
# agent (subagents too) is guaranteed to see.
#
#   gws                 work account, rio@straightawaycocktails.com
#   gog                 personal Gmail account
#   native connectors   Google Sheets/Drive/Gmail MCP tools, account varies
#
# PostToolUse, Bash + MCP. Delegates included on purpose. Fails open: no jq or
# an unreadable payload → exit 0, silent.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
RESP="$(printf '%s' "$INPUT" | jq -r '.tool_response // empty | if type == "string" then . else tojson end' 2>/dev/null)"

# Permission or not-found wording from gws, gog, the Google APIs and connectors.
printf '%s' "$RESP" | grep -Eiq 'code[\\"]*: ?40[34]|PERMISSION_DENIED|caller does not have permission|insufficient ?permission|permission denied|notFound|Requested entity was not found|File not found|403 Forbidden|404 Not Found' || exit 0

case "$TOOL" in
  Bash|exec_command|shell|local_shell)
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty | if type == "array" then join(" ") else . end' 2>/dev/null)"
    # Invocation at a command position, not a mention inside an argument.
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|(`{]|\$\(|(^|[[:space:]])(then|do|time|xargs|timeout [0-9]+[a-z]?|keyfor [^;&|]*--))[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*gws[[:space:]]'; then
      USED="gws (work account)"; TRY="gog (personal account), e.g. \`gog --readonly sheets metadata ID\`, or the native Google connector"
    elif printf '%s' "$CMD" | grep -Eq '(^|[;&|(`{]|\$\(|(^|[[:space:]])(then|do|time|xargs|timeout [0-9]+[a-z]?|keyfor [^;&|]*--))[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*gog[[:space:]]'; then
      USED="gog (personal account)"; TRY="gws (work account), or the native Google connector"
    else
      exit 0
    fi
    ;;
  mcp__*)
    printf '%s' "$TOOL" | grep -Eq '__(get_spreadsheet|get_values|update_values|append_values|update_formulas|batch_clear_values|insert_dimension|update_spreadsheet|copy_sheet_to_another_spreadsheet|read_file_content|download_file_content|get_file_metadata|get_file_permissions|copy_file|update_file|search_files|get_thread|get_message|search_threads|list_events|get_event)$' || exit 0
    USED="a native Google connector"; TRY="gws (work account) and gog (personal account), e.g. \`gog --readonly sheets metadata ID\`"
    ;;
  *) exit 0 ;;
esac

MSG="Google access failed on $USED. Rio has two Google accounts (work: gws; personal: gog; native connectors may be on either). Before calling this file blocked, unshared or missing, or using a substitute source, retry the same read with $TRY. Only if every route fails, report which accounts you tried and ask Rio for access."
jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'

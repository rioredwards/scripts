#!/usr/bin/env bash
# Stamp GitHub issues and PRs with the creating/editing session ID.
#
# Fires from a PostToolUse hook on the Bash tool. When the command was a
# `gh issue/pr create/edit`, it extracts matching URLs from the
# tool response and appends a `Session: <session_id>` footer to each
# body: unless that exact footer is already present (idempotent, so repeated
# edits don't stack footers).
#
# Runs outside the agent's tool loop, so its own `gh issue edit` calls do not
# re-trigger hooks. Fails open (exit 0) on missing jq/gh or malformed input.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.cmd // empty' 2>/dev/null)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$CMD" ] && [ -n "$SID" ] || exit 0

FOOTER="Session: ${SID}"

for kind in issue pr; do
  # Match actual invocations, not quoted mentions.
  printf '%s' "$CMD" | grep -Eq "gh[[:space:]]+$kind[[:space:]]+(create|edit)" || continue
  printf '%s' "$CMD" | "$(dirname "$0")/lib/cmd-invokes" "gh\\s+$kind\\s+(create|edit)" || continue

  # Only the command's own result, never URLs mentioned in its arguments.
  segment=issues
  [ "$kind" = pr ] && segment=pull
  URLS="$(printf '%s' "$INPUT" \
    | jq -r '.tool_response | tostring' 2>/dev/null \
    | grep -oE "https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/$segment/[0-9]+" \
    | sort -u)"
  [ -n "$URLS" ] || continue

  while IFS= read -r url; do
    body="$(gh "$kind" view "$url" --json body --jq .body 2>/dev/null)" || continue
    printf '%s\n' "$body" | grep -Fxq "$FOOTER" && continue
    printf '%s\n\n%s\n' "$body" "$FOOTER" | gh "$kind" edit "$url" --body-file - >/dev/null 2>&1
  done <<< "$URLS"
done

exit 0

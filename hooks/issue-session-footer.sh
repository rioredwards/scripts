#!/usr/bin/env bash
# issue-session-footer.sh — deterministic session-ID stamping for GitHub issues.
#
# Fires from a PostToolUse hook on the Bash tool. When the command was a
# `gh issue create` or `gh issue edit`, it extracts every issue URL from the
# tool response and appends a `Session: <session_id>` footer to each issue
# body — unless that exact footer is already present (idempotent, so repeated
# edits don't stack footers).
#
# Runs outside the agent's tool loop, so its own `gh issue edit` calls do not
# re-trigger hooks. Fails open (exit 0) on missing jq/gh or malformed input.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$CMD" ] && [ -n "$SID" ] || exit 0

printf '%s' "$CMD" | grep -Eq 'gh[[:space:]]+issue[[:space:]]+(create|edit)' || exit 0

# Issue URLs from the tool response only (not the command, which may merely
# reference other issues). `gh issue create/edit` print the issue URL.
URLS="$(printf '%s' "$INPUT" \
  | jq -r '.tool_response | tostring' 2>/dev/null \
  | grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+' \
  | sort -u)"
[ -n "$URLS" ] || exit 0

FOOTER="Session: ${SID}"

while IFS= read -r url; do
  body="$(gh issue view "$url" --json body --jq .body 2>/dev/null)" || continue
  case "$body" in
    *"$FOOTER"*) continue ;;
  esac
  printf '%s\n\n%s\n' "$body" "$FOOTER" | gh issue edit "$url" --body-file - >/dev/null 2>&1
done <<< "$URLS"

exit 0

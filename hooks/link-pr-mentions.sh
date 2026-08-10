#!/usr/bin/env bash
# link-pr-mentions.sh — auto-link bare PR mentions in GitHub issue/PR bodies.
#
# Fires from a PostToolUse hook on the Bash tool (Claude Code and Codex share
# the same hook JSON shape). When the command was a `gh issue`/`gh pr`
# create|edit|comment, it extracts every issue/PR URL from the tool response,
# fetches the current body, and rewrites bare "PR #N" mentions into markdown
# links: "PR #N" -> "[PR #N](<repo-url>/pull/N)". Already-linked mentions are
# left alone, so re-runs are idempotent.
#
# Runs outside the agent's tool loop, so its own `gh ... edit` calls do not
# re-trigger hooks. Fails open (exit 0) on missing jq/gh/perl or malformed
# input.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0
command -v perl >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$CMD" ] || exit 0

printf '%s' "$CMD" | grep -Eq 'gh[[:space:]]+(issue|pr)[[:space:]]+(create|edit|comment)' || exit 0

# Issue/PR URLs from the tool response only (not the command, which may merely
# reference other issues/PRs).
URLS="$(printf '%s' "$INPUT" \
  | jq -r '.tool_response | tostring' 2>/dev/null \
  | grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(issues|pull)/[0-9]+' \
  | sort -u)"
[ -n "$URLS" ] || exit 0

REPO_URL="$(gh repo view --json url -q .url 2>/dev/null)"
[ -n "$REPO_URL" ] || exit 0

while IFS= read -r url; do
  case "$url" in
    */pull/*) kind=pr ;;
    */issues/*) kind=issue ;;
    *) continue ;;
  esac

  body="$(gh "$kind" view "$url" --json body --jq .body 2>/dev/null)" || continue
  [ -n "$body" ] || continue

  new_body="$(printf '%s' "$body" | perl -pe "s{(?<!\\[)PR #(\\d+)(?!\\])}{[PR #\$1](${REPO_URL}/pull/\$1)}g")"

  [ "$new_body" != "$body" ] || continue
  printf '%s' "$new_body" | gh "$kind" edit "$url" --body-file - >/dev/null 2>&1
done <<< "$URLS"

exit 0

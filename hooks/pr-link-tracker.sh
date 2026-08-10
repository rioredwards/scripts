#!/usr/bin/env bash
# pr-link-tracker.sh — surface PR links from the agent's reply in the statusline.
#
# Fires from a Stop hook. Scans `last_assistant_message` (the reply just shown
# to Rio) for bare "PR #N" mentions and resolves each to this repo's GitHub
# pull URL, writing "[PR #N](url)" lines to a session-scoped marker file the
# statusline script reads:
#   /tmp/claude-pr-links-<session_id>
#
# Modern terminals (iTerm2, Warp, kitty, ...) auto-linkify bare URLs even
# inside markdown-style brackets, so no OSC-8 hyperlink hack is needed (and
# Claude Code doesn't reliably pass those through anyway).
#
# Overwrites every turn — empty file when the reply mentions no PRs — so the
# statusline never shows a stale link from an earlier turn. Never blocks the
# turn; fails open on missing jq/git, no git remote, or malformed input.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$SID" ] || exit 0

OUT="/tmp/claude-pr-links-${SID}"
: > "$OUT"

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
REPLY="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
[ -n "$REPLY" ] || exit 0

PR_NUMS="$(printf '%s' "$REPLY" | grep -oE 'PR #[0-9]+' | grep -oE '[0-9]+' | sort -nu)"
[ -n "$PR_NUMS" ] || exit 0

REMOTE="$(git -C "${CWD:-.}" remote get-url origin 2>/dev/null)" || exit 0
[ -n "$REMOTE" ] || exit 0

# Normalize git@github.com:owner/repo.git and https://github.com/owner/repo(.git) alike.
REPO_URL="$(printf '%s' "$REMOTE" | sed -E 's#^git@github\.com:#https://github.com/#; s#\.git$##')"
case "$REPO_URL" in
  https://github.com/*) ;;
  *) exit 0 ;;
esac

while IFS= read -r n; do
  printf '[PR #%s](%s/pull/%s)\n' "$n" "$REPO_URL" "$n"
done <<< "$PR_NUMS" > "$OUT"

exit 0

#!/usr/bin/env bash
# Dotfiles autosync stall alarm. ~/.dotfiles/scripts/dotfiles-autosync writes
# the marker when git-sync needs a human and removes it on the next clean sync.
# Silent while syncing is healthy.

set -euo pipefail

f="$HOME/.agent-context/dotfiles-sync-stalled"
[ -f "$f" ] || exit 0

echo "Dotfiles sync: STALLED on this Mac $(cat "$f") Edits here aren't reaching the other Mac. Tell Rio, then fix it (see ~/Library/Logs/dotfiles-autosync.log)."

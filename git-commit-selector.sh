#!/usr/bin/env zsh

# Git commit message selector using fzf
# Selects a previous commit message and outputs it ready for use with git commit -m

set -e

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository" >&2
    exit 1
fi

# Check if fzf is available
if ! command -v fzf > /dev/null 2>&1; then
    echo "Error: fzf is not installed" >&2
    exit 1
fi

# Get commit list with hash and subject
# Format: hash - subject
COMMIT_LIST=$(git log --pretty=format:"%h - %s" --no-merges)

if [ -z "$COMMIT_LIST" ]; then
    echo "No commits found" >&2
    exit 1
fi

# Use fzf to select a commit
# Preview shows the full commit message
SELECTED=$(echo "$COMMIT_LIST" | fzf \
    --height 40% \
    --layout=reverse \
    --border \
    --preview='git show --stat --color=always {1}' \
    --preview-window=right:50%:wrap \
    --header='Select a commit message')

if [ -z "$SELECTED" ]; then
    exit 1
fi

# Extract the commit hash (first word before the dash)
COMMIT_HASH=$(echo "$SELECTED" | awk '{print $1}')

# Get the full commit message (subject + body if exists)
# Just get the first line (subject) for simplicity
COMMIT_MESSAGE=$(git log -1 --pretty=format:"%s" "$COMMIT_HASH")

# Output just the message (the function will wrap it in the git commit command)
echo "$COMMIT_MESSAGE"

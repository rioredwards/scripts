#!/bin/zsh
# Install repo-local git hooks by setting core.hooksPath to .githooks

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

cd "$DOTFILES_DIR"
git config core.hooksPath .githooks

echo "✓ Installed hooks: core.hooksPath=.githooks"

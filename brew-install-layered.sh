#!/bin/zsh
# Install Homebrew packages using shared + role-specific Brewfiles.
# Usage: ./scripts/brew-install-layered.sh [mini|macbook]

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
ROLE="${1:-}"

if [[ -z "$ROLE" ]]; then
  HOST="$(scutil --get ComputerName 2>/dev/null || hostname)"
  case "${HOST:l}" in
    *mini*) ROLE="mini" ;;
    *) ROLE="macbook" ;;
  esac
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Error: Homebrew not installed"
  exit 1
fi

cd "$DOTFILES_DIR"

echo "Installing Brewfile.base..."
brew bundle --file Brewfile.base

ROLE_FILE="Brewfile.$ROLE"
if [[ -f "$ROLE_FILE" ]]; then
  echo "Installing $ROLE_FILE..."
  brew bundle --file "$ROLE_FILE"
else
  echo "Warning: $ROLE_FILE not found; skipped"
fi

echo "✓ Layered brew install complete for role: $ROLE"

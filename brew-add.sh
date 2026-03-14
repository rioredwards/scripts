#!/bin/zsh
# Install a Homebrew package and record it in a layered Brewfile.
# Usage:
#   ./scripts/brew-add.sh [--cask] [--role base|mini|macbook] <package>

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

IS_CASK=0
ROLE="base"
PKG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cask)
      IS_CASK=1
      shift
      ;;
    --role)
      ROLE="${2:-}"
      if [[ -z "$ROLE" ]]; then
        echo "Error: --role requires a value (base|mini|macbook)" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      echo "Usage: ./scripts/brew-add.sh [--cask] [--role base|mini|macbook] <package>"
      exit 0
      ;;
    *)
      if [[ -n "$PKG" ]]; then
        echo "Error: only one package at a time is supported" >&2
        exit 1
      fi
      PKG="$1"
      shift
      ;;
  esac
done

if [[ -z "$PKG" ]]; then
  echo "Error: package name is required" >&2
  echo "Usage: ./scripts/brew-add.sh [--cask] [--role base|mini|macbook] <package>"
  exit 1
fi

case "$ROLE" in
  base|mini|macbook) ;;
  *)
    echo "Error: invalid role '$ROLE' (expected: base|mini|macbook)" >&2
    exit 1
    ;;
esac

if ! command -v brew >/dev/null 2>&1; then
  echo "Error: brew not found" >&2
  exit 1
fi

TARGET_FILE="$DOTFILES_DIR/Brewfile.$ROLE"
if [[ ! -f "$TARGET_FILE" ]]; then
  echo "Error: target file not found: $TARGET_FILE" >&2
  exit 1
fi

echo "Installing: $PKG"
if [[ "$IS_CASK" -eq 1 ]]; then
  brew install --cask "$PKG"
  ENTRY="cask \"$PKG\""
else
  brew install "$PKG"
  ENTRY="brew \"$PKG\""
fi

if grep -Fqx "$ENTRY" "$TARGET_FILE"; then
  echo "Already present in $(basename "$TARGET_FILE"): $ENTRY"
else
  {
    echo ""
    echo "$ENTRY"
  } >> "$TARGET_FILE"
  echo "Added to $(basename "$TARGET_FILE"): $ENTRY"
fi

echo "Done. Commit changes when ready."

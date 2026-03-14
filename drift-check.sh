#!/bin/zsh
# Compare high-signal machine state to reduce MacBook/Mac Mini drift.
# Usage: ./scripts/drift-check.sh [snapshot|compare]
#   snapshot (default): writes local snapshot under ./state/
#   compare: compares local snapshot with ./state/<other-host>/

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
STATE_DIR="$DOTFILES_DIR/state"
HOST="$(scutil --get ComputerName 2>/dev/null || hostname)"
HOST_SAFE="${HOST// /-}"
SELF_DIR="$STATE_DIR/$HOST_SAFE"

mkdir -p "$SELF_DIR"

snapshot() {
  echo "[drift-check] creating snapshot for: $HOST"

  command -v brew >/dev/null 2>&1 && {
    brew list --formula | sort > "$SELF_DIR/brew-formula.txt"
    brew list --cask | sort > "$SELF_DIR/brew-cask.txt"
  }

  {
    command -v node >/dev/null 2>&1 && echo "node $(node -v)"
    command -v npm >/dev/null 2>&1 && echo "npm $(npm -v)"
    command -v pnpm >/dev/null 2>&1 && echo "pnpm $(pnpm -v)"
    command -v python3 >/dev/null 2>&1 && echo "python3 $(python3 --version 2>&1)"
    command -v git >/dev/null 2>&1 && echo "git $(git --version)"
    command -v gh >/dev/null 2>&1 && echo "gh $(gh --version | head -n1)"
    command -v docker >/dev/null 2>&1 && echo "docker $(docker --version)"
    command -v openclaw >/dev/null 2>&1 && echo "openclaw $(openclaw --version 2>/dev/null | head -n1)"
  } > "$SELF_DIR/versions.txt"

  echo "[drift-check] snapshot written to $SELF_DIR"
  echo "[drift-check] commit/push this state dir if you want cross-machine comparison via git"
}

compare() {
  if [[ ! -d "$STATE_DIR" ]]; then
    echo "No state snapshots found. Run: ./scripts/drift-check.sh snapshot"
    exit 1
  fi

  local others=("$STATE_DIR"/*)
  local target=""
  for d in "${others[@]}"; do
    [[ -d "$d" ]] || continue
    [[ "$(basename "$d")" == "$HOST_SAFE" ]] && continue
    target="$d"
    break
  done

  if [[ -z "$target" ]]; then
    echo "No other host snapshot found."
    echo "Create one on the other machine, commit, then pull here."
    exit 1
  fi

  echo "[drift-check] comparing $HOST_SAFE -> $(basename "$target")"

  for file in brew-formula.txt brew-cask.txt versions.txt; do
    if [[ -f "$SELF_DIR/$file" && -f "$target/$file" ]]; then
      echo "\n=== $file ==="
      diff -u "$target/$file" "$SELF_DIR/$file" || true
    else
      echo "\n=== $file ==="
      echo "missing on one side"
    fi
  done
}

MODE="${1:-snapshot}"
case "$MODE" in
  snapshot) snapshot ;;
  compare) compare ;;
  *)
    echo "Usage: ./scripts/drift-check.sh [snapshot|compare]"
    exit 1
    ;;
esac

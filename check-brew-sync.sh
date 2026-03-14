#!/bin/zsh
# Check whether installed top-level Homebrew packages are represented
# in layered Brewfiles (base + role).
#
# Usage:
#   ./scripts/check-brew-sync.sh [--role mini|macbook] [--strict]
# Role resolution order:
#   1) --role flag
#   2) BREW_ROLE env var
#   3) .machine-role file at repo root
#   4) hostname heuristic (*mini* => mini, else macbook)
#
# Exit codes:
#   0 = in sync (or warnings only when not strict)
#   1 = out of sync in strict mode

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
ROLE=""
STRICT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      ROLE="${2:-}"
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    -h|--help)
      echo "Usage: ./scripts/check-brew-sync.sh [--role mini|macbook] [--strict]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$ROLE" && -n "${BREW_ROLE:-}" ]]; then
  ROLE="$BREW_ROLE"
fi

if [[ -z "$ROLE" && -f "$DOTFILES_DIR/.machine-role" ]]; then
  ROLE="$(tr -d '[:space:]' < "$DOTFILES_DIR/.machine-role")"
fi

if [[ -z "$ROLE" ]]; then
  HOST="$(hostname -s 2>/dev/null || hostname)"
  case "${HOST:l}" in
    *mini*) ROLE="mini" ;;
    *) ROLE="macbook" ;;
  esac
fi

if [[ "$ROLE" != "mini" && "$ROLE" != "macbook" ]]; then
  echo "Invalid role: $ROLE (expected mini|macbook)" >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "brew not found; skipping brew sync check"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

installed_formula="$TMP_DIR/installed-formula.txt"
installed_cask="$TMP_DIR/installed-cask.txt"
expected_formula="$TMP_DIR/expected-formula.txt"
expected_cask="$TMP_DIR/expected-cask.txt"

brew leaves \
  | sed -E 's#^[^/]*/[^/]*/##' \
  | sort > "$installed_formula"
brew list --cask | sort > "$installed_cask"

cat "$DOTFILES_DIR/Brewfile.base" "$DOTFILES_DIR/Brewfile.$ROLE" \
  | rg '^brew\s+"([^"]+)"' -or '$1' | sort -u > "$expected_formula"

cat "$DOTFILES_DIR/Brewfile.base" "$DOTFILES_DIR/Brewfile.$ROLE" \
  | rg '^cask\s+"([^"]+)"' -or '$1' | sort -u > "$expected_cask"

missing_formula="$TMP_DIR/missing-formula.txt"
missing_cask="$TMP_DIR/missing-cask.txt"
extra_formula="$TMP_DIR/extra-formula.txt"
extra_cask="$TMP_DIR/extra-cask.txt"

comm -23 "$installed_formula" "$expected_formula" > "$missing_formula"
comm -23 "$installed_cask" "$expected_cask" > "$missing_cask"
comm -13 "$installed_formula" "$expected_formula" > "$extra_formula"
comm -13 "$installed_cask" "$expected_cask" > "$extra_cask"

# Optional ignore list for intentionally unmanaged local packages.
# Lines format:
#   brew:<name>
#   cask:<name>
IGNORE_FILES=("$DOTFILES_DIR/.brew-sync-ignore" "$DOTFILES_DIR/.brew-sync-ignore.local")
brew_ignore="$TMP_DIR/ignore-brew.txt"
cask_ignore="$TMP_DIR/ignore-cask.txt"
: > "$brew_ignore"
: > "$cask_ignore"

for IGNORE_FILE in "${IGNORE_FILES[@]}"; do
  [[ -f "$IGNORE_FILE" ]] || continue
  rg '^brew:(.+)$' "$IGNORE_FILE" -or '$1' >> "$brew_ignore" || true
  rg '^cask:(.+)$' "$IGNORE_FILE" -or '$1' >> "$cask_ignore" || true
done

sort -u "$brew_ignore" -o "$brew_ignore"
sort -u "$cask_ignore" -o "$cask_ignore"

if [[ -s "$brew_ignore" ]]; then
  comm -23 "$missing_formula" "$brew_ignore" > "$missing_formula.filtered" || true
  mv "$missing_formula.filtered" "$missing_formula"
fi
if [[ -s "$cask_ignore" ]]; then
  comm -23 "$missing_cask" "$cask_ignore" > "$missing_cask.filtered" || true
  mv "$missing_cask.filtered" "$missing_cask"
fi

has_issue=0

if [[ -s "$missing_formula" || -s "$missing_cask" ]]; then
  has_issue=1
  echo "[brew-sync] Installed packages missing from layered Brewfiles (role=$ROLE):"
  [[ -s "$missing_formula" ]] && { echo "  Formulae:"; sed 's/^/    - /' "$missing_formula"; }
  [[ -s "$missing_cask" ]] && { echo "  Casks:"; sed 's/^/    - /' "$missing_cask"; }
  echo ""
  echo "Fix with brew-add, for example:"
  echo "  brew-add --role $ROLE <formula>"
  echo "  brew-add --cask --role $ROLE <cask>"
  echo "  # or --role base if shared on both machines"
fi

if [[ -s "$extra_formula" || -s "$extra_cask" ]]; then
  echo "[brew-sync] Note: Brewfiles include packages not installed on this machine (often intentional):"
  [[ -s "$extra_formula" ]] && { echo "  Formulae:"; sed 's/^/    - /' "$extra_formula"; }
  [[ -s "$extra_cask" ]] && { echo "  Casks:"; sed 's/^/    - /' "$extra_cask"; }
fi

if [[ "$has_issue" -eq 1 && "$STRICT" -eq 1 ]]; then
  exit 1
fi

exit 0

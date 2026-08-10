#!/usr/bin/env bash
# Bulk-set macOS file associations for common coding file types to Cursor.
# Requires `duti` (brew install duti). Re-run anytime to reassert.
set -euo pipefail

CURSOR_BUNDLE_ID="com.todesktop.230313mzl4w4u92"

EXTENSIONS=(
  # code
  js jsx ts tsx mjs cjs py go rb php rs java kt lua c h cpp cc hpp m mm swift gd scm
  # shell
  sh zsh bash
  # web/markup
  html css scss sass less xml svg
  # data/config
  json jsonl yml yaml toml ini cfg conf env npmrc editorconfig gitignore
  # docs/text
  md mdx mdc txt sql csv log plist
)

failed=()
for ext in "${EXTENSIONS[@]}"; do
  if ! duti -s "$CURSOR_BUNDLE_ID" ".$ext" all; then
    failed+=("$ext")
  fi
done

ok=$(( ${#EXTENSIONS[@]} - ${#failed[@]} ))
echo "Set $ok/${#EXTENSIONS[@]} extensions to open in Cursor ($CURSOR_BUNDLE_ID)."
if (( ${#failed[@]} > 0 )); then
  echo "Failed: ${failed[*]}"
fi

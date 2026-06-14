#!/usr/bin/env zsh
set -euo pipefail

typeset -A SHORTCUTS
SHORTCUTS=(
  create-note-for-audio-from-clipboard "Create Note For Audio From Clipboard"
  create-audio-note "Create Note For Audio From Clipboard"
  make-spoken-audio-track "Make Spoken Audio Track"
  make-spoken-audio "Make Spoken Audio Track"
  ping-rio "Ping Rio"
  speak-clipboard-raw "Speak Clipboard Raw"
  speak-clipboard "Speak Clipboard Raw"
  summarize-text "Summarize Text"
  summarize-clipboard "Summarize Clipboard"
  text-phone "Text Phone"
)

usage() {
  cat <<'EOF'
Usage:
  sc
  sc <shortcut-alias> [text...]
  echo "text" | sc <shortcut-alias>

Registered shortcuts:
EOF

  for alias in ${(ok)SHORTCUTS}; do
    printf '  %-42s %s\n' "$alias" "$SHORTCUTS[$alias]"
  done
}

die() {
  printf 'sc: %s\n\n' "$1" >&2
  usage >&2
  exit 1
}

shortcut_alias="${1:-}"

if [[ -z "$shortcut_alias" || "$shortcut_alias" == "-h" || "$shortcut_alias" == "--help" ]]; then
  usage
  exit 0
fi

shortcut_name="${SHORTCUTS[$shortcut_alias]:-}"
[[ -n "$shortcut_name" ]] || die "unknown shortcut alias: $shortcut_alias"

shift

input_file=""
output_file="$(mktemp "${TMPDIR:-/tmp}/sc-output.XXXXXX")"
cleanup() {
  [[ -n "$input_file" && -f "$input_file" ]] && command rm -f "$input_file"
  [[ -f "$output_file" ]] && command rm -f "$output_file"
}
trap cleanup EXIT

args=("$shortcut_name" --output-path "$output_file")

if (( $# > 0 )); then
  base_tmp="$(mktemp "${TMPDIR:-/tmp}/sc-input.XXXXXX")"
  input_file="${base_tmp}.txt"
  mv "$base_tmp" "$input_file"
  printf '%s\n' "$*" > "$input_file"
  args+=(--input-path "$input_file")
elif [[ ! -t 0 ]]; then
  base_tmp="$(mktemp "${TMPDIR:-/tmp}/sc-input.XXXXXX")"
  input_file="${base_tmp}.txt"
  mv "$base_tmp" "$input_file"
  cat > "$input_file"
  args+=(--input-path "$input_file")
fi

shortcuts run "${args[@]}"

if [[ -s "$output_file" ]]; then
  cat "$output_file"
fi

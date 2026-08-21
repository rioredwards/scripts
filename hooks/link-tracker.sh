#!/usr/bin/env bash
# link-tracker.sh — surface links from the agent's reply in the statusline.
#
# Fires from a Stop hook. Two sources of links, both scanned from
# `last_assistant_message` (the reply just shown to Rio):
#   1. Bare "PR #N" mentions (no URL) — resolved against this repo's GitHub
#      remote, e.g. "PR #544" -> https://github.com/<owner>/<repo>/pull/544
#   2. Any URL already written in the reply, markdown-formatted or bare
#   3. File references (`src/a.ts:42`, `~/x/y.md`) that exist on disk ->
#      `mycontrols-dev://open?path=&host=&line=` deeplinks, so a click opens the
#      file in Cursor on whichever Mac Rio is at (my-controls routes it)
#
# Each becomes an OSC-8 hyperlink line (short label clickable, URL as
# target) in a session-scoped marker file the statusline script reads:
#   /tmp/claude-links-<session_id>
#
# Label priority for URLs already in the text: the reply's own markdown
# label if present, else a pattern derived from known GitHub URL shapes
# (PR/issue/commit), else the bare hostname. No network calls — fetching
# page titles adds latency and failure modes a per-turn hook can't afford.
#
# Overwrites every turn — empty file when the reply has no links — so the
# statusline never shows stale links from an earlier turn. Never blocks the
# turn; fails open on missing jq/git, no git remote, or malformed input.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$SID" ] || exit 0

OUT="/tmp/claude-links-${SID}"
: > "$OUT"

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
REPLY="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
[ -n "$REPLY" ] || exit 0

declare -A LABEL=()
declare -a ORDER=()

add_link() {
  local url="$1" label="$2"
  [ -n "${LABEL[$url]+set}" ] && return
  LABEL["$url"]="$label"
  ORDER+=("$url")
}

# 1. Bare "PR #N" mentions -> derive the URL from this repo's GitHub remote.
PR_NUMS="$(printf '%s' "$REPLY" | grep -oE 'PR #[0-9]+' | grep -oE '[0-9]+' | sort -nu)"
if [ -n "$PR_NUMS" ]; then
  REMOTE="$(git -C "${CWD:-.}" remote get-url origin 2>/dev/null)"
  if [ -n "$REMOTE" ]; then
    # Normalize git@github.com:owner/repo.git and https://github.com/owner/repo(.git) alike.
    REPO_URL="$(printf '%s' "$REMOTE" | sed -E 's#^git@github\.com:#https://github.com/#; s#\.git$##')"
    case "$REPO_URL" in
      https://github.com/*)
        while IFS= read -r n; do
          add_link "${REPO_URL}/pull/${n}" "PR #${n}"
        done <<< "$PR_NUMS"
        ;;
    esac
  fi
fi

# 2a. Markdown-formatted links -> keep the reply's own label.
MD_LINKS="$(printf '%s' "$REPLY" | grep -oE '\[[^]]+\]\(https?://[^)]+\)')"
if [ -n "$MD_LINKS" ]; then
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    label="${m%%](*}"
    label="${label#\[}"
    rest="${m#*](}"
    url="${rest%)}"
    add_link "$url" "$label"
  done <<< "$MD_LINKS"
fi

# 2b. Remaining bare URLs -> derive a label from known GitHub shapes, else hostname.
TEXT_NO_MD="$(printf '%s' "$REPLY" | sed -E 's#\[[^]]+\]\([^)]+\)##g')"
BARE_URLS="$(printf '%s' "$TEXT_NO_MD" | grep -oE 'https?://[^[:space:]<>()"]+' | sed -E 's#[.,;:!?]+$##')"
if [ -n "$BARE_URLS" ]; then
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    [ -n "${LABEL[$url]+set}" ] && continue
    case "$url" in
      https://github.com/*/*/pull/*)
        n="${url##*/pull/}"
        add_link "$url" "PR #${n}"
        ;;
      https://github.com/*/*/issues/*)
        n="${url##*/issues/}"
        add_link "$url" "Issue #${n}"
        ;;
      https://github.com/*/*/commit/*)
        sha="${url##*/commit/}"
        add_link "$url" "Commit ${sha:0:7}"
        ;;
      *)
        host="$(printf '%s' "$url" | sed -E 's#^https?://##; s#/.*##')"
        add_link "$url" "$host"
        ;;
    esac
  done <<< "$BARE_URLS"
fi

# 3. File references -> my-controls `open` deeplinks (first 3 that exist).
#    `host` is this Mac's ssh alias: the click may land on the other one.
case "$(hostname -s | tr '[:upper:]' '[:lower:]')" in
  *mac-mini*) HOST_ALIAS=mini ;;
  *) HOST_ALIAS=macbook ;;
esac
MC_SCHEME="${MC_SCHEME:-mycontrols-dev}"
n_files=0
FILE_REFS="$(printf '%s' "$TEXT_NO_MD" | grep -oE '(~/|/|\./)?[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*\.[A-Za-z0-9]+(:[0-9]+)?' | sed -E 's#^`##; s#`$##' | awk '!seen[$0]++')"
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  [ "$n_files" -lt 3 ] || break
  line="${ref##*:}"; path="${ref%:*}"
  [ "$line" = "$ref" ] && line=""
  path="${path/#\~/$HOME}"
  case "$path" in /*) ;; *) path="${CWD:-.}/$path" ;; esac
  [ -f "$path" ] || continue
  path="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  url="${MC_SCHEME}://open?path=${path}&host=${HOST_ALIAS}${line:+&line=$line}"
  add_link "$url" "$(printf '\xf0\x9f\x93\x82 %s' "$(basename "$path")${line:+:$line}")"
  n_files=$((n_files + 1))
done <<< "$FILE_REFS"

[ "${#ORDER[@]}" -gt 0 ] || exit 0

for url in "${ORDER[@]}"; do
  printf '\033]8;;%s\033\\%s\033]8;;\033\\\n' "$url" "${LABEL[$url]}"
done > "$OUT"

exit 0

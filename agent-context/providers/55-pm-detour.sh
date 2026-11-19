#!/usr/bin/env bash
# Detour catcher (trial, PM issue 21). In one of Rio's tooling repos while a planned focus
# block is running, name the block so the agent can offer a seed for a detour.
# Prints nothing outside a block window, outside a tooling repo, or with no journal.
# Test overrides: PM_DETOUR_NOW (HH:MM), PM_DETOUR_JOURNAL (path).

set -euo pipefail

# The session's directory comes from the SessionStart payload (emit.sh exports it).
cwd="${AGENT_SESSION_CWD:-}"
[ -n "$cwd" ] || exit 0

# SPIKE: explicit list. ~/.agents/categories.json maps only Straightaway repos, not tooling repos.
tooling=(
  "$HOME/scripts"
  "$HOME/.dotfiles"
  "$HOME/dev/agent-skills"
  "$HOME/dev/agent-sessions"
  "$HOME/dev/agent-router"
  "$HOME/dev/ai-text-transform"
  "$HOME/dev/click-tool"
  "$HOME/dev/shortcuts-workshop"
  "$HOME/dev/project-manager"
)

# A git worktree counts as its main repo, wherever the worktree lives.
dirs=("$cwd")
if common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  dirs+=("$(dirname "$common")")
fi

is_tooling=""
for d in "${dirs[@]}"; do
  for t in "${tooling[@]}"; do
    case "$d" in "$t"|"$t"/*) is_tooling=1 ;; esac
  done
done
[ -n "$is_tooling" ] || exit 0

journal="${PM_DETOUR_JOURNAL:-$HOME/dev/project-manager/journal/$(date +%F).md}"
[ -f "$journal" ] || exit 0
now="${PM_DETOUR_NOW:-$(date +%H:%M)}"

# Plan lines look like "- 07:45-09:15  Title  ·  why: ...".
block=$(awk -v now="$now" '
  /^## plan for /{on=1; next} /^## /{on=0}
  on && /^- [0-9][0-9]:[0-9][0-9]-[0-9][0-9]:[0-9][0-9]/ {
    win=substr($2,1,11); s=substr(win,1,5); e=substr(win,7,5)
    if (now >= s && now < e) {
      t=$0; sub(/^- [0-9:-]+ +/,"",t); sub(/ +·.*/,"",t)
      print win "  " t; exit
    }
  }' "$journal")
[ -n "$block" ] || exit 0

echo "Detour check: Rio's planned focus block is running now (${block%%  *}): ${block#*  }. If this session's work is a detour from it, offer Rio a one-line seed issue for the detour and point him back to the block."

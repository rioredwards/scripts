#!/usr/bin/env bash
# Unified AI-agent session picker. Aggregates Claude/Codex/OpenCode
# sessions, sorts newest-first, lets you fzf-pick one, then reattaches.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${HERE}/agent-sessions.py"

command -v fzf >/dev/null || { echo "needs fzf"; exit 1; }

# Fire the summarizer in the background (detached) so missing titles get
# generated for the next run. No-ops if ollama is absent. Picker stays instant.
if command -v ollama >/dev/null 2>&1; then
  nohup python3 "${HERE}/agent-sessions-summarize.py" >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

# Line layout: <fixed-width display>\t<resume-json>\t<preview-json>
# Show field 1 to the user; keep fields 2-3 hidden. fzf feeds field 3 to the
# Python preview renderer for the highlighted row.
choice="$(python3 "$PY" \
  | fzf --ansi --delimiter=$'\t' --with-nth=1 \
        --header='AI sessions (newest first) — enter resume · ctrl-/ preview · shift-↑/↓ scroll' \
        --preview="python3 '${PY}' --preview {3}" \
        --preview-window='nohidden,right,55%,wrap,border-left')" || exit 0

[ -z "$choice" ] && exit 0

payload="$(printf '%s' "$choice" | cut -f2)"
kind="$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin)["kind"])')"
cwd="$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin)["cwd"])')"
mapfile -t cmd < <(printf '%s' "$payload" | python3 -c 'import json,sys;[print(a) for a in json.load(sys.stdin)["cmd"]]')

echo "→ ${kind}: cd ${cwd} && ${cmd[*]}"
[ -d "$cwd" ] && cd "$cwd"
exec "${cmd[@]}"

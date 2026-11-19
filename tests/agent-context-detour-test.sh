#!/usr/bin/env bash
# Detour line: only in a tooling repo, inside a planned block window, with a journal.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
p="$root/agent-context/providers/55-pm-detour.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/j.md" <<'J'
# day
## plan for 2026-11-19
- 07:45-09:15  Finish the 2027 Forecasting Sheet  ·  why: due
- 09:45-11:45  Release the waiting fixes  ·  why: waited
## gather
J
run() { # cwd now journal
  AGENT_SESSION_CWD="$1" PM_DETOUR_NOW="$2" PM_DETOUR_JOURNAL="$3" bash "$p"
}
out="$(run "$HOME/scripts" 08:00 "$tmp/j.md")"
grep -q 'Finish the 2027 Forecasting Sheet' <<<"$out"
grep -q 'seed issue' <<<"$out"
out="$(run "$HOME/dev/agent-skills/.claude/worktrees/x" 10:00 "$tmp/j.md")"
grep -q 'Release the waiting fixes' <<<"$out"
[ -z "$(run "$HOME/dev/straightaway/straightaway-next" 08:00 "$tmp/j.md")" ]
[ -z "$(run "$HOME/scripts" 09:30 "$tmp/j.md")" ]
[ -z "$(run "$HOME/scripts" 08:00 "$tmp/none.md")" ]
[ -z "$(run "" 08:00 "$tmp/j.md")" ]
echo "PASS agent-context-detour"

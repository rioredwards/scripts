#!/usr/bin/env bash
# pm: the one door to Rio's project manager, on either Mac.
#   pm [message]          talk to the PM (Claude Code in ~/dev/project-manager; memory is the repo)
#   pm daily              run today's routine; a same-day re-run updates today in place
#   pm daily --headless   same, print mode, no prompts, only the note comes back (needs: claude auth login)
#   pm last               print the newest journal entry
set -euo pipefail
PM="$HOME/dev/project-manager"
[ -d "$PM/.git" ] || { echo "pm: $PM missing. git clone git@github.com:rioredwards/project-manager.git $PM" >&2; exit 1; }
command -v claude >/dev/null || { echo "pm: claude CLI missing" >&2; exit 1; }
cd "$PM" && git pull -q
# installs are snapshots: refresh the pm plugin so /pm:* skills match the repo
claude plugin update pm@project-manager >/dev/null 2>&1 || echo "pm: plugin update failed. Once per Mac: claude plugin marketplace add ~/dev/project-manager && claude plugin install pm@project-manager" >&2
CAL="mcp__3d6559c0-53a4-4853-be29-849c11211af1"   # Google Calendar connector (same id on both Macs)
DAILY="Run the daily routine now. Read AGENTS.md, PLAYBOOK.md, then skills/daily/SKILL.md and follow it exactly"
OPEN="Open as the PM: read AGENTS.md and follow its Sessions contract. Then one line only: today's blocks and yesterday's score. Then wait."
case "${1:-}" in
  "") exec claude "$OPEN" ;;
  -h|--help) sed -n '2,6p' "$0" ;;
  daily)
    if [ "${2:-}" = "--headless" ]; then
      exec claude -p "$DAILY, in headless mode: never ask, never wait." --max-turns 80 \
        --allowedTools Bash Read Edit Write Glob Grep ToolSearch Artifact "$CAL"
    fi
    exec claude "$DAILY." ;;
  last) cat "$(ls journal/[0-9]*.md | sort | tail -1)" ;;
  *) exec claude "$*" ;;
esac

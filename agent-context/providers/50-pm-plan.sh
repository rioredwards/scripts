#!/usr/bin/env bash
# Today's focus blocks from the PM's daily run, so every agent knows Rio's plan.
# No journal for today yet (PM hasn't run) is normal: print nothing.

set -euo pipefail

journal="$HOME/dev/project-manager/journal/$(date +%F).md"
[ -f "$journal" ] || exit 0

plan=$(awk '/^## plan for /{on=1; next} /^## /{on=0} on && /^- [0-9]/' "$journal")
[ -n "$plan" ] || exit 0

echo "Today's plan (PM focus blocks):"
echo "$plan"

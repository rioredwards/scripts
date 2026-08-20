#!/usr/bin/env bash
# The live reply-length ceiling, so AGENTS.md never has to name a number.
#
# The cap is a knob (`agent-toggle reply-cap`). Hardcoding it in prose means
# changing the knob leaves the agent told two different numbers — which is the
# bug this provider exists to remove. Source of truth is the same lib the
# enforcing hook uses, so the two can't drift.

set -euo pipefail

lib="$HOME/scripts/hooks/lib/reply-cap-lib.sh"
[ -r "$lib" ] || exit 0
# shellcheck source=/dev/null
. "$lib"

if cap="$(reply_cap_value)"; then
  echo "Reply cap: $cap prose words (fenced code excluded). A hook bounces anything over."
else
  echo "Reply cap: off. No hook enforcement right now — stay brief anyway."
fi

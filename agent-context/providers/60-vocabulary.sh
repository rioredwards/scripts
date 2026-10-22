#!/usr/bin/env bash
# Rio's shared vocabulary, so every session starts knowing his words instead of being told
# to go read a file (L-0213). Straightaway sessions (cwd under ~/dev/straightaway) also get
# that repo's vocabulary.

set -euo pipefail

f="$HOME/.agents/VOCABULARY.md"
[ -f "$f" ] || { echo "agent-context: missing $f" >&2; exit 1; }
echo "Rio's vocabulary (~/.agents/VOCABULARY.md):"
cat "$f"

sa="$HOME/dev/straightaway/straightaway-next/VOCABULARY.md"
case "$PWD" in
  "$HOME"/dev/straightaway/*) [ -f "$sa" ] && { echo; echo "Straightaway vocabulary ($sa):"; cat "$sa"; } ;;
esac
exit 0

#!/usr/bin/env bash
# Where Rio is. Nothing here computes it — an Apple Shortcut writes the file
# (iPhone location-arrival automation, or a manual Shortcut on the Mac).
# Reference implementation of a pushed fact: same shape as any other provider.
# Silent until something writes the file.

set -euo pipefail

f="$HOME/.agent-context/location"
[ -f "$f" ] || exit 0

echo "Location: $(cat "$f")"

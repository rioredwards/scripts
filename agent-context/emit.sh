#!/usr/bin/env bash
# Dynamic agent context — emitted at SessionStart for Claude Code and Codex.
#
# One rule: a fact is a provider script in providers/ that prints "Name: value"
# lines on stdout. How it gets that value — computing it, reading a file an
# Apple Shortcut wrote, calling an API — is that provider's own business.
# There is no "derived" vs "declared" split to reason about.
#
#   Add a fact       drop an executable in providers/. Nothing else changes.
#   Nothing to say   print nothing, exit 0. Normal (e.g. Shortcut hasn't run).
#   Broken           exit non-zero. Fails the whole emit, loudly, by name.
#
# Providers run in filename order, hence the numeric prefixes.

set -euo pipefail
shopt -s nullglob

providers="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/providers"

facts=""
for p in "$providers"/*; do
  if [ ! -x "$p" ]; then
    echo "agent-context: provider not executable: $p" >&2
    exit 1
  fi
  if ! out=$("$p"); then
    echo "agent-context: provider failed: $p" >&2
    exit 1
  fi
  if [ -n "$out" ]; then
    facts+="$out"$'\n'
  fi
done

[ -n "$facts" ] || exit 0

jq -nc --arg c "${facts%$'\n'}" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'

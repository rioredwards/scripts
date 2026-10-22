#!/usr/bin/env bash
# Vocabulary reaches every session at start; Straightaway's only inside that repo.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
p="$root/agent-context/providers/60-vocabulary.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.agents" "$tmp/dev/straightaway/straightaway-next/app"
echo "glance: quick look" > "$tmp/.agents/VOCABULARY.md"
echo "SKU: product code" > "$tmp/dev/straightaway/straightaway-next/VOCABULARY.md"
out="$(cd "$tmp" && HOME="$tmp" bash "$p")"
grep -q 'glance: quick look' <<<"$out"
! grep -q SKU <<<"$out"
out="$(cd "$tmp/dev/straightaway/straightaway-next/app" && HOME="$tmp" bash "$p")"
grep -q 'SKU: product code' <<<"$out"
echo "PASS agent-context-vocabulary"

#!/bin/sh
# claude-latest: picks from a seeded cache, never the network.
set -u
CL="$(dirname "$0")/../claude-latest"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/claude-latest"
cat > "$tmp/claude-latest/models.json" <<'J'
[{"id":"claude-sonnet-5","created_at":"2026-06-29T00:00:00Z","max_tokens":128000},
 {"id":"claude-sonnet-5-5","created_at":"2026-09-28T00:00:00Z","max_tokens":128000},
 {"id":"claude-haiku-4-5-20251001","created_at":"2025-10-15T00:00:00Z","max_tokens":64000}]
J
export XDG_CACHE_HOME="$tmp"
# A miss forces a refresh; a HOME with no keyfor makes that fail loudly offline.
export HOME="$tmp"
fail=0
check() { if [ "$2" = "$3" ]; then echo "  ok: $1"; else echo "  FAIL: $1 (want '$3', got '$2')" >&2; fail=1; fi; }
check "family picks newest" "$("$CL" sonnet)" "claude-sonnet-5-5"
check "json gives output cap" "$("$CL" --json claude-haiku-4-5-20251001)" '{"id": "claude-haiku-4-5-20251001", "max_tokens": 64000}'
"$CL" opus >/dev/null 2>&1; check "unknown family fails" "$?" "1"
"$CL" >/dev/null 2>&1; check "no args fails" "$?" "1"
exit $fail

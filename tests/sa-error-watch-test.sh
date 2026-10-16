#!/bin/zsh
# sa-error-watch: hit path (sample lines, temp inbox), zero-hit path, and fail-loud paths.
# Never calls Vercel and never touches the real inbox or state file.

set -uo pipefail

WATCH="${0:A:h}/../sa-error-watch"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export SA_ERROR_WATCH_INBOX_DIR="$tmp/inbox"
export SA_ERROR_WATCH_STATE="$tmp/state/last-run"
export SA_ERROR_WATCH_NOW="2026-10-16T08:00:00-07:00"

pass=0 fail=0
ok()   { print -- "  ok: $1"; (( ++pass )) }
bad()  { print -u2 -- "  FAIL: $1"; (( ++fail )) }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi }

# Server error (app line inside logs[], repeated in message), the same request twice in the page,
# a client crash (line only in message), and an unrelated request.
srv='{"tag":"sa-app-error","source":"server","message":"relation \"x\" does not exist","digest":"d111","path":"/qc/runs","method":"GET"}'
cli='{"tag":"sa-app-error","source":"client","message":"Cannot read properties of undefined | boom","digest":"d222","path":"/qc/runs"}'
python3 - "$srv" "$cli" > "$tmp/sample.jsonl" <<'PY'
import json, sys
srv, cli = sys.argv[1], sys.argv[2]
a = {"id": "a1", "timestamp": 1792110000000, "level": "error", "message": srv, "requestPath": "/qc/runs",
     "logs": [{"level": "error", "message": srv}]}
c = {"id": "c1", "timestamp": 1792110100000, "level": "error", "message": cli, "requestPath": "/", "logs": []}
n = {"id": "n1", "timestamp": 1792110200000, "level": "info", "message": "", "requestPath": "/", "logs": []}
for e in (a, a, c, n):
    print(json.dumps(e))
PY

# --- hit path
out="$("$WATCH" --from-file "$tmp/sample.jsonl" 2>&1)"; rc=$?
check "hits exit 0" "$rc" "0"
f="$SA_ERROR_WATCH_INBOX_DIR/2026-10-16-sa-error-watch.md"
[[ -f "$f" ]] && ok "inbox file written" || bad "inbox file missing: $out"
check "counts 2 distinct errors, not duplicates" "$(grep -c '^- status: 1x' "$f")" "2"
check "one ask line" "$(grep -c '^- ask: ' "$f")" "1"
grep -q 'sa-app-error' "$f" && grep -q 'vercel.com/straightaway/straightaway-next/logs' "$f" && ok "ask carries search and link" || bad "ask lacks search or link"
check "ask has exactly 2 ' | ' separators" "$(grep '^- ask: ' "$f" | grep -o ' | ' | wc -l | tr -d ' ')" "2"
grep -q 'd111' "$f" && ok "digest listed" || bad "digest missing"
[[ ! -e "$SA_ERROR_WATCH_STATE" ]] && ok "--from-file leaves state alone" || bad "--from-file wrote state"
"$WATCH" --from-file "$tmp/sample.jsonl" >/dev/null 2>&1
check "same-day rerun appends, keeps earlier report" "$(grep -c '^- ask: ' "$f")" "2"

# --- zero-hit path: no ping
rm -rf "$SA_ERROR_WATCH_INBOX_DIR"
print -r -- '{"id":"n1","timestamp":1,"level":"info","message":"","logs":[]}' > "$tmp/none.jsonl"
out="$("$WATCH" --from-file "$tmp/none.jsonl" 2>&1)"; rc=$?
check "zero hits exit 0" "$rc" "0"
[[ ! -e "$SA_ERROR_WATCH_INBOX_DIR" ]] && ok "zero hits write nothing" || bad "zero hits wrote an inbox"

# --- fail loud: CLI exits non-zero, garbage output; state must not advance
mkdir -p "$tmp/bin"
print -r -- '#!/bin/sh
echo "Error: Response Error (400)" >&2; exit 1' > "$tmp/bin/vercel-fail"
print -r -- '#!/bin/sh
echo "not json"; exit 0' > "$tmp/bin/vercel-garbage"
print -r -- '#!/bin/sh
exit 0' > "$tmp/bin/vercel-empty"
chmod +x $tmp/bin/*
out="$(SA_ERROR_WATCH_VERCEL="$tmp/bin/vercel-fail" "$WATCH" 2>&1)"; rc=$?
check "CLI failure exits 1" "$rc" "1"
[[ "$out" == *"Response Error (400)"* ]] && ok "CLI failure message surfaced" || bad "CLI failure message lost: $out"
out="$(SA_ERROR_WATCH_VERCEL="$tmp/bin/vercel-garbage" "$WATCH" 2>&1)"; rc=$?
check "unparseable output exits 1" "$rc" "1"
out="$(SA_ERROR_WATCH_VERCEL="$tmp/bin/does-not-exist" "$WATCH" 2>&1)"; rc=$?
check "missing CLI exits 1" "$rc" "1"
[[ ! -e "$SA_ERROR_WATCH_STATE" ]] && ok "failures leave state alone" || bad "a failed run advanced state"

# --- success through the real fetch path advances state
out="$(SA_ERROR_WATCH_VERCEL="$tmp/bin/vercel-empty" "$WATCH" 2>&1)"; rc=$?
check "empty successful query exits 0" "$rc" "0"
check "state holds the window end" "$(cat "$SA_ERROR_WATCH_STATE")" "$(python3 -c 'import datetime;print(int(datetime.datetime.fromisoformat("2026-10-16T08:00:00-07:00").timestamp()))')"

print -- "$pass passed, $fail failed"
(( fail == 0 ))

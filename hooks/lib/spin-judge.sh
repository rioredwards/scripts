#!/usr/bin/env bash
# spin-judge.sh VIEW_FILE: the spin-check final-reply judge (L-0108). A Codex
# run on Rio's ChatGPT plan (no API billing) that reads the fixed view from
# spin_view.py and may grep the transcript before it flags anything.
# Prints {verdict, items, ms, error}; verdict pass | flag | error. Every quote
# must appear in the view (normalized), else the item is dropped as unquoted.
#   AGENT_SPIN_JUDGE_MODEL   default gpt-6-luna
#   AGENT_SPIN_JUDGE_EFFORT  default low
#   AGENT_SPIN_JUDGE_SECS    default 110
#   AGENT_SPIN_JUDGE_LOG     copy Codex's run log here (debug)
set -uo pipefail
VIEW="$1"
DIR="$HOME/scripts/hooks/lib/spin-judge"
WORK="$(mktemp -d -t spin-judge)"
trap 'rm -rf "$WORK"' EXIT
start=$(python3 -c 'import time; print(int(time.time()*1000))')
# --ignore-user-config + --disable hooks: the judge must not fire Rio's own
# hooks (they would review the judge). AGENT_DELEGATE=1 is the backstop.
cat "$DIR/prompt.md" "$VIEW" | AGENT_DELEGATE=1 timeout -k 5 "${AGENT_SPIN_JUDGE_SECS:-110}" codex exec \
  --ephemeral --ignore-user-config --skip-git-repo-check --disable hooks \
  -s read-only -C "$WORK" \
  -m "${AGENT_SPIN_JUDGE_MODEL:-gpt-6-luna}" -c "model_reasoning_effort=${AGENT_SPIN_JUDGE_EFFORT:-low}" \
  --output-schema "$DIR/schema.json" -o "$WORK/out.json" - > "$WORK/log" 2>&1
rc=$?
[ -n "${AGENT_SPIN_JUDGE_LOG:-}" ] && cp "$WORK/log" "$AGENT_SPIN_JUDGE_LOG"
ms=$(( $(python3 -c 'import time; print(int(time.time()*1000))') - start ))
if [ $rc -ne 0 ] || ! jq -e '.verdict' "$WORK/out.json" >/dev/null 2>&1; then
  err="$( [ $rc -eq 124 ] && echo "timed out" || echo "codex exec rc=$rc" ): $(tail -c 300 "$WORK/log" | tr '\n\t' '  ')"
  jq -nc --arg e "$err" --argjson ms "$ms" '{verdict:"error", items:[], ms:$ms, error:$e}'
  exit 0
fi
python3 - "$VIEW" "$WORK/out.json" "$ms" <<'PY'
import json, re, sys
norm = lambda s: re.sub(r"\s+", " ", s).strip().lower().rstrip(".")
view = norm(open(sys.argv[1], encoding="utf-8", errors="replace").read())
out = json.load(open(sys.argv[2]))
kept, unquoted = [], []
for it in out.get("items") or []:
    q = norm(it.get("quote") or "")
    (kept if q and q in view else unquoted).append(it)
print(json.dumps({"verdict": "flag" if kept else "pass", "items": kept,
                  "unquoted": len(unquoted), "ms": int(sys.argv[3]), "error": ""}))
PY

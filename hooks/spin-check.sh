#!/usr/bin/env bash
# spin-check.sh — periodic outside-perspective sanity check for long agent runs.
#
# Fires from a global PostToolUse hook. Every Nth tool call it sends a digest of
# the recent transcript to a DIFFERENT model (gpt-5.6-luna via agent-router) and asks
# the one question a stuck agent never asks itself: "am I spinning or tunnel-
# visioned?" If the outside model says yes, its course-correction is injected
# back into the running session (stderr + exit 2 — the PostToolUse feedback path).
#
# Rationale: a tunnel-visioned agent will not volunteer to ask for help, so the
# check must be involuntary. This hook is that involuntary safety net.
#
# CONTEXT the reviewer sees (two complementary sources — this is the whole point):
#   1. session-handoff `peek` — the SAME clean extraction /session-handoff uses.
#      Wrapper-stripped original task + narrative (assistant reasoning + notable
#      errors), deduped, indexed. Far cleaner than a raw `jq` grab, and it nails
#      the original task through /clear + hook banners + <system-reminder> noise.
#      BUT session-handoff filters out tool_use blocks, so on its own it is blind
#      to the mechanical spin signal.
#   2. raw tool-call trace (this script) — `TOOL <name> <input>` from the tail of
#      the JSONL, the exact sequence peek drops. This is what reveals "same action
#      3x" and "thrashing one file", the highest-confidence loop evidence.
#   If session-handoff is missing/fails, we fall back to a self-contained jq
#   extraction so the hook still works.
#
# Settings follow the agent-hooks convention: profile vars live in
# ~/.dotfiles/zsh/profiles/agent-hooks.sh, loaded by agent-hooks-env.sh; any var
# already set in the environment overrides the profile (opt-in per run).
#
#   AGENT_SPIN_CHECK           on | off   (default off — dormant until enabled)
#   AGENT_SPIN_CHECK_EVERY     fire every Nth tool call        (default 20)
#   AGENT_SPIN_CHECK_MODEL     reviewer model                  (default gpt-5.6-luna)
#   AGENT_SPIN_CHECK_PROVIDER  agent-router provider           (default codex)
#   AGENT_SPIN_CHECK_TIMEOUT   seconds to wait on the reviewer (default 90)
#   AGENT_SPIN_CHECK_LOG       audit log path (default $STATE_DIR/fires.log;
#                              set to "off" to disable)
#
# Enable for one run:  AGENT_SPIN_CHECK=on claude ...

set -uo pipefail

# --- load the shared agent-hooks profile (env wins over profile) ----------
[ -f "$HOME/scripts/agent-hooks-env.sh" ] && . "$HOME/scripts/agent-hooks-env.sh"

# --- opt-in gate -----------------------------------------------------------
[ "${AGENT_SPIN_CHECK:-off}" = "on" ] || exit 0
command -v agent-router >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

EVERY="${AGENT_SPIN_CHECK_EVERY:-20}"
PROVIDER="${AGENT_SPIN_CHECK_PROVIDER:-codex}"
MODEL="${AGENT_SPIN_CHECK_MODEL:-gpt-5.6-luna}"
WAIT="${AGENT_SPIN_CHECK_TIMEOUT:-90}"

# --- per-session tool-call counter ----------------------------------------
STATE_DIR="${TMPDIR:-/tmp}/claude-spin-check"
mkdir -p "$STATE_DIR"
# opportunistic GC so count/log files don't accumulate forever in TMPDIR.
find "$STATE_DIR" -type f \( -name '*.count' -o -name '*.err' -o -name '*.failed' \) -mtime +1 -delete 2>/dev/null
COUNT_FILE="$STATE_DIR/${SESSION_ID}.count"
COUNT=$(( $(cat "$COUNT_FILE" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$COUNT" > "$COUNT_FILE"
[ $(( COUNT % EVERY )) -eq 0 ] || exit 0

LOG="${AGENT_SPIN_CHECK_LOG:-$STATE_DIR/fires.log}"

# --- ORIGINAL TASK + NARRATIVE via session-handoff peek -------------------
# Reuse the /session-handoff extraction: wrapper-stripped, deduped, indexed.
# `.session.first` = the real first ask (survives /clear + hook banners +
# <system-reminder> preamble that a naive jq grab trips on). `.messages` =
# recent assistant reasoning + notable errors/results, already trimmed.
TASK=""
NARRATIVE=""
CTX_SOURCE="fallback"
if command -v session-handoff >/dev/null 2>&1; then
  PEEK="$(session-handoff peek "claude:${SESSION_ID}" --format json --messages 16 --chars 6000 2>/dev/null || true)"
  if [ -n "$PEEK" ]; then
    TASK="$(printf '%s' "$PEEK" | jq -r '.session.first // .session.title // empty' 2>/dev/null | cut -c1-600)"
    [ -n "$TASK" ] && CTX_SOURCE="session-handoff peek"
    NARRATIVE="$(printf '%s' "$PEEK" | jq -r '
      .messages[]?
      | (.role // "?" | ascii_upcase) + ": " + ((.text // "") | gsub("\\s+"; " ") | .[0:400])
    ' 2>/dev/null | tail -n 14)"
  fi
fi

# Fallback: self-contained jq extraction if session-handoff is unavailable or
# returned nothing (keeps the hook working on machines without the CLI).
if [ -z "$TASK" ]; then
  TASK="$(jq -rc '
    select(.type=="user")
    | (.message.content // empty)
    | if type=="string" then .
      else (map(select(.type=="text") | .text) | join(" "))
      end
  ' "$TRANSCRIPT" 2>/dev/null | grep -vE '^[[:space:]]*(<|$)' | head -n1 | cut -c1-600)"
  [ -n "$TASK" ] || TASK="(unknown — could not extract; do NOT judge task drift)"
fi
if [ -z "$NARRATIVE" ]; then
  NARRATIVE="$(tail -n 120 "$TRANSCRIPT" 2>/dev/null | jq -rc '
    select(.type=="user" or .type=="assistant")
    | (.message.content // []) as $c
    | if .type=="assistant" then
        ( $c[]? | select(.type=="text") | "ASSISTANT: " + ((.text // "") | .[0:400]) )
      else
        ( $c[]? | select(.type=="tool_result")
          | "RESULT: " + (( (.content | if type=="array" then map(.text // "") | join(" ") else tostring end) ) | .[0:280]) )
      end
  ' 2>/dev/null | tail -n 14)"
fi

# --- RECENT TOOL CALLS — the mechanical loop signal peek cannot see --------
# `tool_use` name + trimmed input, tail of the JSONL. This is where "same action
# repeated 3x" and "file thrash" actually show up. session-handoff drops these.
TRACE="$(tail -n 200 "$TRANSCRIPT" 2>/dev/null | jq -rc '
  select(.type=="assistant")
  | (.message.content // [])[]?
  | select(.type=="tool_use")
  | "TOOL " + (.name // "?") + " " + ((.input | tostring) | gsub("\\s+"; " ") | .[0:200])
' 2>/dev/null | tail -n 24)"

# Nothing to judge on -> stay silent.
[ -n "$NARRATIVE$TRACE" ] || exit 0
[ -n "$TASK" ] || TASK="(unknown — could not extract; do NOT judge task drift)"
[ -n "$TRACE" ] || TRACE="(no tool calls captured)"
[ -n "$NARRATIVE" ] || NARRATIVE="(no narrative captured)"

# --- ask the outside model ------------------------------------------------
read -r -d '' PROMPT <<EOF || true
You are a skeptical senior engineer doing a quick sanity check on another AI
coding agent's live session. You see a KEYHOLE view: only its recent actions,
trimmed. You do NOT see the full context, the files, or the complete results.

Your job is to catch ONLY clear, high-confidence failure. Default to silence.
A false alarm is WORSE than a miss: it derails an agent that was working fine.

Reply "ON TRACK" (nothing else) if ANY of these hold:
  - You are not highly confident it is stuck.
  - You lack the context to judge what it is doing or why.
  - It is making forward progress, even if slow or messy.
  - The apparent "problem" could be a normal mid-task step whose payoff is
    outside this keyhole.

Reply "COURSE-CORRECT" ONLY on UNMISTAKABLE evidence of being stuck:
  - the SAME failing action repeated 3+ times (see RECENT TOOL CALLS), or
  - thrashing the same file back and forth with no progress, or
  - clearly abandoning the ORIGINAL TASK below for something unrelated.
Then output: COURSE-CORRECT: <=2 sentences naming the specific repeated failure
and the concrete alternative. Cite the evidence you saw. No generic advice.

When in doubt, ON TRACK. No praise, no summary, no preamble.

ORIGINAL TASK:
$TASK

RECENT NARRATIVE (assistant reasoning + notable errors, trimmed — keyhole):
$NARRATIVE

RECENT TOOL CALLS (the action sequence — read this for loops/thrash):
$TRACE
EOF

# Debug escape hatch: dump the assembled prompt and exit before calling the
# reviewer (AGENT_SPIN_CHECK_DEBUG=1). Handy for verifying context extraction.
if [ "${AGENT_SPIN_CHECK_DEBUG:-0}" = "1" ]; then
  printf 'CONTEXT_SOURCE=%s\n----- PROMPT -----\n%s\n' \
    "${CTX_SOURCE:-unknown}" "$PROMPT" >&2
  exit 0
fi

TIMEOUT_CMD=()
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(gtimeout "$WAIT")
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(timeout "$WAIT")
fi

# --- call the reviewer, capturing WHY it failed ---------------------------
# This used to be `2>/dev/null || true`. Router outage, timeout, a bad model
# name, and a genuine "nothing to report" all collapsed into the same empty
# string, and the hook went quiet for the rest of the session with no signal.
# A safety net that cannot report its own death is not a safety net. Capture
# stderr and the exit code, classify the failure, log the reason, and tell the
# session — once, so a broken router doesn't turn into an alert storm.
ERR_FILE="$STATE_DIR/${SESSION_ID}.err"
# AGENT_DELEGATE tells the reviewer's own turn-end hook that its reply is input
# for this session, not a turn Rio asked for — without it every probe delivered
# a phone text, a TTS clip and a web view page saying "on track".
VERDICT="$( AGENT_DELEGATE=1 ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} agent-router delegate --provider "$PROVIDER" --model "$MODEL" --prompt "$PROMPT" 2>"$ERR_FILE" )"
RC=$?
VERDICT="$(printf '%s' "$VERDICT" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
ERR_TAIL="$(tr '\n\t' '  ' < "$ERR_FILE" 2>/dev/null | sed 's/  */ /g' | cut -c1-300)"

FAILURE=""
case "$RC" in
  0)       [ -n "$VERDICT" ] || FAILURE="reviewer returned an empty verdict (exit 0)" ;;
  124|142) FAILURE="reviewer timed out after ${WAIT}s" ;;
  *)       FAILURE="agent-router exited $RC" ;;
esac

# --- audit log (append one line per fire; disable with AGENT_SPIN_CHECK_LOG=off)
if [ "$LOG" != "off" ]; then
  LOG_SUFFIX=""
  [ -n "$FAILURE" ] && LOG_SUFFIX="$(printf '\tFAILED=%s\terr=%s' "$FAILURE" "${ERR_TAIL:-<no stderr>}")"
  { printf '%s\tsid=%s\tcount=%s\tmodel=%s\trc=%s\tverdict=%s%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SESSION_ID" "$COUNT" "$MODEL" "$RC" \
      "$(printf '%s' "${VERDICT:-<empty>}" | tr '\n' ' ' | cut -c1-200)" \
      "$LOG_SUFFIX" \
      >> "$LOG"; } 2>/dev/null
fi

# --- the reviewer is broken: say so, loudly, once per session -------------
if [ -n "$FAILURE" ]; then
  NOTICE_FILE="$STATE_DIR/${SESSION_ID}.failed"
  [ -f "$NOTICE_FILE" ] && exit 0
  : > "$NOTICE_FILE"
  printf '⚠️ SPIN-CHECK IS BROKEN — %s.\nThe outside-view safety net is NOT running this session; nothing is watching for spin.\nstderr: %s\nLog: %s\nFix `agent-router delegate --provider %s --model %s`, or silence it with `agent-toggle spin-check off`.\n(Reported once per session.)\n' \
    "$FAILURE" "${ERR_TAIL:-<no stderr>}" "$LOG" "$PROVIDER" "$MODEL" >&2
  exit 2
fi

case "$VERDICT" in
  ON\ TRACK*|on\ track*|"ON TRACK") exit 0 ;;
esac

# --- inject the course-correction into the running session ----------------
# PostToolUse: stderr + exit 2 is fed back to the main agent as feedback.
# Framed as a heuristic, not a command: a cheap outside model on a keyhole view
# is often wrong. The main agent should weigh it, not obey it.
printf '🔍 SPIN-CHECK (heuristic outside view via %s, after %s tool calls — it sees only a trimmed keyhole and is often wrong; if it misreads your state, note why in one line and carry on):\n%s\n' \
  "$MODEL" "$COUNT" "$VERDICT" >&2
exit 2

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
# Settings follow the agent-hooks convention: profile vars live in
# ~/.dotfiles/zsh/profiles/agent-hooks.sh, loaded by agent-hooks-env.sh; any var
# already set in the environment overrides the profile (opt-in per run).
#
#   AGENT_SPIN_CHECK           on | off   (default off — dormant until enabled)
#   AGENT_SPIN_CHECK_EVERY     fire every Nth tool call        (default 20)
#   AGENT_SPIN_CHECK_MODEL     reviewer model                  (default gpt-5.6-luna)
#   AGENT_SPIN_CHECK_PROVIDER  agent-router provider           (default codex)
#   AGENT_SPIN_CHECK_TIMEOUT   seconds to wait on the reviewer (default 90)
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
COUNT_FILE="$STATE_DIR/${SESSION_ID}.count"
COUNT=$(( $(cat "$COUNT_FILE" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$COUNT" > "$COUNT_FILE"
[ $(( COUNT % EVERY )) -eq 0 ] || exit 0

# --- build a compact digest of recent activity ----------------------------
# Pull the last chunk of the JSONL transcript: assistant reasoning, the tools it
# ran (name + trimmed input), and trimmed tool results. Enough to judge whether
# it is looping, without shipping the whole session.
DIGEST="$(tail -n 120 "$TRANSCRIPT" 2>/dev/null | jq -rc '
  select(.type=="user" or .type=="assistant")
  | (.message.content // []) as $c
  | if .type=="assistant" then
      ( $c[]? | select(.type=="text")     | "ASSISTANT: " + ((.text // "")            | .[0:500]) ),
      ( $c[]? | select(.type=="tool_use") | "TOOL "      + (.name // "?") + " " + ((.input | tostring) | .[0:200]) )
    else
      ( $c[]? | select(.type=="tool_result")
        | "RESULT: " + (( (.content | if type=="array" then map(.text // "") | join(" ") else tostring end) ) | .[0:280]) )
    end
' 2>/dev/null | tail -n 70)"

[ -n "$DIGEST" ] || exit 0

# --- extract the ORIGINAL TASK (first real user prompt, top of transcript) --
# The digest is only the tail, so "drift off the original task" can't be judged
# without this. Grab the first user message that carries actual text (skip
# tool_result entries and hook/meta noise).
TASK="$(jq -rc '
  select(.type=="user")
  | (.message.content // empty)
  | if type=="string" then .
    else (map(select(.type=="text") | .text) | join(" "))
    end
' "$TRANSCRIPT" 2>/dev/null | grep -vE '^[[:space:]]*(<|$)' | head -n1 | cut -c1-600)"
[ -n "$TASK" ] || TASK="(unknown — could not extract; do NOT judge task drift)"

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
  - the SAME failing action repeated 3+ times, or
  - thrashing the same file back and forth with no progress, or
  - clearly abandoning the ORIGINAL TASK below for something unrelated.
Then output: COURSE-CORRECT: <=2 sentences naming the specific repeated failure
and the concrete alternative. Cite the evidence you saw. No generic advice.

When in doubt, ON TRACK. No praise, no summary, no preamble.

ORIGINAL TASK:
$TASK

RECENT ACTIVITY (keyhole, trimmed — not the whole picture):
$DIGEST
EOF

TIMEOUT_BIN=""
command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN="gtimeout ${WAIT}"
[ -z "$TIMEOUT_BIN" ] && command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="timeout ${WAIT}"

VERDICT="$( $TIMEOUT_BIN agent-router delegate --provider "$PROVIDER" --model "$MODEL" --prompt "$PROMPT" 2>/dev/null || true )"
VERDICT="$(printf '%s' "$VERDICT" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

# Silent when fine or when the reviewer failed/empty.
[ -n "$VERDICT" ] || exit 0
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

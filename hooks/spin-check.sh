#!/usr/bin/env bash
# spin-check.sh: periodic outside-perspective sanity check for long agent runs.
#
# Fires from a global PostToolUse hook. Every Nth tool call SINCE RIO LAST SPOKE
# it sends a digest of
# the recent transcript to a DIFFERENT model (gpt-6-luna via agent-router) and asks
# the one question a stuck agent never asks itself: "am I spinning or tunnel-
# visioned?" If the outside model says yes, its course-correction is injected
# back into the running session (stderr + exit 2: the PostToolUse feedback path).
#
# Rationale: a tunnel-visioned agent will not volunteer to ask for help, so the
# check must be involuntary. This hook is that involuntary safety net.
#
# WHY THE COUNTER RESETS ON EVERY USER MESSAGE (UserPromptSubmit registration):
# spin is a function of UNATTENDED runtime, not lifetime tool calls. A session
# where Rio steers every few calls is by definition not tunnel-visioned: he just
# corrected it. Counting from session start meant a chatty, healthy session got
# probed on a fixed clock while its own evidence said "supervised", and a fresh
# 19-call-deep runaway right after a reply was invisible until the arbitrary
# boundary happened to land. Resetting on each user turn makes the trigger mean
# what it should: "this agent has taken N actions since a human last touched it."
#
# CONTEXT the reviewer sees (complementary sources):
#   1. conversation (jq over the JSONL): every message Rio wrote, each paired
#      with the tail of the agent message it answered. This sets the task, so a
#      redirect or a bare "yes" is judged against what it actually meant.
#   2. session-handoff `peek`: recent assistant reasoning + notable errors,
#      deduped. It filters out tool_use blocks, so it is blind to loops.
#   3. raw tool-call trace (this script): `TOOL <name> <input>` from the tail of
#      the JSONL, the exact sequence peek drops. This is what reveals "same action
#      3x" and "thrashing one file", the highest-confidence loop evidence.
#   4. the latest subagent brief and 5. the latest agent message, whole: where
#      unasked changes and unchecked claims live (L-0006, L-0012).
#   If session-handoff is missing/fails, the narrative falls back to a
#   self-contained jq extraction so the hook still works.
#
# Settings follow the agent-hooks convention: profile vars live in
# ~/.dotfiles/zsh/profiles/agent-hooks.sh, loaded by agent-hooks-env.sh; any var
# already set in the environment overrides the profile (opt-in per run).
#
#   AGENT_SPIN_CHECK           on | off   (default off: dormant until enabled)
#   AGENT_SPIN_CHECK_EVERY     fire every Nth tool call since Rio's last
#                              message                         (default 20)
#   AGENT_SPIN_CHECK_MODEL     reviewer model                  (default gpt-6-luna)
#   AGENT_SPIN_CHECK_PROVIDER  agent-router provider           (default codex)
#   AGENT_SPIN_CHECK_TIMEOUT   seconds to wait on the reviewer (default 90)
#   AGENT_SPIN_CHECK_LOG       audit log path (default ~/.cache/spin-check/fires.log;
#                              set to "off" to disable)
#
# The log lives outside TMPDIR on purpose: it is the ONLY evidence of whether the
# reviewer's judgement is any good. Counters are throwaway and stay in TMPDIR;
# the log is the eval corpus. One line per fire, verdict captured whole.
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
EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty')"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // "?"')"
. "$HOME/scripts/hooks/lib/delegate.sh"
hook_is_delegate "$INPUT" && exit 0

# --- per-session tool-call counter ----------------------------------------
STATE_DIR="${TMPDIR:-/tmp}/claude-spin-check"
mkdir -p "$STATE_DIR"
# opportunistic GC so count/log files don't accumulate forever in TMPDIR.
find "$STATE_DIR" -type f \( -name '*.count' -o -name '*.err' -o -name '*.failed' \) -mtime +1 -delete 2>/dev/null
COUNT_FILE="$STATE_DIR/${SESSION_ID}.count"

# --- UserPromptSubmit: Rio just spoke, so the clock restarts ---------------
# Registered on UserPromptSubmit as well as PostToolUse. Deleting the counter is
# the whole job here; the next tool call starts again at 1.
if [ "$EVENT" = "UserPromptSubmit" ]; then
  rm -f "$COUNT_FILE"
  exit 0
fi

[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0


EVERY="${AGENT_SPIN_CHECK_EVERY:-20}"
PROVIDER="${AGENT_SPIN_CHECK_PROVIDER:-codex}"
MODEL="${AGENT_SPIN_CHECK_MODEL:-gpt-6-luna}"
WAIT="${AGENT_SPIN_CHECK_TIMEOUT:-90}"

# Canonical source-priority and don't-hand-roll rules live in the explore skill;
# the prompt cites these paths instead of restating them, so the rules can evolve
# in one place. The reviewer runs under `codex exec` and can read them.
EXPLORE_REF="${SKILLS:-$HOME/dev/agent-skills}/plugins/core/skills/explore/ref"

# --- tool calls since Rio last spoke --------------------------------------
COUNT=$(( $(cat "$COUNT_FILE" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$COUNT" > "$COUNT_FILE"
[ $(( COUNT % EVERY )) -eq 0 ] || exit 0

SOURCE_AGENT=claude
if [ "$(head -n 1 "$TRANSCRIPT" | jq -r '.type // empty')" = session_meta ]; then
  SOURCE_AGENT=codex
  NORMALIZED="$(mktemp -t spin-transcript)"
  trap 'rm -f "$NORMALIZED"' EXIT
  jq -c -f "$HOME/scripts/hooks/lib/spin-transcript.jq" "$TRANSCRIPT" > "$NORMALIZED" || exit 1
  TRANSCRIPT="$NORMALIZED"
fi


LOG_DIR="$HOME/.cache/spin-check"
mkdir -p "$LOG_DIR"
LOG="${AGENT_SPIN_CHECK_LOG:-$LOG_DIR/fires.log}"

# --- CONVERSATION: every message Rio wrote, each after the reply it answered
# Judging drift against only the first message flagged healthy sessions as
# DRIFT after Rio redirected them (0 of 51 flags confirmed right, Sep 2-10).
# The last message alone is no better: it is often just "yes". Pairing each of
# Rio's messages with the end of the agent message before it tells the reviewer
# what "yes" approved, and a later ask visibly replaces the earlier one.
# Skips tool results, compaction summaries, interrupts and wrapper text. Keeps
# Rio's first message plus the most recent THREAD_KEEP exchanges. Desktop
# quote-replies start with `<!-- reply -->`; strip it, or the wrapper filter
# drops exactly the messages where Rio pushes back on a quoted line.
THREAD_KEEP=20
THREAD="$(jq -rc '
  if .type=="assistant" then
    (.message.content // [])[]? | select(.type=="text")
    | "A\t" + ((.text // "") | gsub("\\s+"; " ") | .[-400:])
  elif .type=="user" and (.isMeta // false | not) and (.isCompactSummary // false | not) then
    (.message.content // empty)
    | (if type=="string" then . else (map(select(.type=="text") | .text) | join(" ")) end)
    | sub("^\\s*<!-- reply -->"; "")
    | gsub("\\s+"; " ")
    | select(test("^ *(<|$|\\[Request interrupted|Caveat:|Base directory for this skill|This session is being continued)") | not)
    | "U\t" + .[0:500]
  else empty end
' "$TRANSCRIPT" 2>/dev/null | awk -F'\t' -v keep="$THREAD_KEEP" '
  $1=="A" { a=$2; next }
  $1=="U" { n++; p[n]="AGENT: " (a=="" ? "(no reply text)" : "..." a) "\nRIO: " $2; a="" }
  END {
    if (n == 0) exit
    print p[1]
    start = n - keep + 1; if (start < 2) start = 2
    if (start > 2) printf "\n(%d earlier exchanges omitted)\n", start - 2
    for (i = start; i <= n; i++) print "\n" p[i]
  }')"
[ -n "$THREAD" ] || THREAD="(unknown, could not extract; do NOT judge task drift)"

# --- NARRATIVE via session-handoff peek -----------------------------------
# Reuse the /session-handoff extraction: wrapper-stripped, deduped, indexed.
# `.messages` = a start-middle-end window of the transcript within a token
# budget (agent-sessions window.py), so the latest turns are always present.
NARRATIVE=""
CTX_SOURCE="fallback"
if command -v session-handoff >/dev/null 2>&1; then
  PEEK="$(session-handoff peek "${SOURCE_AGENT}:${SESSION_ID}" --format json --tokens 1500 2>/dev/null || true)"
  if [ -n "$PEEK" ]; then
    NARRATIVE="$(printf '%s' "$PEEK" | jq -r '
      .messages[]?
      | (.role // "?" | ascii_upcase) + ": " + ((.text // "") | gsub("\\s+"; " ") | .[0:400])
    ' 2>/dev/null | tail -n 14)"
    [ -n "$NARRATIVE" ] && CTX_SOURCE="session-handoff peek"
  fi
fi

# Fallback: self-contained jq extraction if session-handoff is unavailable or
# returned nothing (keeps the hook working on machines without the CLI).
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

# --- RECENT TOOL CALLS: the mechanical loop signal peek cannot see --------
# `tool_use` name + trimmed input, tail of the JSONL. This is where "same action
# repeated 3x" and "file thrash" actually show up. session-handoff drops these.
TRACE="$(tail -n 200 "$TRANSCRIPT" 2>/dev/null | jq -rc '
  select(.type=="assistant")
  | (.message.content // [])[]?
  | select(.type=="tool_use")
  | "TOOL " + (.name // "?") + " " + ((.input | tostring) | gsub("\\s+"; " ") | .[0:200])
' 2>/dev/null | tail -n 24)"

# --- LATEST SUBAGENT BRIEF: what an orchestrator told a helper to change ---
# The trace trims each input to 200 chars, so a brief's change list (where an
# unasked change hides) is invisible there.
BRIEF="$(tail -n 200 "$TRANSCRIPT" 2>/dev/null | jq -rc '
  select(.type=="assistant")
  | (.message.content // [])[]?
  | select(.type=="tool_use" and (.name=="Agent" or .name=="Task"))
  | (.input.prompt // "") | gsub("\\s+"; " ") | .[0:3000]
' 2>/dev/null | tail -n 1)"
[ -n "$BRIEF" ] || BRIEF="(none in view)"

# --- LATEST AGENT MESSAGE, whole: the narrative cuts each to 400 chars, which
# hides the claims and announced changes a report makes past its opening.
# Only one written since the last incoming message: an older one read as the
# answer to Rio's newest message (a stale "still waiting on you" after "merged").
LAST_MSG="$(tail -n 200 "$TRANSCRIPT" 2>/dev/null | jq -rc '
  if .type=="assistant" then
    (.message.content // [])[]? | select(.type=="text")
    | "A\t" + ((.text // "") | gsub("\\s+"; " ") | .[0:2500])
  elif .type=="user" and (.isMeta // false | not)
    and ((.message.content | type)=="string"
         or ([.message.content[]? | select(.type=="text")] | length) > 0) then "U"
  else empty end
' 2>/dev/null | awk -F'\t' '$1=="U" { m="" } $1=="A" { m=$2 } END { print m }')"
[ -n "$LAST_MSG" ] || LAST_MSG="(none since the last incoming message)"

# Nothing to judge on -> stay silent.
[ -n "$NARRATIVE$TRACE" ] || exit 0
[ -n "$TRACE" ] || TRACE="(no tool calls captured)"
[ -n "$NARRATIVE" ] || NARRATIVE="(no narrative captured)"

# --- ask the outside model ------------------------------------------------
read -r -d '' PROMPT <<EOF || true
You are a skeptical senior engineer checking another AI coding agent's live
session through a KEYHOLE: recent actions only, trimmed. You cannot see the files
or full context.

Catch only clear, high-confidence failure, a false alarm is WORSE than a miss.
Reply "ON TRACK" (nothing else) unless you are highly confident; slow or messy
progress is still progress.

COURSE-CORRECT only on unmistakable evidence of:
- LOOP: same failing action 3+ times, or thrashing one file.
- DRIFT: silently abandoned what Rio CURRENTLY wants for something
  unrelated. Rio's latest messages set the task, not his first.
- WRONG SOURCE: spelunking vendor code, system files or huge logs when docs,
  \`--help\` or the web rank higher on the §4 ladder in
  $EXPLORE_REF/explore-core.md.
- HAND-ROLLING: writing what a library already does (parsing, env, auth,
  validation, icons/SVG, UI). Rio prefers third-party; see
  $EXPLORE_REF/tool-scout.md.
- CONSTRAINT TAX: an elaborate workaround serving a constraint Rio or the docs
  set; the constraint may be what's wrong. Ask Rio.
- OVERRUN: effort far past what Rio's latest request implies. Ask Rio.
- PING-PONG: trading turns with another agent without converging.
- UNASKED CHANGE: silently changing something Rio did not ask to change
  (approved wording or design, behavior, names, extra features), including
  via a subagent brief. Say what changed and defend why, or keep it.
Departing from a plan or approval is fine, often right, when new evidence
calls for it: never flag a departure the agent names out loud with its reason.
Rigid loyalty to a plan the evidence has outgrown is a failure too.
- UNVERIFIED CLAIM: the agent states as fact what code, a rule, a legacy app or
  a past decision says, with no tool call in view that checked it. Verify it
  or label it a guess.

Output \`COURSE-CORRECT: <=2 sentences\` citing evidence and one concrete
alternative. No generic advice or preamble. When in doubt, ON TRACK.

CONVERSATION (every message from Rio, oldest first, each shown after the tail
of the agent message it answered. Later messages override earlier ones: a
short "yes" or "go" approves what the agent proposed just before it, and a new
ask replaces the old task):
$THREAD

RECENT NARRATIVE (assistant reasoning + notable errors, trimmed, keyhole):
$NARRATIVE

RECENT TOOL CALLS (the action sequence: read this for loops/thrash):
$TRACE

LATEST SUBAGENT BRIEF (what the agent told a helper to build or change):
$BRIEF

LATEST AGENT MESSAGE (whole: check its claims and announced changes):
$LAST_MSG
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
# session: once, so a broken router doesn't turn into an alert storm.
ERR_FILE="$STATE_DIR/${SESSION_ID}.err"
# AGENT_DELEGATE tells the reviewer's own turn-end hook that its reply is input
# for this session, not a turn Rio asked for: without it every probe delivered
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
  # cwd and the WHOLE verdict, not a 200-char stub: a truncated COURSE-CORRECT
  # is exactly the line an eval needs to read in full.
  { printf '%s\tsid=%s\tcount=%s\tcwd=%s\tmodel=%s\trc=%s\tverdict=%s%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SESSION_ID" "$COUNT" "$CWD" "$MODEL" "$RC" \
      "$(printf '%s' "${VERDICT:-<empty>}" | tr '\n\t' '  ')" \
      "$LOG_SUFFIX" \
      >> "$LOG"; } 2>/dev/null
fi

# --- the reviewer is broken: say so, loudly, once per session -------------
if [ -n "$FAILURE" ]; then
  NOTICE_FILE="$STATE_DIR/${SESSION_ID}.failed"
  [ -f "$NOTICE_FILE" ] && exit 0
  : > "$NOTICE_FILE"
  printf '⚠️ SPIN-CHECK IS BROKEN, %s.\nThe outside-view safety net is NOT running this session; nothing is watching for spin.\nstderr: %s\nLog: %s\nFix `agent-router delegate --provider %s --model %s`, or silence it with `agent-toggle spin-check off`.\n(Reported once per session.)\n' \
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
printf '🔍 SPIN-CHECK (heuristic outside view via %s, after %s tool calls with no input from Rio. It sees only a trimmed keyhole and is often wrong; if it misreads your state, note why in one line and carry on):\n%s\n' \
  "$MODEL" "$COUNT" "$VERDICT" >&2
exit 2

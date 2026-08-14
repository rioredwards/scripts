#!/bin/sh
# run.sh — one hook that enforces every rule in rules.json.
#
# PILOT. The bet: Rio's guard hooks (rm-guard, issue-skill-guard, reply-cap,
# loop-reminder) are all the same 30 lines of jq plumbing with a different
# regex and a different sentence. If that is true, a new rule should be a
# JSON entry, not a new script.
#
#   usage:  run.sh <tool|response> [claude|codex]     payload on stdin
#
#   tool      -> Claude PreToolUse. Can remind or deny.
#   response  -> Claude/Codex Stop. Can remind (bounces the reply back).
#
# Fails OPEN everywhere. A broken rules file must never wedge an agent — that
# is the one place Rio's fail-fast-and-loud rule is the wrong call, because the
# blast radius is every tool call on the machine. `validate.sh` is where a bad
# rule is supposed to fail loudly, before it ships.
set -u

KIND="${1:-}"
AGENT="${2:-claude}"
RULES="${AGENT_RULES_FILE:-$HOME/scripts/hooks/rules/rules.json}"

[ "$KIND" = "tool" ] || [ "$KIND" = "response" ] || exit 0
[ -r "$RULES" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD="$(cat)"
[ -n "$PAYLOAD" ] || exit 0

TOOL=""; INPUT=""; TEXT=""
if [ "$KIND" = "tool" ]; then
  TOOL="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null)"
  INPUT="$(printf '%s' "$PAYLOAD" | jq -r '(.tool_input.command // (.tool_input | tostring)) // empty' 2>/dev/null)"
  [ -n "$TOOL" ] || exit 0
else
  # A bounced reply gets rewritten, and the rewrite fires Stop again. Let the
  # second pass through or the agent never finishes the turn.
  [ "$(printf '%s' "$PAYLOAD" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
  TEXT="$(printf '%s' "$PAYLOAD" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
  [ -n "$TEXT" ] || exit 0
fi

VERDICT="$(
  printf '%s' '{}' | jq -r \
    --slurpfile cfg "$RULES" \
    --arg kind "$KIND" --arg tool "$TOOL" --arg input "$INPUT" --arg text "$TEXT" '
  def m($re; $subject):
    if (($re // "") == "") then true else ($subject | test($re)) end;

  def subject: if $kind == "tool" then $input else $text end;

  def hit($r):
    (if $kind == "tool"
     then m($r.match.tool; $tool) and m($r.match.input; $input)
     else m($r.match.text; $text) end)
    and (($r.unless // "") == "" or (subject | test($r.unless) | not));

  [ (($cfg[0].rules) // [])[]
    | select(.on == $kind)
    | select(hit(.)) ]                      as $fired
  | ($fired | map(select(.do == "deny")))   as $denies
  | if ($fired | length) == 0 then "none\t\t"
    elif ($denies | length) > 0 and $kind == "tool"
      then "deny\t" + ($denies[0].id) + "\t" + ($denies[0].text)
    else "remind\t"
      + ($fired | map(.id) | join(","))  + "\t"
      + ($fired | map(.text) | join(" "))
    end
' 2>/dev/null
)" || exit 0

DECISION="$(printf '%s' "$VERDICT" | cut -f1)"
IDS="$(printf '%s' "$VERDICT" | cut -f2)"
MSG="$(printf '%s' "$VERDICT" | cut -f3-)"
[ "$DECISION" = "deny" ] || [ "$DECISION" = "remind" ] || exit 0
[ -n "$MSG" ] || exit 0

if [ "$KIND" = "tool" ]; then
  # Claude PreToolUse. `allow` on a remind is deliberate: it suppresses the
  # permission prompt so the nudge never turns into a question for Rio.
  if [ "$DECISION" = "deny" ]; then
    jq -n --arg r "$MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse",
      permissionDecision:"deny", permissionDecisionReason:$r}}'
  else
    jq -n --arg c "NUDGE (non-blocking, Rio was not asked): $MSG" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",
        permissionDecision:"allow", additionalContext:$c}}'
  fi
  exit 0
fi

# Stop. Exit 2 hands stderr back to the agent and makes it answer again.
# Verified on Claude. Codex uses the same payload field names (see
# note-on-turn/codex-note-on-turn) but its blocking contract is unconfirmed.
printf 'Rule triggered (%s): %s\n' "$IDS" "$MSG" >&2
exit 2

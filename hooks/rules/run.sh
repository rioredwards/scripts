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

TOOL=""; INPUT=""; CONTENT=""; TEXT=""; LIMITED=false
if [ "$KIND" = "tool" ]; then
  TOOL="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null)"
  # Preserve the legacy command/path projection for existing rules.
  INPUT="$(printf '%s' "$PAYLOAD" | jq -r '
    .tool_input | if type == "object" then
      (.command // (del(.file_path, .notebook_path) | tostring))
    else (. // "" | tostring) end
  ' 2>/dev/null)"
  # Whole input for content rules; only known existing-content fields are exempt.
  CONTENT="$(printf '%s' "$PAYLOAD" | jq -r --arg tool "$TOOL" '
    def patch:
      if type == "string" then
        split("\n") | map(select(startswith("-") or startswith(" ") | not)) | join("\n")
      else . end;
    .tool_input
    | if $tool == "Edit" and type == "object" then del(.old_string)
      elif ($tool | test("(^|[._])apply_patch$")) then
        if type == "object" then
          if has("input") then .input |= patch
          elif has("patch") then .patch |= patch else . end
        else patch end
      else . end
    | if . == null then "" elif type == "string" then . else tostring end
  ' 2>/dev/null)"
  [ -n "$TOOL" ] || exit 0
else
  # Ordinary response rules skip rewrites/delegates; scope=all rules still run.
  [ "$(printf '%s' "$PAYLOAD" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && LIMITED=true
  . "$HOME/scripts/hooks/lib/delegate.sh"
  hook_is_delegate "$PAYLOAD" && LIMITED=true
  TEXT="$(printf '%s' "$PAYLOAD" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
  [ -n "$TEXT" ] || exit 0
fi

VERDICT="$(
  printf '%s' '{}' | jq -r \
    --slurpfile cfg "$RULES" \
    --argjson limited "$LIMITED" --arg kind "$KIND" --arg tool "$TOOL" --arg input "$INPUT" --arg content "$CONTENT" --arg text "$TEXT" '
  def m($re; $subject):
    if (($re // "") == "") then true else ($subject | test($re)) end;

  def subject($r): if $kind != "tool" then $text
    elif $r.match.content != null then $content else $input end;

  def hit($r):
    (if $kind == "tool"
     then m($r.match.tool; $tool) and m($r.match.input; $input) and m($r.match.content; $content)
     else m($r.match.text; $text) end)
    and (($r.unless // "") == "" or (subject($r) | test($r.unless) | not));

  [ (($cfg[0].rules) // [])[]
    | select(.on == $kind)
    | select(($limited | not) or .scope == "all")
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

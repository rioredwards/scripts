#!/bin/sh
# delegate.sh: one question, shared by every Rio-facing hook: is this hook
# firing inside a DELEGATE: an agent whose reply goes to another agent, not to
# Rio? Rio-facing behavior (reply cap, response rules, checkpoint nudges, retro
# check-ins) stands down for delegates: Rio never reads their replies, and
# capping or nudging them starves the orchestrator of the detailed report that
# is the delegate's whole job.
#
# Three signals, any one wins:
#   AGENT_DELEGATE=1  exported by whoever spawned the delegate
#                     (agent-router delegate, spin-check)
#   agent_id          present in Claude Code hook payloads only when the tool
#                     call happened inside a native subagent (verified 2026-09-05)
#   originator        "Claude Code" in the Codex transcript's session_meta: the
#                     openai-codex plugin launched it (/codex:rescue, browser-task).
#                     Its shared app-server broker can't pass variables through (2026-09-30).
#
# usage:  . "$HOME/scripts/hooks/lib/delegate.sh"
#         hook_is_delegate "$PAYLOAD" && exit 0
hook_is_delegate() {
  [ -n "${AGENT_DELEGATE:-}" ] && return 0
  command -v jq >/dev/null 2>&1 || return 1
  [ -n "$(printf '%s' "${1:-}" | jq -r '.agent_id // empty' 2>/dev/null)" ] && return 0
  _t="$(printf '%s' "${1:-}" | jq -r '.transcript_path // empty' 2>/dev/null)"
  case "$_t" in *.jsonl) ;; *) return 1 ;; esac
  [ -f "$_t" ] || return 1
  [ "$(head -n 1 "$_t" | jq -r '.payload.originator // empty' 2>/dev/null)" = "Claude Code" ]
}

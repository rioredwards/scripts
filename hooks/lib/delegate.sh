#!/bin/sh
# delegate.sh — one question, shared by every Rio-facing hook: is this hook
# firing inside a DELEGATE — an agent whose reply goes to another agent, not to
# Rio? Rio-facing behavior (reply cap, response rules, checkpoint nudges, retro
# check-ins) stands down for delegates: Rio never reads their replies, and
# capping or nudging them starves the orchestrator of the detailed report that
# is the delegate's whole job.
#
# Two signals, either one wins:
#   AGENT_DELEGATE=1  exported by whoever spawned the delegate
#                     (agent-router delegate, spin-check, the codex MCP server)
#   agent_id          present in Claude Code hook payloads only when the tool
#                     call happened inside a native subagent (verified 2026-09-05)
#
# usage:  . "$HOME/scripts/hooks/lib/delegate.sh"
#         hook_is_delegate "$PAYLOAD" && exit 0
hook_is_delegate() {
  [ -n "${AGENT_DELEGATE:-}" ] && return 0
  command -v jq >/dev/null 2>&1 || return 1
  [ -n "$(printf '%s' "${1:-}" | jq -r '.agent_id // empty' 2>/dev/null)" ]
}

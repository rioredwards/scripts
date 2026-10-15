#!/bin/sh
# Shared agent-hooks profile loader for hook scripts.
#
# Precedence, highest first:
#   1. env vars already set when this file is sourced  (per-run override:
#      `AGENT_SPEAK=on claude ...`)
#   2. ~/.config/agent-hooks/sessions/$AGENT_SESSION_ID.sh: one session's
#      knobs (`agent-toggle --session`). Only when AGENT_SESSION_ID is set;
#      hooks set it from their payload's session_id.
#   3. ~/.config/agent-hooks/local.sh  : machine-local, untracked. Written by
#      `agent-toggle`; wins over the synced profile so a remote flip can't be
#      reverted by a dotfiles auto-sync race. Absent on a fresh machine.
#   4. ~/.dotfiles/zsh/profiles/agent-hooks.sh: tracked, synced defaults.
#
# Implemented by loading session, then local, then the profile, with none ever
# overwriting a value that is already set. Env beats them all because env is
# set before we run; each file beats the ones parsed after it.
#
# Override paths: AGENT_HOOKS_PROFILE, AGENT_HOOKS_LOCAL

AGENT_HOOKS_PROFILE="${AGENT_HOOKS_PROFILE:-${HOME}/.dotfiles/zsh/profiles/agent-hooks.sh}"
AGENT_HOOKS_LOCAL="${AGENT_HOOKS_LOCAL:-${HOME}/.config/agent-hooks/local.sh}"
AGENT_HOOKS_SESSION=""
case "${AGENT_SESSION_ID:-}" in
  ''|*[!A-Za-z0-9_-]*) ;;
  *) AGENT_HOOKS_SESSION="${HOME}/.config/agent-hooks/sessions/${AGENT_SESSION_ID}.sh" ;;
esac
AGENT_HOOKS_SRC=default

_ah_env_override=0
_ah_session_set=0
_ah_local_set=0
_ah_profile_set=0
_ah_local_keys=' '

# _ah_load FILE LAYER: parse `KEY=VAL` / `export KEY=VAL` lines, skipping any
# key that already holds a value. LAYER is `session`, `local` or `profile`.
_ah_load() {
  [ -f "$1" ] || return 0
  while IFS= read -r _ah_line || [ -n "$_ah_line" ]; do
    case "$_ah_line" in
      ''|\#*) continue ;;
      export\ *) _ah_line="${_ah_line#export }" ;;
    esac
    case "$_ah_line" in *=*) ;; *) continue ;; esac
    _ah_key="${_ah_line%%=*}"
    _ah_val="${_ah_line#*=}"
    # Skip anything that isn't a plain shell name: it would break the eval.
    case "$_ah_key" in ''|*[!A-Za-z0-9_]*) continue ;; esac
    if eval "[ -z \"\${${_ah_key}+x}\" ]"; then
      # shellcheck disable=SC2086
      eval "export ${_ah_key}=\"${_ah_val}\""
      if [ "$2" = session ]; then
        _ah_session_set=1
        _ah_local_keys="${_ah_local_keys}${_ah_key} "
      elif [ "$2" = local ]; then
        _ah_local_set=1
        _ah_local_keys="${_ah_local_keys}${_ah_key} "
      else
        _ah_profile_set=1
      fi
    else
      # Already set. That's a real env override only if session/local didn't set it.
      case "$_ah_local_keys" in
        *" ${_ah_key} "*) ;;
        *) _ah_env_override=1 ;;
      esac
    fi
  done < "$1"
}

if [ -n "$AGENT_HOOKS_SESSION" ]; then _ah_load "$AGENT_HOOKS_SESSION" session; fi
_ah_load "$AGENT_HOOKS_LOCAL" local
_ah_load "$AGENT_HOOKS_PROFILE" profile

# shellcheck disable=SC2034  # AGENT_HOOKS_SRC is read by agy-write-guard after sourcing
if [ "$_ah_env_override" -eq 1 ]; then
  AGENT_HOOKS_SRC='env'
elif [ "$_ah_session_set" -eq 1 ]; then
  AGENT_HOOKS_SRC=session
elif [ "$_ah_local_set" -eq 1 ]; then
  AGENT_HOOKS_SRC=local
elif [ "$_ah_profile_set" -eq 1 ]; then
  AGENT_HOOKS_SRC=profile
fi

unset _ah_line _ah_key _ah_val
unset _ah_env_override _ah_session_set _ah_local_set _ah_profile_set _ah_local_keys

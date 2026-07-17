#!/bin/sh
# Shared agent-hooks profile loader for hook scripts.
#
# Precedence, highest first:
#   1. env vars already set when this file is sourced  (per-run override:
#      `AGENT_SPEAK=on claude ...`)
#   2. ~/.config/agent-hooks/local.sh   — machine-local, untracked. Written by
#      `agent-toggle`; wins over the synced profile so a remote flip can't be
#      reverted by a dotfiles auto-sync race. Absent on a fresh machine.
#   3. ~/.dotfiles/zsh/profiles/agent-hooks.sh — tracked, synced defaults.
#
# Implemented by loading local BEFORE the profile, with neither ever
# overwriting a value that is already set. Env beats local because env is set
# before we run; local beats the profile because local is parsed first.
#
# Override paths: AGENT_HOOKS_PROFILE, AGENT_HOOKS_LOCAL

AGENT_HOOKS_PROFILE="${AGENT_HOOKS_PROFILE:-${HOME}/.dotfiles/zsh/profiles/agent-hooks.sh}"
AGENT_HOOKS_LOCAL="${AGENT_HOOKS_LOCAL:-${HOME}/.config/agent-hooks/local.sh}"
AGENT_HOOKS_SRC=default

_ah_env_override=0
_ah_local_set=0
_ah_profile_set=0
_ah_local_keys=' '

# _ah_load FILE LAYER — parse `KEY=VAL` / `export KEY=VAL` lines, skipping any
# key that already holds a value. LAYER is `local` or `profile`.
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
    # Skip anything that isn't a plain shell name — it would break the eval.
    case "$_ah_key" in ''|*[!A-Za-z0-9_]*) continue ;; esac
    if eval "[ -z \"\${${_ah_key}+x}\" ]"; then
      # shellcheck disable=SC2086
      eval "export ${_ah_key}=\"${_ah_val}\""
      if [ "$2" = local ]; then
        _ah_local_set=1
        _ah_local_keys="${_ah_local_keys}${_ah_key} "
      else
        _ah_profile_set=1
      fi
    else
      # Already set. That's a real env override only if local didn't set it.
      case "$_ah_local_keys" in
        *" ${_ah_key} "*) ;;
        *) _ah_env_override=1 ;;
      esac
    fi
  done < "$1"
}

_ah_load "$AGENT_HOOKS_LOCAL" local
_ah_load "$AGENT_HOOKS_PROFILE" profile

if [ "$_ah_env_override" -eq 1 ]; then
  AGENT_HOOKS_SRC=env
elif [ "$_ah_local_set" -eq 1 ]; then
  AGENT_HOOKS_SRC=local
elif [ "$_ah_profile_set" -eq 1 ]; then
  AGENT_HOOKS_SRC=profile
fi

unset _ah_line _ah_key _ah_val
unset _ah_env_override _ah_local_set _ah_profile_set _ah_local_keys

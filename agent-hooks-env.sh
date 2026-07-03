#!/bin/sh
# Shared agent-hooks profile loader for hook scripts.
# Env vars already set when this file is sourced win over profile values.
#
# Profile: ~/.dotfiles/zsh/profiles/agent-hooks.sh
# Override path: AGENT_HOOKS_PROFILE=/path/to/file

AGENT_HOOKS_PROFILE="${AGENT_HOOKS_PROFILE:-${HOME}/.dotfiles/zsh/profiles/agent-hooks.sh}"
AGENT_HOOKS_SRC=default
_had_env_override=0

[ -f "$AGENT_HOOKS_PROFILE" ] || return 0 2>/dev/null || exit 0

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    ''|\#*) continue ;;
    export\ *) line="${line#export }" ;;
  esac
  key="${line%%=*}"
  val="${line#*=}"
  # shellcheck disable=SC2086
  eval "case \"\${${key}+x}\" in '') export ${key}=\"${val}\" ;; *) _had_env_override=1 ;; esac"
done < "$AGENT_HOOKS_PROFILE"

if [ "$_had_env_override" -eq 1 ]; then
  AGENT_HOOKS_SRC=env
else
  AGENT_HOOKS_SRC=profile
fi

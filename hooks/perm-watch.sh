#!/usr/bin/env bash
# perm-watch.sh — surface native macOS permission dialogs to the running agent.
#
# Fires from a global PostToolUse hook (matcher: Bash). After each Bash tool
# call — the moment a TCC/consent prompt would pop — it runs `ax-dialog read`.
# If a native dialog is sitting in the modal-panel layer band, it injects the
# dialog's text + button labels back into the running session (stderr + exit 2
# — the PostToolUse feedback path) so the agent handles it via the
# remote-permissions skill: ask Rio with getUserInput, then `ax-dialog click`.
#
# Rationale: Rio drives agents from his phone. When a command trips a macOS
# permission gate he can't reach the desktop to answer it. This hook makes the
# *responsible* agent — the one that just ran the command — aware, right when
# the dialog appears, with no daemon and no separate notification channel (the
# agent's own getUserInput tool reaches his phone).
#
# Settings follow the agent-hooks convention: profile vars live in
# ~/.dotfiles/zsh/profiles/agent-hooks.sh, loaded by agent-hooks-env.sh; any var
# already set in the environment overrides the profile.
#
#   AGENT_PERM_WATCH           on | off   (default on)
#   AGENT_PERM_WATCH_DEBOUNCE  seconds to suppress a repeat of the same dialog
#                              (default 60)
#   AGENT_PERM_WATCH_LOG       raw-band log path for filter validation
#                              (default ~/.claude/perm-watch-dialogs.log)
#
# Disable for one run:  AGENT_PERM_WATCH=off claude ...

set -uo pipefail

# --- load the shared agent-hooks profile (env wins over profile) ----------
[ -f "$HOME/scripts/agent-hooks-env.sh" ] && . "$HOME/scripts/agent-hooks-env.sh"

# --- opt-in gate (on by default) ------------------------------------------
[ "${AGENT_PERM_WATCH:-on}" = "on" ] || exit 0

# ax-dialog lives on PATH via ~/scripts; make sure the hook shell sees it.
case ":$PATH:" in *":$HOME/scripts:"*) ;; *) PATH="$HOME/scripts:$PATH" ;; esac
command -v ax-dialog >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

DEBOUNCE="${AGENT_PERM_WATCH_DEBOUNCE:-60}"

INPUT="$(cat)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')"
COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"

# --- skip when the agent is already handling a dialog ----------------------
# Its own ax-dialog/click-tool calls would otherwise re-detect the same dialog
# and re-alert in a loop.
case "$COMMAND" in
  *ax-dialog*|*click-tool*) exit 0 ;;
esac

# --- detect + read the dialog (cheap when the band is empty: ~55ms) --------
OUT="$(ax-dialog read 2>/dev/null)"; RC=$?
[ "$RC" -eq 0 ] || exit 0                      # 3 = no dialog up
[ -n "$OUT" ] || exit 0
COUNT="$(printf '%s' "$OUT" | jq -r '.dialogs | length' 2>/dev/null || echo 0)"
[ "$COUNT" -gt 0 ] 2>/dev/null || exit 0

OWNER="$(printf '%s' "$OUT"   | jq -r '.owner // "?"')"
TEXTS="$(printf '%s' "$OUT"   | jq -r '[.dialogs[].texts[]?] | join(" / ")')"
BUTTONS="$(printf '%s' "$OUT" | jq -r '[.dialogs[].buttons[]?.name] | join(", ")')"

# --- debounce: don't re-alert the same dialog within DEBOUNCE seconds -------
SIG="$(printf '%s' "$OWNER|$TEXTS" | cksum | cut -d" " -f1)"
STATE_DIR="${TMPDIR:-/tmp}/claude-perm-watch"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/${SESSION_ID}.last"
NOW="$(date +%s)"
if [ -f "$STATE_FILE" ]; then
  LAST_SIG="$(cut -d" " -f1 "$STATE_FILE" 2>/dev/null || echo)"
  LAST_TS="$(cut -d" " -f2 "$STATE_FILE" 2>/dev/null || echo 0)"
  if [ "$LAST_SIG" = "$SIG" ] && [ $(( NOW - LAST_TS )) -lt "$DEBOUNCE" ]; then
    exit 0
  fi
fi
printf '%s %s' "$SIG" "$NOW" > "$STATE_FILE"

# --- log the raw band (all zones, PRE-filter) for validation over real usage -
# Logs what `detect` sees WITHOUT --no-scrim, so if a genuine dialog ever tags
# "fullscreen" (and would be wrongly dropped) it shows here. Durable path,
# override with AGENT_PERM_WATCH_LOG. Never fails the hook.
LOG_FILE="${AGENT_PERM_WATCH_LOG:-$HOME/.claude/perm-watch-dialogs.log}"
ax-dialog detect --min 4 --max 23 2>/dev/null \
  | jq -c --arg ts "$(date '+%Y-%m-%dT%H:%M:%S')" \
      '{ts:$ts, band:[.[]|{owner,zone,layer,w,h,x,y}]}' >> "$LOG_FILE" 2>/dev/null || true

# --- inject into the running session (PostToolUse: stderr + exit 2) ---------
cat >&2 <<EOF
🔔 PERMISSION DIALOG DETECTED (perm-watch hook)
A native macOS dialog is on screen. Rio is likely driving you remotely and cannot
reach the desktop to answer it — surface it to him and press his choice.

  Owner:   $OWNER
  Text:    $TEXTS
  Buttons: $BUTTONS

ACTION — use the remote-permissions skill:
  1. Ask Rio which button via getUserInput. Quote the text and the EXACT button
     labels above. Do NOT approve anything consequential (grant access, delete,
     sign in, keychain) without his explicit choice — Cancel/deny is the safe
     default and needs no approval.
  2. Press his choice: ax-dialog click "<label>"  (dry-run first if the choice
     is close, e.g. Allow vs Allow Once).
  3. Password / SecurityAgent auth prompts run in a secure field AX can't fill —
     tell Rio those are VNC-only; you can still press Cancel.
EOF
exit 2

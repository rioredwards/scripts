#!/bin/bash
# todaybar-watchdog.sh — health check for the TodayBar agent loop in tmux
# Outputs a 2-3 line report for piping to text-phone-summary
set -euo pipefail

SESSION="todaybar"
LOOP_DIR="$HOME/dev/TodayBar/.agent-loop"

# 1. Session alive?
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "🔴 todaybar: tmux session \"$SESSION\" is GONE. Crashed or killed."
  exit 0
fi

# 2. Count agents in window 1 panes (1.1-1.4)
agent_count=0
declare -A pane_states
for pane in 1.1 1.2 1.3 1.4; do
  head=$(tmux capture-pane -t "${SESSION}:${pane}" -p 2>/dev/null | head -5)
  pane_states[$pane]="$head"
  if echo "$head" | grep -qiE 'claude|codex|opus|sonnet|gpt|gemini|antigravity|opencode'; then
    ((agent_count++))
  fi
done

# 3. Danger signals
dangers=""
for pane in 1.1 1.2 1.3 1.4; do
  tail20=$(tmux capture-pane -t "${SESSION}:${pane}" -p 2>/dev/null | tail -20)
  if echo "$tail20" | grep -qi "kneading"; then
    dangers="${dangers} kneading@${pane}"
  fi
  if echo "$tail20" | grep -qiE "error|failed|panic|crash|sigterm|sigkill"; then
    dangers="${dangers} error@${pane}"
  fi
  if echo "$tail20" | grep -qiE "rate.limit|429|401|403|api.error|token.limit|context.window"; then
    dangers="${dangers} api-issue@${pane}"
  fi
done

# 4. Check review loop
review_state="unknown"
if [[ -f "$LOOP_DIR/review-response.md" ]] && [[ -f "$LOOP_DIR/review-request.md" ]]; then
  resp_age=$(( $(date +%s) - $(stat -f %m "$LOOP_DIR/review-response.md" 2>/dev/null || echo 0) ))
  req_age=$(( $(date +%s) - $(stat -f %m "$LOOP_DIR/review-request.md" 2>/dev/null || echo 0) ))
  if [[ $resp_age -gt $req_age ]]; then
    review_state="approved"
  elif [[ $req_age -gt 900 ]]; then
    review_state="stuck (request >15min old, no response)"
  else
    review_state="waiting"
  fi
else
  review_state="no review files"
fi

# 5. Build report
if [[ -z "$dangers" ]]; then
  status="🟢"
else
  status="🟡"
fi

echo "${status} todaybar: ${agent_count} agents in win1. Review: ${review_state}.${dangers:+ Alerts:${dangers}}"

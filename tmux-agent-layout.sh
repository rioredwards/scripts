#!/usr/bin/env bash
# Restore sidebar + full-height middle + two stacked right layout.
# Expects: pane 1 = sidebar, panes 2/3/4 = content (stacked vertically).
tmux set-hook -gu after-resize-pane
tmux move-pane -h -s :.3 -t :.2
tmux move-pane -v -s :.4 -t :.3
tmux source ~/.tmux.conf

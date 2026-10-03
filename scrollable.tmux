#!/usr/bin/env bash
# tmux-scrollable: niri-style scrollable horizontal tiling for tmux.
# New horizontal splits grow the window to the right instead of squeezing, and the view
# scrolls so the active column is always fully visible.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$DIR/scripts/scrollable.sh"

# tmux <= 3.7 draws a window wider than the terminal with ghost borders and can spin
# the server at 100% CPU for minutes (tmux issue 5664); refuse rather than freeze
ver="$(tmux -V | sed 's/^[^0-9]*//; s/[^0-9.].*$//')"
if [ "$(printf '%s\n' 3.8 "$ver" | sort -V | head -1)" != 3.8 ]; then
  tmux display-message "tmux-scrollable needs tmux >= 3.8 (found $ver); not loaded"
  exit 0
fi

# Both keys work without the prefix, like niri's Mod+key; tmux's own bindings are untouched.
key="$(tmux show -gqv @scrollable-split-key)"
tmux bind-key -n "${key:-M-n}" run-shell "$S split"
key="$(tmux show -gqv @scrollable-preset-key)"
tmux bind-key -n "${key:-M-r}" run-shell "$S cycle"

# Hooks are arrays; a key keeps ours separate from any hook the user has set.
#   window-pane-changed   active pane changed (keys, mouse): just scroll to it (fast path)
#   session-window-changed window switched: a scrolled window must match this client
#   client-resized        terminal resized: columns are a percentage of its width
#   after-kill-pane / pane-exited  a column closed: shrink the window
tmux set-hook -g 'window-pane-changed[tmux-scrollable]' "run-shell '$S focus #{window_id}'"
for h in session-window-changed client-resized after-kill-pane; do
  tmux set-hook -g "$h[tmux-scrollable]" "run-shell '$S fit #{window_id}'"
done
tmux set-hook -gw 'pane-exited[tmux-scrollable]' "run-shell 'sleep 0.1; $S fit #{window_id}'"   # fires before the pane is removed

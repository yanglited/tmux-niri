#!/usr/bin/env bash
# tmux-scrollable: niri-style scrollable horizontal tiling for tmux.
# New horizontal splits grow the window to the right instead of squeezing, and the view
# scrolls so the active column is always fully visible.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$DIR/scripts/scrollable.sh"

# tmux <= 3.7 draws a window wider than the terminal with ghost borders and can spin
# the server at 100% CPU for minutes (tmux issue 5664); refuse rather than freeze
ver="$(tmux -V | sed 's/^[^0-9]*//; s/[^0-9.].*$//')"   # "3.8-rc3" -> 3.8, "next-3.9" -> 3.9
IFS=. read -r major minor _ <<< "$ver"
if (( ${major:-0} < 3 || (${major:-0} == 3 && ${minor:-0} < 8) )); then
  tmux display-message "tmux-scrollable needs tmux >= 3.8 (found $ver); not loaded"
  exit 0
fi

# Both keys work without the prefix, like niri's Mod+key; tmux's own bindings are untouched.
# The key last bound is remembered so re-sourcing after changing an option unbinds it.
bind() {  # bind <option> <default> <action>
  local key old
  key="$(tmux show -gqv "$1")"; key=${key:-$2}
  old="$(tmux show -gqv "@scrollable-bound-$3")"
  [[ -n $old && $old != "$key" ]] && tmux unbind-key -n "$old"
  tmux bind-key -n "$key" run-shell "$S $3" \; set -g "@scrollable-bound-$3" "$key"
}
bind @scrollable-split-key M-n split
bind @scrollable-preset-key M-r cycle

# Hooks are arrays; a key keeps ours separate from any hook the user has set.
#   window-pane-changed   active pane changed (keys, mouse): just scroll to it (fast path)
#   session-window-changed window switched: a scrolled window must match this client
#   client-resized        terminal resized: columns are a percentage of its width
#   after-kill-pane / pane-exited  a column closed: shrink the window
tmux set-hook -g 'window-pane-changed[tmux-scrollable]' "run-shell '$S focus #{window_id}'"
for h in session-window-changed client-resized after-kill-pane; do
  tmux set-hook -g "$h[tmux-scrollable]" "run-shell '$S fit #{window_id}'"
done
tmux set-hook -gw 'pane-exited[tmux-scrollable]' "run-shell 'sleep 0.02; $S fit #{window_id}'"   # fires just before the pane is removed

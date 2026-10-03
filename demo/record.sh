#!/usr/bin/env bash
# Record demo.gif: a scripted session on a throwaway tmux server (no personal data: fake
# home, neutral prompt, no hostname), captured headlessly with asciinema, rendered by agg.
# Usage: demo/record.sh [out.gif]   (needs tmux >= 3.8, asciinema 3, agg, bat, nvim)
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT=${1:-$HERE/../demo.gif}
W=$(mktemp -d); trap 'tmux -L demo kill-server 2>/dev/null; rm -rf "$W"' EXIT
mkdir -p "$W/home/project"
cat > "$W/home/project/server.py" <<'PY'
from dataclasses import dataclass


@dataclass
class Column:
    """One column on the strip: a fixed width in cells."""
    width: int
    panes: list[str]

    def fits(self, terminal: int) -> bool:
        return self.width <= terminal


def layout(columns: list[Column], terminal: int) -> int:
    total = sum(c.width for c in columns) + len(columns) - 1
    return max(total, terminal)
PY
cat > "$W/home/project/NOTES.md" <<'MD'
# Scrollable tiling

- new columns open to the **right** of the current one
- the strip scrolls; nothing gets squeezed
- `Alt+r` cycles 30% / 50% / 90%
MD
for f in main.c Makefile README.md config.toml .gitignore; do : > "$W/home/project/$f"; done
mkdir -p "$W/home/project/src" "$W/home/project/tests"

cat > "$W/shell.sh" <<SH
#!/usr/bin/env bash
export PS1='\[\e[1;34m\]\W\[\e[0m\] ❯ '
exec env -i HOME="$W/home" TERM=tmux-256color PATH="$PATH" PS1="\$PS1" bash --norc --noprofile
SH
chmod +x "$W/shell.sh"
cat > "$W/demo.conf" <<CONF
set -g default-terminal tmux-256color
set -g default-command "$W/shell.sh"
set -g status-style 'bg=colour236,fg=colour250'
set -g status-left ' #[bold]tmux-scrollable '
set -g status-left-length 30
set -g status-right '#[fg=colour245]Alt+n new column   Alt+r width   Ctrl+hjkl move '
set -g status-right-length 60
set -g window-status-format ''
set -g window-status-current-format ''
set -g message-style 'bg=colour39,fg=colour16,bold'
set -g display-time 2600
set -g pane-border-lines heavy
set -g pane-border-status top
set -g pane-border-format ' #{pane_index}: #{pane_current_command} '
set -g pane-border-style 'fg=colour240'
set -g pane-active-border-style 'fg=colour39,bold'
set -g @scrollable-width 50
run '$HERE/../scrollable.tmux'
CONF

T="tmux -L demo"
$T -f "$W/demo.conf" new-session -d -s demo -x 120 -y 32 -c "$W/home/project"
asciinema rec --headless --overwrite --window-size 120x32 -c "env TERM=xterm-256color $T attach -t demo" "$W/demo.cast" &
REC=$!
sleep 1.5
say() { $T display-message "$1"; }
type_() { $T send-keys -t demo "$1" Enter; }
plugin() { $T run-shell "$HERE/../scripts/scrollable.sh $1"; }

type_ 'bat --style=numbers --paging=never server.py'; sleep 1.5
say ' Ordinary tmux: one pane filling the terminal.'; sleep 3
say ' Alt+r cycles the column width: 30% ...'; sleep 0.8; plugin cycle; sleep 2.2
say ' ... 50%.  Widths are fixed cells; resizing the terminal does not change them.'; sleep 0.4; plugin cycle; sleep 3.2
say ' Alt+n opens a new column to the right and scrolls to it.'; sleep 1
plugin split; sleep 0.8; type_ 'ls --color -1'; sleep 2.8
say ' Alt+n again: the strip scrolls, the first column slides off to the left. Nothing is squeezed.'; sleep 1
plugin split; sleep 0.8; type_ "nvim -u NONE -c 'syntax on' -c 'set number' NOTES.md"; sleep 3.4
say ' Ctrl+h moves left; the strip scrolls so the whole column is visible.'; sleep 1
$T select-pane -t demo -L; sleep 1.6; $T select-pane -t demo -L; sleep 2.2
say ' Ctrl+l moves right again.'; sleep 0.8
$T select-pane -t demo -R; sleep 1.4; $T select-pane -t demo -R; sleep 2
say ' prefix "  still stacks panes inside a column, like windows in a niri column.'; sleep 1
$T split-window -v -t demo -c "$W/home/project"; sleep 0.8; type_ 'echo stacked'; sleep 2.6
say ' Alt+r on this column: 90% ...'; sleep 0.8; plugin cycle; sleep 2.4
say ' ... and back to 30%.'; sleep 0.4; plugin cycle; sleep 2.6
say ' Closing a column shrinks the strip back.'; sleep 1
$T select-pane -t demo -U; sleep 0.5; $T send-keys -t demo ':q' Enter; sleep 0.6; type_ exit; sleep 2.6
say ' github.com/yanglited/tmux-scrollable'; sleep 3
$T kill-server; wait $REC || true
agg --font-family "JetBrainsMono Nerd Font Mono" --font-size 15 --theme monokai "$W/demo.cast" "$OUT"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"

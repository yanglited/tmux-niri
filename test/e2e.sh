#!/usr/bin/env bash
# End-to-end check on a throwaway tmux server with a fake 100x20 terminal attached.
# Run: test/e2e.sh   (exits non-zero on the first mismatch)
cd "$(dirname "$0")" || exit 1
S=tmux-scrollable-test; T="tmux -L $S"
$T kill-server 2>/dev/null
tmux -L $S -f /dev/null new-session -d -s t -x 100 -y 20
python3 pty_attach.py $S & PID=$!
trap 'kill $PID 2>/dev/null; $T kill-server 2>/dev/null' EXIT
sleep 0.7
$T run-shell "$PWD/../scrollable.tmux"
split() { $T run-shell "$PWD/../scripts/scrollable.sh split"; sleep 0.4; }
# expect <label> <off_x> <win_w> <lefts...>
expect() {
  local label=$1 want="$2 $3 ${*:4}"
  local got; got="$($T list-clients -F '#{window_offset_x} #{window_width}') $($T list-panes -t t -F '#{pane_left}' | sort -n | tr '\n' ' ')"
  got=${got% }
  if [[ $got == "$want" ]]; then echo "ok   $label"; else echo "FAIL $label: want [$want] got [$got]"; exit 1; fi
}
split;                                  expect 'first split grows window right'    50  150 0 101
split;                                  expect 'second split appends column'       100 200 0 101 151
$T resize-pane -Z -t t:.2; sleep 0.4
got="$($T list-clients -F '#{window_offset_x} #{window_width} #{window_zoomed_flag}') $($T display -p -t t:.2 '#{pane_left} #{pane_width}')"
[[ $got == " 100 1 0 100" ]] && echo 'ok   zoom fills the terminal, not the strip' || { echo "FAIL zoom: got [$got]"; exit 1; }
$T resize-pane -Z -t t:.2; sleep 0.6;   expect 'unzoom restores the strip'          100 200 0 101 151
$T choose-tree -Zs; sleep 0.5             # prefix s / prefix w zoom without resize-pane
got="$($T list-clients -F '#{window_offset_x} #{window_width} #{window_zoomed_flag}') $($T display -p '#{pane_width} #{pane_mode}')"
[[ $got == " 100 1 100 tree-mode" ]] && echo 'ok   choose-tree -Z fills the terminal' || { echo "FAIL choose-tree -Z: got [$got]"; exit 1; }
$T send-keys -t t q; sleep 0.6;         expect 'leaving choose-tree restores the strip' 100 200 0 101 151
$T select-pane -t t:.0; sleep 0.3;      expect 'focus left column scrolls to 0'    0   200 0 101 151
$T select-pane -t t:.1; sleep 0.3;      expect 'focus middle column fully visible' 50  200 0 101 151
$T send-keys -t t:.1 'tput civis; sleep 1' Enter; sleep 0.5; expect 'hidden cursor does not move view' 50 200 0 101 151
sleep 0.8
cycle() { $T run-shell "$PWD/../scripts/scrollable.sh cycle"; sleep 0.4; }
cycle;                                  expect 'preset 50 -> 66 widens column'      67  217 0 101 168
cycle;                                  expect 'preset 66 -> 100 widens more'       101 251 0 101 202
$T resize-pane -Z -t t:.1; sleep 0.4    # zoomed: Alt+r must unzoom first, and must not deadlock on its own hook
timeout 5 $T run-shell "$PWD/../scripts/scrollable.sh cycle" || { echo 'FAIL cycle while zoomed deadlocks'; exit 1; }
sleep 0.4;                              expect 'preset 100 -> 66 from zoomed'       67  217 0 101 168
$T split-window -v -t t:.1; sleep 0.3;  expect 'vertical split stacks in column'   67  217 0 101 101 168
$T split-window -h -t t:.2; sleep 0.4;  expect 'stock split inside a column row'    67  217 0 101 101 135 168
$T select-pane -t t:.1; sleep 0.4;      expect 'focus up keeps nested row intact'   67  217 0 101 101 135 168
$T kill-pane -t t:.3; sleep 0.6;        expect 'close nested pane keeps columns'    67  217 0 101 101 168
split;                                  expect 'split inserts after current column' 117 267 0 101 101 168 218
$T kill-pane -t t:.4; sleep 0.6;        expect 'kill the new (active) column'      101 217 0 101 101 168
$T send-keys -t t:.3 exit Enter; sleep 0.8; expect 'shell exit shrinks window'     67  167 0 101 101
$T send-keys -t t:.2 exit Enter; sleep 0.8; expect 'stacked exit keeps columns'    67  167 0 101
$T select-pane -t t:.0; sleep 0.3; cycle; expect 'first column 100% -> 66%'           0   133 0 67
cycle; cycle;                           expect 'then 50% and 33%: narrower than terminal' '' 99 0 33
$T kill-pane -t t:.1; sleep 0.6;        expect 'single column returns to normal'   ''  100 0
echo all ok

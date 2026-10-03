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
$T select-pane -t t:.0; sleep 0.3;      expect 'focus left column scrolls to 0'    0   200 0 101 151
$T select-pane -t t:.1; sleep 0.3;      expect 'focus middle column fully visible' 50  200 0 101 151
$T send-keys -t t:.1 'tput civis; sleep 1' Enter; sleep 0.5; expect 'hidden cursor does not move view' 50 200 0 101 151
sleep 0.8
cycle() { $T run-shell "$PWD/../scripts/scrollable.sh cycle"; sleep 0.4; }
cycle;                                  expect 'preset 50 -> 90 widens column'      90  240 0 101 191
cycle;                                  expect 'preset 90 -> 30 narrows column'     80  180 0 101 131
cycle;                                  expect 'preset 30 -> 50 back'               80  200 0 101 151
$T split-window -v -t t:.1; sleep 0.3;  expect 'vertical split stacks in column'   80  200 0 101 101 151
$T split-window -h -t t:.2; sleep 0.4;  expect 'stock split inside a column row'    80  200 0 101 101 126 151
$T select-pane -t t:.1; sleep 0.4;      expect 'focus up keeps nested row intact'   80  200 0 101 101 126 151
$T kill-pane -t t:.3; sleep 0.6;        expect 'close nested pane keeps columns'    80  200 0 101 101 151
split;                                  expect 'split inserts after current column' 100 250 0 101 101 151 201
$T kill-pane -t t:.4; sleep 0.6;        expect 'kill-pane shrinks window'          100 200 0 101 101 151
$T send-keys -t t:.3 exit Enter; sleep 0.8; expect 'shell exit shrinks window'     50  150 0 101 101
$T send-keys -t t:.2 exit Enter; sleep 0.8; expect 'stacked exit keeps columns'    50  150 0 101
$T select-pane -t t:.0; sleep 0.3; cycle; expect 'first column 30%: window narrower than terminal' '' 79 0 30
cycle; cycle;                           expect 'then 50% and 90%: window grows again' 0 139 0 90
$T kill-pane -t t:.1; sleep 0.6;        expect 'single column returns to normal'   ''  100 0
echo all ok

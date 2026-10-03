#!/usr/bin/env bash
# Columns are the children of the window's top-level left-to-right layout node. Each
# column's width is a fixed number of cells, remembered in the @scrollable_w option of its
# panes: chosen relative to the terminal when set (Alt+n, Alt+r), then kept when the
# terminal is resized, like niri's "fixed" widths. scripts/layout.py does the tree maths
# on tmux's JSON layout.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Hooks fire several copies of this script at once (closing a pane fires three), so
# serialise: interleaved resize commands from two runs corrupt tmux's layout tree.
exec 9>"${TMUX_TMPDIR:-/tmp}/tmux-scrollable-$(id -u).lock"; flock 9

log() { [[ -n ${SCROLLABLE_LOG:-} ]] && printf '%s %s\n' "$(date +%T.%N)" "$*" >> "$SCROLLABLE_LOG"; return 0; }
SCROLLABLE_LOG=$(tmux show -gqv @scrollable-log)

widths() { tmux list-panes -t "$1" -F '#{pane_id} #{@scrollable_w}'; }
layout() { tmux display -p -t "$1" '#{window_layout}'; }

# Resize the window to its columns' total and give every column its width.
# $2 (optional) reorders the columns: comma-separated column indexes.
fit() {
  local win=$1 order=${2:-} cw ch st rows cols total new cur
  # only windows where the plugin has been used; leave stock tmux windows alone
  (( $(widths "$win" | awk 'NF>1' | wc -l) > 0 )) || return 0
  read -r cw ch st cur < <(tmux display -p -t "$win" '#{client_width} #{client_height} #{status} #{window_width}x#{window_height}')
  case $st in on) rows=1 ;; off) rows=0 ;; *) rows=$st ;; esac
  cols=$("$DIR/layout.py" columns "$(layout "$win")" < <(widths "$win"))
  log "fit $win client=${cw}x$ch window=$cur cols=[$(tr '\n' ';' <<< "$cols")]"
  # every pane of a column carries the column's width (new panes inherit it) and the
  # column's index, so focus() can find the column without re-parsing the layout
  local i=0
  while read -r w ids; do
    for id in ${ids//,/ }; do tmux set -p -t "$id" @scrollable_w "$w" \; set -p -t "$id" @scrollable_col "$i"; done
    i=$((i+1))
  done <<< "$cols"
  if (( $(wc -l <<< "$cols") <= 1 )); then
    tmux set -w -t "$win" window-size latest   # a single column always fills the terminal
    return
  fi
  { read -r total; read -r new; } < <("$DIR/layout.py" apply "$(layout "$win")" "$order" < <(widths "$win"))
  # The window is exactly as wide as its columns, whether that is wider or narrower than
  # the terminal: like niri, the space after the last column stays empty instead of the
  # last column stretching, and a resized terminal does not resize the columns.
  # Resize only when something changed: every resize is a SIGWINCH to every pane program,
  # and client-resized can fire dozens of times per second.
  if [[ $cur != "${total}x$(( ch - rows ))" ]]; then
    tmux set -w -t "$win" window-size manual
    tmux set -w -t "$win" fill-character ' '   # blank, not tmux's dots, after the last column
    tmux resize-window -t "$win" -x "$total" -y "$(( ch - rows ))"
    # heights were rescaled by tmux: recompute the layout from the resized tree
    { read -r total; read -r new; } < <("$DIR/layout.py" apply "$(layout "$win")" "$order" < <(widths "$win"))
  fi
  [[ $new == "$(layout "$win")" ]] || tmux select-layout -t "$win" "$new"   # one atomic resize
  log "fit done window=$(tmux display -p -t "$win" '#{window_width}') panes=[$(tmux list-panes -t "$win" -F '#{pane_left}/#{pane_width}' | tr '\n' ' ')]"
  focus "$win"
}

# Scroll every client showing this window so the active column is fully visible, moving
# as little as possible (niri's center-focused-column "never"). This replaces tmux's own
# cursor tracking, which centres the cursor instead of the pane and jumps to the far left
# when the program hides its cursor.
focus() {
  local win=$1 pl pw name cw ox wid want
  # span of the active pane's column from the cached @scrollable_col (fast path: no python);
  # fall back to the layout tree if a pane has no index yet
  read -r pl pw < <(tmux list-panes -t "$win" -F '#{pane_left} #{pane_width} #{pane_active} #{@scrollable_col}' \
    | awk '$3==1 { col=$4 } { l[NR]=$1; w[NR]=$2; c[NR]=$4 }
           END { if (col=="") exit 1; for (i=1;i<=NR;i++) if (c[i]==col) { if (!n++ || l[i]<L) L=l[i]; if (l[i]+w[i]>R) R=l[i]+w[i] } print L, R-L }') \
    || read -r _ _ _ pl pw < <(active_col "$win")
  tmux list-clients -F '#{client_name} #{client_width} #{window_offset_x} #{window_id}' \
    | while read -r name cw ox wid; do
    [[ $wid == "$win" && -n $ox ]] || continue   # empty offset: window fits, nothing to scroll
    want=$ox
    (( pl + pw > want + cw )) && want=$(( pl + pw - cw ))
    (( pl < want )) && want=$pl
    # always re-issue, even when nothing moves: refresh-client -L/-R switches the client
    # from cursor tracking to explicit panning (adjustment must be >= 1, so go to 0 first)
    if (( want > 0 )); then
      tmux refresh-client -t "$name" -L 100000 \; refresh-client -t "$name" -R "$want"
    else
      tmux refresh-client -t "$name" -L 100000
    fi
  done
  return 0
}

# "idx width ids left span" of the column holding the active pane
active_col() {
  local win=$1 active i=0 w ids
  active=$(tmux display -p -t "$win" '#{pane_id}')
  while read -r w ids; do
    if [[ ",$ids," == *",$active,"* ]]; then
      tmux list-panes -t "$win" -F '#{pane_id} #{pane_left} #{pane_width}' \
        | awk -v ids=",$ids," -v i="$i" -v w="$w" -v ids_out="$ids" \
          '{ if (index(ids, ","$1",")) { if (!n++ || $2<l) l=$2; if ($2+$3>r) r=$2+$3 } } END { print i, w, ids_out, l, r-l }'
      return
    fi
    i=$((i+1))
  done < <("$DIR/layout.py" columns "$(layout "$win")" < <(widths "$win"))
}

# width in cells for a percentage of the terminal; the +1/-1 account for the one-cell
# border, so columns adding up to 100% fill the terminal exactly
cells() { local w=$(( ($2 + 1) * $1 / 100 - 1 )); echo $(( w < 1 ? 1 : w )); }

# Cycle the active column through the preset widths (niri's switch-preset-column-width)
cycle() {
  local win cw idx cur ids presets next p id
  read -r win cw < <(tmux display -p '#{window_id} #{client_width}')
  fit_mark "$win"
  read -r idx cur ids _ _ < <(active_col "$win")
  presets=$(tmux show -gqv @scrollable-presets); presets=${presets:-30 50 90}
  next=""   # first preset wider than the column now, relative to the current terminal
  for p in $presets; do (( $(cells "$p" "$cw") > cur )) && { next=$p; break; }; done
  [[ -n $next ]] || next=${presets%% *}
  for id in ${ids//,/ }; do tmux set -p -t "$id" @scrollable_w "$(cells "$next" "$cw")"; done
  fit "$win"
}

# Open a new column right of the current one, like niri
split() {
  local win cw pct path pane idx n order i
  read -r win cw pct path < <(tmux display -p '#{window_id} #{client_width} #{?#{@scrollable-width},#{@scrollable-width},50} #{pane_current_path}')
  fit_mark "$win"   # a stock window keeps its current column widths
  read -r idx _ < <(active_col "$win")
  n=$("$DIR/layout.py" columns "$(layout "$win")" < <(widths "$win") | wc -l)
  # -f: a full-height column at the window's right edge; fit then moves it after the current column
  pane=$(tmux split-window -h -f -l 1 -c "$path" -P -F '#{pane_id}')
  tmux set -p -t "$pane" @scrollable_w "$(cells "$pct" "$cw")"
  order=""; for ((i = 0; i < n; i++)); do order+="$i,"; (( i == idx )) && order+="$n,"; done
  fit "$win" "${order%,}"
}

# remember the current column widths of a window the plugin has not managed yet
fit_mark() {
  local win=$1 w ids id
  (( $(widths "$win" | awk 'NF>1' | wc -l) > 0 )) && return 0
  while read -r w ids; do
    for id in ${ids//,/ }; do tmux set -p -t "$id" @scrollable_w "$w"; done
  done < <("$DIR/layout.py" columns "$(layout "$win")" < <(widths "$win"))
}

"$@"

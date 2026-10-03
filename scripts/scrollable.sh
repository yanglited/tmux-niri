#!/usr/bin/env bash
# Columns are the children of the window's top-level left-to-right layout node. Each
# column's width is a fixed number of cells, remembered in the @scrollable_w option of its
# panes: chosen relative to the terminal when set (Alt+n, Alt+r), then kept when the
# terminal is resized, like niri's "fixed" widths. scripts/layout.py does the tree maths
# on tmux's JSON layout; everything here is kept to a handful of tmux round trips.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Hooks fire several copies of this script at once (closing a pane fires three), so
# serialise: interleaved resize commands from two runs corrupt tmux's layout tree.
# flock is util-linux; without it (macOS) runs are not serialised.
if command -v flock >/dev/null; then
  exec 9>"${TMUX_TMPDIR:-/tmp}/tmux-scrollable-$(id -u).lock"; flock 9
fi

log() { [[ -n ${SCROLLABLE_LOG:-} ]] && printf '%s %s\n' "${EPOCHREALTIME:-$(date +%s)}" "$*" >> "$SCROLLABLE_LOG"; return 0; }
SCROLLABLE_LOG=$(tmux show -gqv @scrollable-log)

widths() { tmux list-panes -t "$1" -F '#{pane_id} #{@scrollable_w}'; }
layout() { tmux display -p -t "$1" '#{window_layout}'; }
managed() { (( $(widths "$1" | awk 'NF>1' | wc -l) > 0 )); }
columns() { "$DIR/layout.py" columns "$(layout "$1")" < <(widths "$1"); }

# width in cells for a percentage of the terminal; the +1/-1 account for the one-cell
# border, so columns adding up to 100% fill the terminal exactly
cells() { local w=$(( ($2 + 1) * $1 / 100 - 1 )); echo $(( w < 1 ? 1 : w )); }

# Resize the window to its columns' total and give every column its width, in one
# select-layout. $2 reorders the columns (comma-separated indexes), $3 = "force" manages a
# window the plugin has not touched yet (keeping its current column widths).
fit() {
  local win=$1 order=${2:-} force=${3:-} cw ch st rows cur total new cols
  # leave stock tmux windows alone unless asked
  [[ $force == force ]] || managed "$win" || return 0
  read -r cw ch st cur < <(tmux display -p -t "$win" '#{client_width} #{client_height} #{status} #{window_width}x#{window_height}')
  case $st in on) rows=1 ;; off) rows=0 ;; *) rows=$st ;; esac
  { read -r total; read -r new; cols=$(cat); } < <("$DIR/layout.py" apply "$(layout "$win")" "$(( ch - rows ))" "$order" < <(widths "$win"))
  log "fit $win client=${cw}x$ch window=$cur cols=[$(tr '\n' ';' <<< "$cols")]"
  # every pane carries its column's width (new panes inherit it) and the column's index,
  # so focus() can find the column without re-parsing the layout; one tmux call for all
  local i=0 w ids id args=()
  while read -r w ids; do
    for id in ${ids//,/ }; do args+=(set -p -t "$id" @scrollable_w "$w" \; set -p -t "$id" @scrollable_col "$i" \;); done
    i=$((i+1))
  done <<< "$cols"
  tmux "${args[@]:0:${#args[@]}-1}"
  if (( i <= 1 )); then
    tmux set -w -t "$win" window-size latest   # a single column always fills the terminal
    return
  fi
  # The window is exactly as wide as its columns, whether that is wider or narrower than
  # the terminal: like niri, the space after the last column stays empty instead of the
  # last column stretching, and a resized terminal does not resize the columns.
  # Resize only when something changed: every resize is a SIGWINCH to every pane program,
  # and client-resized can fire dozens of times per second.
  if [[ $cur != "${total}x$(( ch - rows ))" ]]; then
    tmux set -w -t "$win" window-size manual \; set -w -t "$win" fill-character ' ' \; \
      resize-window -t "$win" -x "$total" -y "$(( ch - rows ))"
  fi
  [[ $new == "$(layout "$win")" ]] || tmux select-layout -t "$win" "$new"   # one atomic resize
  log "fit done window=$(tmux display -p -t "$win" '#{window_width}')"
  focus "$win"
}

# Scroll every client showing this window so the active column is fully visible, moving
# as little as possible (niri's center-focused-column "never"). This replaces tmux's own
# cursor tracking, which centres the cursor instead of the pane and jumps to the far left
# when the program hides its cursor.
focus() {
  local win=$1 pl pw name cw ox wid want
  # span of the active pane's column from the cached @scrollable_col (no python)
  read -r pl pw < <(tmux list-panes -t "$win" -F '#{pane_left} #{pane_width} #{pane_active} #{@scrollable_col}' \
    | awk '$3==1 { col=$4 } { l[NR]=$1; w[NR]=$2; c[NR]=$4 }
           END { if (col=="") exit 1; for (i=1;i<=NR;i++) if (c[i]==col) { if (!n++ || l[i]<L) L=l[i]; if (l[i]+w[i]>R) R=l[i]+w[i] } print L, R-L }') \
    || read -r pl pw < <(active_span "$win")
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

# "idx width ids count" of the column holding the active pane; also records the current
# column widths on a window the plugin has not managed yet, so they survive the change
active_col() {
  local win=$1 active i=0 w ids found="" args=()
  active=$(tmux display -p -t "$win" '#{pane_id}')
  managed "$win"; local unmanaged=$?
  while read -r w ids; do
    [[ -z $found && ",$ids," == *",$active,"* ]] && found="$i $w $ids"
    (( unmanaged )) && for id in ${ids//,/ }; do args+=(set -p -t "$id" @scrollable_w "$w" \;); done
    i=$((i+1))
  done < <(columns "$win")
  (( ${#args[@]} )) && tmux "${args[@]:0:${#args[@]}-1}"
  [[ -n $found ]] && echo "$found $i"
}

# "left span" of the column holding the active pane, from the layout tree
active_span() {
  local ids; read -r _ _ ids _ < <(active_col "$1")
  tmux list-panes -t "$1" -F '#{pane_id} #{pane_left} #{pane_width}' \
    | awk -v ids=",$ids," '{ if (index(ids, ","$1",")) { if (!c++ || $2<l) l=$2; if ($2+$3>r) r=$2+$3 } } END { print l, r-l }'
}

# Cycle the active column through the preset widths (niri's switch-preset-column-width)
cycle() {
  local win cw idx cur ids presets next p id args=()
  read -r win cw < <(tmux display -p '#{window_id} #{client_width}')
  read -r idx cur ids _ < <(active_col "$win")
  presets=$(tmux show -gqv @scrollable-presets); presets=${presets:-30 50 90}
  next=""   # first preset wider than the column now, relative to the current terminal
  for p in $presets; do (( $(cells "$p" "$cw") > cur )) && { next=$p; break; }; done
  [[ -n $next ]] || next=${presets%% *}
  for id in ${ids//,/ }; do args+=(set -p -t "$id" @scrollable_w "$(cells "$next" "$cw")" \;); done
  tmux "${args[@]:0:${#args[@]}-1}"
  fit "$win" "" force
}

# Open a new column right of the current one, like niri
split() {
  local win cw pct path pane idx n order i
  read -r win cw pct path < <(tmux display -p '#{window_id} #{client_width} #{?#{@scrollable-width},#{@scrollable-width},50} #{pane_current_path}')
  read -r idx _ _ n < <(active_col "$win")
  # -f: a full-height column at the window's right edge; fit then moves it after the current column
  pane=$(tmux split-window -h -f -l 1 -c "$path" -P -F '#{pane_id}')
  tmux set -p -t "$pane" @scrollable_w "$(cells "$pct" "$cw")"
  order=""; for ((i = 0; i < n; i++)); do order+="$i,"; (( i == idx )) && order+="$n,"; done
  fit "$win" "${order%,}" force
}

"$@"

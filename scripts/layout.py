#!/usr/bin/env python3
"""Column maths on tmux's JSON window layout (tmux >= 3.8).

A column is a child of the window's top-level left-to-right node (the whole window if the
root is a single pane or a top-to-bottom stack). Pane percentages arrive on stdin as
"pane_id pct" lines; a column's percentage is the first one set on any of its panes.

  layout.py columns LAYOUT CW            -> "pct id,id,..." per column, left to right
  layout.py apply   LAYOUT CW [ORDER]    -> "total\\nNEWLAYOUT" with each column sized
                                            to its percentage (ORDER: comma-separated
                                            column indexes to reorder them first)
"""
import json
import sys


def panes(node):
    if node["t"] == "p":
        return [node["I"]]
    return [p for c in node["c"] for p in panes(c)]


def columns(root):
    return root["c"] if root["t"] == "h" else [root]


def column_widths(cols, stored):
    out = []
    for col in cols:
        w = next((stored[i] for i in panes(col) if stored.get(i)), None)
        out.append(max(1, int(w)) if w else col["w"])
    return out


def scale(node, x, w):
    """Resize a subtree to width w at x, keeping child proportions and 1-cell borders."""
    node["x"], node["w"] = x, w
    if node["t"] == "v":
        for c in node["c"]:
            scale(c, x, w)
    elif node["t"] == "h":
        kids = node["c"]
        old = sum(c["w"] for c in kids)
        avail = w - (len(kids) - 1)
        cx, used = x, 0
        for i, c in enumerate(kids):
            cw_ = avail - used if i == len(kids) - 1 else max(1, c["w"] * avail // old)
            scale(c, cx, cw_)
            cx += cw_ + 1
            used += cw_


def main():
    cmd, layout = sys.argv[1], json.loads(sys.argv[2])
    stored = {}
    for line in sys.stdin:
        parts = line.split()
        if parts:
            stored[parts[0]] = parts[1] if len(parts) > 1 else ""
    root = layout["L"]
    cols = columns(root)
    widths = column_widths(cols, stored)
    if cmd == "columns":
        for col, w in zip(cols, widths):
            print(w, ",".join(panes(col)))
        return
    if len(sys.argv) > 3 and sys.argv[3]:
        order = [int(i) for i in sys.argv[3].split(",")]
        cols = [cols[i] for i in order]
        widths = [widths[i] for i in order]
    total = sum(widths) + len(widths) - 1
    x = 0
    for col, w in zip(cols, widths):
        scale(col, x, w)
        x += w + 1
    if root["t"] == "h":
        root["c"] = cols
        root["x"], root["w"] = 0, total
    print(total)
    print(json.dumps(layout, separators=(",", ":")))


main()

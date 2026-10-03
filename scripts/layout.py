#!/usr/bin/env python3
"""Column maths on tmux's JSON window layout (tmux >= 3.8).

A column is a child of the window's top-level left-to-right node (the whole window if the
root is a single pane or a top-to-bottom stack). Column widths are fixed cell counts
(like niri's "fixed" widths: chosen relative to the terminal when set, then kept when the
terminal is resized). They arrive on stdin as "pane_id width" lines; a column's width is
the first one set on any of its panes, else its current width.

  layout.py columns LAYOUT
      -> one line per column, left to right: "width id,id,..."
  layout.py apply LAYOUT HEIGHT [ORDER]
      -> "total", then the new layout JSON with every column at its width and the whole
         tree scaled to HEIGHT rows, then the column lines as above (in the new order).
         ORDER: comma-separated column indexes to reorder the columns first.
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


def split_sizes(kids, key, avail):
    """Share avail cells among kids in proportion to their current size (1-cell borders)."""
    old = sum(c[key] for c in kids)
    sizes = [max(1, c[key] * (avail - len(kids) + 1) // old) for c in kids[:-1]]
    sizes.append(max(1, avail - len(kids) + 1 - sum(sizes)))
    return sizes


def scale(node, x, y, w, h):
    """Resize a subtree to w x h at (x, y), keeping child proportions."""
    node["x"], node["y"], node["w"], node["h"] = x, y, w, h
    if node["t"] == "h":
        cx = x
        for c, cw in zip(node["c"], split_sizes(node["c"], "w", w)):
            scale(c, cx, y, cw, h)
            cx += cw + 1
    elif node["t"] == "v":
        cy = y
        for c, ch in zip(node["c"], split_sizes(node["c"], "h", h)):
            scale(c, x, cy, w, ch)
            cy += ch + 1


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
    height = int(sys.argv[3])
    if len(sys.argv) > 4 and sys.argv[4]:
        order = [int(i) for i in sys.argv[4].split(",")]
        cols = [cols[i] for i in order]
        widths = [widths[i] for i in order]
    total = sum(widths) + len(widths) - 1
    x = 0
    for col, w in zip(cols, widths):
        scale(col, x, 0, w, height)
        x += w + 1
    if root["t"] == "h":
        root["c"] = cols
        root["x"], root["y"], root["w"], root["h"] = 0, 0, total, height
    print(total)
    print(json.dumps(layout, separators=(",", ":")))
    for col, w in zip(cols, widths):
        print(w, ",".join(panes(col)))


main()

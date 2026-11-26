#!/usr/bin/env python3
"""Inline SVG drawings of contract diagrams, and the Diagrams section of the contract page.

The SVG carries classes only. The page CSS colors them with its theme variables.
"""
import collections
import html
import re
from urllib.parse import quote

from contract_diagrams import display_width, sequence_participants, subject_slug, subjects

COLUMN_PX = 7.5  # estimated width of one display column of 13px text
PAD = 12
BOX_H = 30
SLOT = 44  # flow: vertical distance between two edge ends on one side of a part
STEP = 36  # sequence: vertical distance between two steps
STATE_H = 32
STATE_ROW = 76
LAYER_HEAD = 56
NUMBER = re.compile(r"-?\d+(?:\.\d+)?")


def esc(text):
    return html.escape(str(text))


def text_width(text):
    return display_width(str(text)) * COLUMN_PX


def num(value):
    return "%g" % round(value, 2)


def line(*points):
    return "M" + " L".join("%s %s" % (num(x), num(y)) for x, y in points)


def curve(start, control_1, control_2, end):
    return "M%s %s C%s %s %s %s %s %s" % tuple(num(v) for v in start + control_1 + control_2 + end)


class Canvas:
    """Collects SVG elements and grows the view box to hold them. Edge labels paint last."""

    def __init__(self, prefix, title):
        self.marker, self.title = "%s-arrow" % prefix, title
        self.shapes, self.labels, self.right, self.bottom = [], [], 0.0, 0.0

    def grow(self, x, y):
        self.right, self.bottom = max(self.right, x), max(self.bottom, y)

    def rect(self, x, y, width, height, cls, rx=6, node=None):
        self.grow(x + width, y + height)
        data = ' data-id="%s"' % esc(node) if node is not None else ""
        self.shapes.append('<rect class="%s"%s x="%s" y="%s" width="%s" height="%s" rx="%s"/>' % (
            cls, data, num(x), num(y), num(width), num(height), rx))

    def text(self, x, y, value, cls="", anchor="middle"):
        width = text_width(value)
        if anchor == "middle":
            x = max(x, PAD + width / 2)
            self.grow(x + width / 2, y + 4)
        else:
            self.grow(x + width, y + 4)
        element = '<text%s x="%s" y="%s" text-anchor="%s">%s</text>' % (
            ' class="%s"' % cls if cls else "", num(x), num(y), anchor, esc(value))
        (self.labels if cls == "lbl" else self.shapes).append(element)

    def path(self, d, cls="edge", source=None, target=None, arrow=True):
        numbers = [float(v) for v in NUMBER.findall(d)]
        self.grow(max(numbers[0::2]), max(numbers[1::2]))
        data = ' data-from="%s" data-to="%s"' % (esc(source), esc(target)) if source is not None else ""
        end = ' marker-end="url(#%s)"' % esc(self.marker) if arrow else ""
        self.shapes.append('<path class="%s"%s d="%s"%s/>' % (cls, data, d, end))

    def svg(self):
        width, height = num(self.right + PAD), num(self.bottom + PAD)
        marker = ('<defs><marker id="%s" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="9" markerHeight="9" '
                  'markerUnits="userSpaceOnUse" orient="auto"><path class="head" d="M0 0 L10 5 L0 10 z"/>'
                  '</marker></defs>' % esc(self.marker))
        return ('<svg xmlns="http://www.w3.org/2000/svg" role="img" viewBox="0 0 %s %s" width="%s" height="%s">'
                '<title>%s</title>%s%s</svg>') % (
            width, height, width, height, esc(self.title), marker, "".join(self.shapes + self.labels))


def caption(kind, value):
    if kind == "flow":
        return "Component flow"
    if kind in ("sequence", "states"):
        return "%s: %s" % (kind.capitalize(), value.get("title") or value.get("id", ""))
    style = value.get("style")
    return "Architecture (%s)" % style if style else "Architecture"


def lane_width(edge):
    return text_width(edge["label"]) + 24 if edge.get("label") else 16


def other_end(end, edge):
    return edge["to"] if end == "from" else edge["from"]


def outer_column(canvas, nodes, sides, labels, slot, box_x, box_w, part_x, label_x):
    """Draw caller or dependency boxes beside the parts they touch, with a horizontal arrow for each edge.

    One box spans each run of consecutive edge ends of one node.
    A node whose ends are not consecutive gets one box for each run.
    """
    ids = {n["id"] for n in nodes}
    ends = sorted(((slot[(id(edge), end)], end, edge) for items in sides for end, edge in items
                   if other_end(end, edge) in ids), key=lambda e: e[0])
    runs = []
    for y, end, edge in ends:
        if runs and runs[-1][0] == other_end(end, edge):
            runs[-1][2] = y
        else:
            runs.append([other_end(end, edge), y, y])
    linked = {r[0] for r in runs}
    bottom = runs[-1][2] if runs else PAD + 31 - SLOT
    runs += [[n["id"], bottom + SLOT * k, bottom + SLOT * k] for k, n in enumerate(
        [n for n in nodes if n["id"] not in linked], 1)]
    for node, first, last in runs:
        canvas.rect(box_x, first - BOX_H / 2, box_w, last - first + BOX_H, "node", node=node)
        canvas.text(box_x + box_w / 2, (first + last) / 2 + 4, labels[node])
    near_x = box_x + box_w if box_x < part_x else box_x
    for y, end, edge in ends:
        start, finish = ((part_x, y), (near_x, y)) if end == "from" else ((near_x, y), (part_x, y))
        canvas.path(line(start, finish), source=edge["from"], target=edge["to"])
        if edge.get("label"):
            canvas.text(label_x, y - 6, edge["label"], "lbl")


def svg_flow(flow, prefix):
    parts, callers, dependencies = (flow.get(k) or [] for k in ("parts", "callers", "dependencies"))
    labels = {n["id"]: str(n.get("label") or n["id"]) for n in parts + callers + dependencies}
    index = {p["id"]: i for i, p in enumerate(parts)}
    caller_ids = {c["id"] for c in callers}
    left, right, gaps, loops = [[] for _ in parts], [[] for _ in parts], [[] for _ in parts], []
    for edge in flow.get("edges") or []:
        source, target = edge["from"], edge["to"]
        if source in index and target in index:
            if abs(index[source] - index[target]) == 1:
                gaps[min(index[source], index[target])].append(edge)
            else:
                loops.append(edge)
                right[index[source]].append(("from", edge))
                right[index[target]].append(("to", edge))
        elif source in index or target in index:
            end, outer = ("from", target) if source in index else ("to", source)
            if outer in labels:
                (left if outer in caller_ids else right)[index[edge[end]]].append((end, edge))
    order = {n["id"]: k for k, n in enumerate(callers + dependencies)}
    touches = collections.defaultdict(set)
    for side in (left, right):
        for i, items in enumerate(side):
            for end, edge in items:
                touches[other_end(end, edge)].add(i)

    def slot_key(i, item):
        outer = other_end(*item)
        if outer not in order:
            return (2, 0, 0)
        # A node that also touches the part above goes first, and one that touches the part below goes last.
        # Then its ends on two parts can share one box.
        return (i - 1 not in touches[outer], i + 1 in touches[outer], order[outer])

    left = [sorted(items, key=lambda item: slot_key(i, item)) for i, items in enumerate(left)]
    right = [sorted(items, key=lambda item: slot_key(i, item)) for i, items in enumerate(right)]
    rows = [max(1, len(l), len(r)) for l, r in zip(left, right)]
    part_w = max([text_width(labels[p["id"]]) + 28 for p in parts]
                 + [16 + sum(map(lane_width, g)) for g in gaps] + [60])
    caller_w = max([text_width(labels[c["id"]]) + 24 for c in callers] + [0])
    dependency_w = max([text_width(labels[d["id"]]) + 24 for d in dependencies] + [0])
    side_gap = [max([text_width(e.get("label", "")) for items in side for _, e in items] + [16]) + 32
                for side in (left, right)]
    service_x = PAD + caller_w + side_gap[0] if callers else PAD
    part_x = service_x + 16
    part_right = part_x + part_w
    service_right = part_right + 16 + sum(map(lane_width, loops))
    tops, heights, y = [], [], PAD + 16
    for i in range(len(parts)):
        tops.append(y)
        heights.append(rows[i] * SLOT - 14)
        y += heights[i] + (SLOT if gaps[i] else 14)
    service_bottom = (tops[-1] + heights[-1] if parts else PAD + 46) + 16
    slot = {}
    for side in (left, right):
        for i, items in enumerate(side):
            for r, (end, edge) in enumerate(items):
                slot[(id(edge), end)] = tops[i] + 15 + SLOT * (r + (rows[i] - len(items)) / 2)

    canvas = Canvas(prefix, caption("flow", flow))
    canvas.rect(service_x, PAD, service_right - service_x, service_bottom - PAD, "svc", rx=10)
    for i, part in enumerate(parts):
        canvas.rect(part_x, tops[i], part_w, heights[i], "node", node=part["id"])
        canvas.text(part_x + part_w / 2, tops[i] + heights[i] / 2 + 4, labels[part["id"]])
    dependency_x = service_right + side_gap[1]
    outer_column(canvas, callers, left, labels, slot, PAD, caller_w, part_x, (PAD + caller_w + service_x) / 2)
    outer_column(canvas, dependencies, right, labels, slot, dependency_x, dependency_w, part_right,
                 (service_right + dependency_x) / 2)
    for i, gap in enumerate(gaps):
        x = part_x + 16
        for edge in gap:
            upper, lower = (x, tops[i] + heights[i]), (x, tops[i + 1])
            down = index[edge["from"]] < index[edge["to"]]
            canvas.path(line(upper, lower) if down else line(lower, upper), source=edge["from"], target=edge["to"])
            if edge.get("label"):
                canvas.text(x + 6, (upper[1] + lower[1]) / 2 + 4, edge["label"], "lbl", anchor="start")
            x += lane_width(edge)
    x = part_right + 16
    for edge in loops:
        y_from, y_to = slot[(id(edge), "from")], slot[(id(edge), "to")]
        canvas.path(line((part_right, y_from), (x, y_from), (x, y_to), (part_right, y_to)),
                    source=edge["from"], target=edge["to"])
        if edge.get("label"):
            canvas.text(x + 6, (y_from + y_to) / 2 + 4, edge["label"], "lbl", anchor="start")
        x += lane_width(edge)
    return canvas.svg()


def svg_sequence(sequence, prefix):
    steps = sequence.get("steps") or []
    names = sequence_participants(steps)
    canvas = Canvas(prefix, caption("sequence", sequence))
    if not names:
        return canvas.svg()
    widths = [text_width(n) + 24 for n in names]
    gaps = [(widths[i] + widths[i + 1]) / 2 + 24 for i in range(len(names) - 1)]
    spans = []
    for step in steps:
        low, high = sorted((names.index(step["from"]), names.index(step["to"])))
        need = text_width(step.get("label", ""))
        if low != high:
            spans.append((low, high, need + 24))
        elif high + 1 < len(names):
            spans.append((low, high + 1, need + 52))
    for low, high, need in sorted(spans, key=lambda s: s[1] - s[0]):
        deficit = need - sum(gaps[low:high])
        if deficit > 0:
            gaps[high - 1] += deficit
    centers = [PAD + widths[0] / 2]
    for gap in gaps:
        centers.append(centers[-1] + gap)
    first_row = PAD + BOX_H + 34
    lifeline_end = first_row + STEP * (len(steps) - 1) + 24
    for name, center, width in zip(names, centers, widths):
        canvas.rect(center - width / 2, PAD, width, BOX_H, "node", node=name)
        canvas.text(center, PAD + 19, name)
        canvas.path(line((center, PAD + BOX_H), (center, lifeline_end)), cls="life", arrow=False)
    for row, step in enumerate(steps):
        y = first_row + STEP * row
        source, target = centers[names.index(step["from"])], centers[names.index(step["to"])]
        label = step.get("label", "")
        if source == target:
            canvas.path(line((source, y - 10), (source + 28, y - 10), (source + 28, y + 4), (source, y + 4)),
                        source=step["from"], target=step["to"])
            if label:
                canvas.text(source + 34, y + 1, label, "lbl", anchor="start")
            continue
        canvas.path(line((source, y), (target, y)), source=step["from"], target=step["to"])
        if label:
            canvas.text((source + target) / 2, y - 6, label, "lbl")
    return canvas.svg()


def state_columns(transitions, start):
    """Column of each state: its breadth-first distance from start. States start cannot reach share a last column."""
    column = {start: 0} if start is not None else {}
    queue = collections.deque(column)
    while queue:
        state = queue.popleft()
        for t in transitions:
            if t["from"] == state and t["to"] not in column:
                column[t["to"]] = column[state] + 1
                queue.append(t["to"])
    last = max(column.values()) + 1 if column else 0
    for t in transitions:
        for key in ("from", "to"):
            column.setdefault(t[key], last)
    return column


def svg_states(lifecycle, prefix):
    transitions = lifecycle.get("transitions") or []
    names = sequence_participants(transitions)
    initial = lifecycle.get("initial") if lifecycle.get("initial") in names else None
    column = state_columns(transitions, initial or (names[0] if names else None))
    stacks = collections.defaultdict(list)
    for name in names:
        stacks[column[name]].append(name)
    count = max(stacks) + 1 if stacks else 0
    widths = [max([text_width(n) + 28 for n in stacks[c]] + [0]) for c in range(count)]
    # A back route drops through the gap left of its source column and rises through the gap right of its target column.
    # Column 0 holds only the start state, so a back route never starts there.
    lanes = collections.Counter()
    for t in transitions:
        if t["from"] != t["to"] and column[t["to"]] <= column[t["from"]]:
            lanes[(column[t["from"]] - 1, "source")] += 1
            lanes[(column[t["to"]], "target")] += 1
    gaps = [max([text_width(t.get("label", "")) for t in transitions
                 if column[t["from"]] == c and column[t["to"]] == c + 1] + [20,
                 6 * (lanes[(c, "source")] + lanes[(c, "target")]) - 4]) + 36 for c in range(count)]
    top = PAD + (16 if any(t["from"] == t["to"] for t in transitions) else 0)
    x = PAD + (30 if initial else 0)
    box = {}
    for c in range(count):
        for row, name in enumerate(stacks[c]):
            box[name] = (x, top + STATE_ROW * row, widths[c], STATE_H)
        x += widths[c] + gaps[c]

    canvas = Canvas(prefix, caption("states", lifecycle))
    for name, (bx, by, bw, bh) in box.items():
        canvas.rect(bx, by, bw, bh, "node", rx=12, node=name)
        canvas.text(bx + bw / 2, by + 20, name)
    if initial:
        bx, by = box[initial][:2]
        canvas.shapes.append('<circle class="start" cx="%s" cy="%s" r="5"/>' % (num(bx - 25), num(by + STATE_H / 2)))
        canvas.path(line((bx - 20, by + STATE_H / 2), (bx, by + STATE_H / 2)))
    floor = max([by + bh for bx, by, bw, bh in box.values()] + [0])
    back_count, used = 0, collections.Counter()
    for t in transitions:
        sx, sy, sw, sh = box[t["from"]]
        ex, ey, ew, eh = box[t["to"]]
        step, anchor = column[t["to"]] - column[t["from"]], "middle"
        if step == 1:
            x0, y0, x1, y1 = sx + sw, sy + sh / 2, ex, ey + eh / 2
            d = curve((x0, y0), ((x0 + x1) / 2, y0), ((x0 + x1) / 2, y1), (x1, y1))
            spot = ((x0 + x1) / 2, (y0 + y1) / 2 - 6)
        elif t["from"] == t["to"]:
            d = curve((sx + sw - 20, sy), (sx + sw - 20, sy - 28), (sx + sw + 28, sy + 8), (sx + sw, sy + 8))
            spot, anchor = (sx + sw + 12, sy - 4), "start"
        else:
            # Breadth-first columns make every other edge go back or stay in its column. It runs through the column gaps
            # and a channel below every box, so it crosses no box.
            source_lane, target_lane = (column[t["from"]] - 1, "source"), (column[t["to"]], "target")
            down_x, up_x = sx - 16 - 6 * used[source_lane], ex + ew + 16 + 6 * used[target_lane]
            used.update((source_lane, target_lane))
            channel = floor + 22 + 30 * back_count
            back_count += 1
            d = line((sx, sy + sh - 6), (down_x, sy + sh - 6), (down_x, channel),
                     (up_x, channel), (up_x, ey + eh - 6), (ex + ew, ey + eh - 6))
            spot = ((sx + ex + ew) / 2, channel + 16)
        canvas.path(d, source=t["from"], target=t["to"])
        if t.get("label"):
            canvas.text(spot[0], spot[1], t["label"], "lbl", anchor=anchor)
    return canvas.svg()


def svg_architecture(architecture, prefix):
    layers = architecture.get("layers") or []
    labels = {c["id"]: str(c.get("label") or c["id"]) for layer in layers for c in layer.get("components") or []}
    heads_of = lambda group: [30 + text_width(layer.get("name", ""))
                              + sum(text_width(labels[c["id"]]) + 34 for c in layer.get("components") or []) for layer in group]
    siblings = [layer for layer in layers if layer.get("sibling")]
    layers = [layer for layer in layers if not layer.get("sibling")]
    heads = heads_of(layers)
    widths, heights, inner_w, inner_h = [0] * len(layers), [0] * len(layers), 0, 0
    for depth in reversed(range(len(layers))):
        widths[depth] = inner_w = max(heads[depth], inner_w + 48 if inner_w else 0)
        heights[depth] = inner_h = LAYER_HEAD + (inner_h + 24 if inner_h else 0)
    canvas = Canvas(prefix, caption("architecture", architecture))
    pills = {}
    # Each sibling is a head-high box to the right of the nested group, top-aligned with it.
    next_x = PAD + (widths[0] + 24 if layers else 0)
    placed = [(layer, PAD + 24 * depth, PAD + LAYER_HEAD * depth, widths[depth], heights[depth])
              for depth, layer in enumerate(layers)]
    for layer, head in zip(siblings, heads_of(siblings)):
        placed.append((layer, next_x, PAD, head, LAYER_HEAD))
        next_x += head + 24
    for layer, x, y, width, height in placed:
        canvas.rect(x, y, width, height, "layer", rx=10)
        canvas.text(x + 12, y + 29, layer.get("name", ""), "layer-name", anchor="start")
        pill_x = x + 28 + text_width(layer.get("name", ""))
        for component in layer.get("components") or []:
            width = text_width(labels[component["id"]]) + 24
            canvas.rect(pill_x, y + 12, width, 26, "pill", rx=13, node=component["id"])
            canvas.text(pill_x + width / 2, y + 29, labels[component["id"]])
            pills[component["id"]] = (pill_x + width / 2, y + 12, y + 38)
            pill_x += width + 10
    for pair in architecture.get("implements") or []:
        adapter, port = pills.get(pair["adapter"]), pills.get(pair["port"])
        if not adapter or not port:
            continue
        if adapter[1] < port[1]:
            d = line((adapter[0], adapter[2]), (port[0], port[1]))
        elif adapter[1] > port[1]:
            d = line((adapter[0], adapter[1]), (port[0], port[2]))
        else:
            d = curve((adapter[0], adapter[2]), (adapter[0], adapter[2] + 14),
                      (port[0], port[2] + 14), (port[0], port[2]))
        canvas.path(d, cls="edge impl", source=pair["adapter"], target=pair["port"])
    return canvas.svg()


def html_section(diagrams, deep_dives):
    present = subjects(diagrams)
    if not present and not deep_dives:
        return ""
    draw = {"flow": svg_flow, "sequence": svg_sequence, "states": svg_states, "architecture": svg_architecture}
    out = ["<h2>Diagrams</h2>"]
    for subject, value in present.items():
        kind = subject.partition(":")[0]
        out.append('<figure class="diagram"><figcaption>%s</figcaption>%s</figure>' % (
            esc(caption(kind, value)), draw[kind](value, subject_slug(subject))))
    if deep_dives:
        items = "".join('<li><a href="%s">%s</a>%s</li>' % (
            esc("file://" + quote(d["path"])), esc(d["name"]),
            "" if d["state"] == "fresh" else ' <span class="badge">%s</span>' % esc(d["state"])) for d in deep_dives)
        out.append("<h3>Deep dives</h3><ul>%s</ul>" % items)
    return "\n".join(out)

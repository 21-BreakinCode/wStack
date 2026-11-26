#!/usr/bin/env python3
"""Inline SVG drawings of contract diagrams, and the Diagrams section of the contract page.

The SVG carries classes only. The page CSS colors them with its theme variables.
"""
import collections
import html
import re
from urllib.parse import quote

from contract_diagrams import display_width, flow_overview, part_cards, sequence_participants, state_columns, subject_slug, subjects

COLUMN_PX = 7.5  # estimated width of one display column of 13px text
PAD = 12
BOX_H = 30
SLOT = 36  # flow overview: vertical distance between two edge ends on one side of a part
LANE_GAP = 10  # flow overview: space between a part and its nearest lane, and between the last lane and the zone edge
LANE_PITCH = 8  # flow overview: distance between two lanes
CALLBACK_GAP = 36  # flow overview: space between a callback box and the zone
STEP = 36  # sequence: vertical distance between two steps
STATE_H = 32
STATE_ROW = 76
LANE = 24  # states: vertical distance between two lanes below the boxes, and between two forward label rows
LEG = 8  # states: horizontal distance between two vertical legs beside one column
FIRST_LEG = 12  # states: distance from a box side to the nearest leg
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


def rounded(*points):
    """An orthogonal line through the points, each corner rounded."""
    sign = lambda v: (v > 0) - (v < 0)
    d = "M%s %s" % (num(points[0][0]), num(points[0][1]))
    for (x0, y0), (x1, y1), (x2, y2) in zip(points, points[1:], points[2:]):
        r = min(6, (abs(x1 - x0) + abs(y1 - y0)) / 2, (abs(x2 - x1) + abs(y2 - y1)) / 2)
        d += " L%s %s Q%s %s %s %s" % tuple(num(v) for v in (
            x1 - r * sign(x1 - x0), y1 - r * sign(y1 - y0), x1, y1, x1 + r * sign(x2 - x1), y1 + r * sign(y2 - y1)))
    return d + " L%s %s" % (num(points[-1][0]), num(points[-1][1]))


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


def count_label(count, singular, plural):
    return "%d %s" % (count, singular if count == 1 else plural)


class FlowLayout:
    """Sizes and positions of the flow overview.

    Caller arrows and callback arrows end on the left side of a part. Part-to-part lanes run on the right.
    A callback box sits left of the zone, so no callback arrow crosses a link lane.
    """

    def __init__(self, flow):
        self.overview = overview = flow_overview(flow)
        self.parts = parts = overview["parts"]
        self.labels = {n["id"]: str(n.get("label") or n["id"]) for kind in ("parts", "dependencies") for n in flow.get(kind) or []}
        index = {part: i for i, part in enumerate(parts)}
        self.links = sorted(overview["links"], key=lambda link: abs(index[link[0]] - index[link[1]]))
        self.left_ends = {part: [("_callers", part)] if part in overview["caller_targets"] else [] for part in parts}
        self.right_ends = {part: [] for part in parts}
        for source, target in self.links:
            self.right_ends[source].append((source, target, "from"))
            self.right_ends[target].append((source, target, "to"))
        for source, target in overview["callbacks"]:
            self.left_ends[target].append((source, target))
        self.callers_text = count_label(overview["callers"], "caller", "callers") if overview["callers"] else ""
        self.dependencies_text = (
            count_label(overview["dependencies"], "dependency", "dependencies") if overview["dependencies"] else "")
        self.callback_w = max([text_width(self.labels[d]) + 24 for d, _ in overview["callbacks"]] + [0])
        self.place(len(overview["caller_targets"]))

    def place(self, caller_lanes):
        wide = max([text_width(self.labels[p]) + 28 for p in self.parts]
                   + [text_width(self.callers_text) + 24, text_width(self.dependencies_text) + 24, 60])
        self.caller_lanes = caller_lanes
        self.zone_x = PAD + (self.callback_w + CALLBACK_GAP if self.callback_w else 0)
        self.part_x = self.zone_x + LANE_GAP + caller_lanes * LANE_PITCH + LANE_GAP
        self.part_w = wide
        self.part_right = self.part_x + wide
        self.zone_w = self.part_right + LANE_GAP + len(self.links) * LANE_PITCH + LANE_GAP - self.zone_x
        self.zone_top = PAD + (BOX_H + SLOT if self.callers_text else 0)
        self.tops, self.heights, y = {}, {}, self.zone_top + 16
        for part in self.parts:
            self.tops[part] = y
            self.heights[part] = max(BOX_H, SLOT * max(len(self.left_ends[part]), len(self.right_ends[part])))
            y += self.heights[part] + 14
        self.zone_bottom = (y - 14 if self.parts else self.zone_top + 30) + 16

    def left_y(self, part, end):
        return self.tops[part] + SLOT * (self.left_ends[part].index(end) + 0.5)

    def right_y(self, part, end):
        return self.tops[part] + SLOT * (self.right_ends[part].index(end) + 0.5)


def draw_flow_boxes(canvas, layout):
    if layout.callers_text:
        canvas.rect(layout.zone_x, PAD, layout.zone_w, BOX_H, "node", node="_callers")
        canvas.text(layout.zone_x + layout.zone_w / 2, PAD + BOX_H / 2 + 4, layout.callers_text)
    canvas.rect(layout.zone_x, layout.zone_top, layout.zone_w, layout.zone_bottom - layout.zone_top, "svc", rx=10,
                node="_zone")
    for part in layout.parts:
        canvas.rect(layout.part_x, layout.tops[part], layout.part_w, layout.heights[part], "node", node=part)
        canvas.text(layout.part_x + layout.part_w / 2, layout.tops[part] + layout.heights[part] / 2 + 4,
                    layout.labels[part])
    if layout.dependencies_text:
        box_top = layout.zone_bottom + SLOT
        canvas.rect(layout.zone_x, box_top, layout.zone_w, BOX_H, "node", node="_dependencies")
        canvas.text(layout.zone_x + layout.zone_w / 2, box_top + BOX_H / 2 + 4, layout.dependencies_text)


def draw_flow_arrows(canvas, layout):
    targets = layout.overview["caller_targets"]
    for k, target in enumerate(targets):  # a later target gets a lane further left, so no caller lane crosses another
        lane_x = layout.zone_x + LANE_GAP + LANE_PITCH * (len(targets) - 1 - k)
        y = layout.left_y(target, ("_callers", target))
        canvas.path(line((lane_x, PAD + BOX_H), (lane_x, y), (layout.part_x, y)), source="_callers", target=target)
    for rank, (source, target) in enumerate(layout.links):
        lane_x = layout.part_right + LANE_GAP + LANE_PITCH * rank
        y_from, y_to = layout.right_y(source, (source, target, "from")), layout.right_y(target, (source, target, "to"))
        canvas.path(line((layout.part_right, y_from), (lane_x, y_from), (lane_x, y_to), (layout.part_right, y_to)),
                    source=source, target=target)
    for dependency, target in layout.overview["callbacks"]:
        y = layout.left_y(target, (dependency, target))
        box_w = text_width(layout.labels[dependency]) + 24
        canvas.rect(PAD, y - BOX_H / 2, box_w, BOX_H, "node", node=dependency)
        canvas.text(PAD + box_w / 2, y + 4, layout.labels[dependency])
        canvas.path(line((PAD + box_w, y), (layout.part_x, y)), source=dependency, target=target)
    if layout.dependencies_text:
        middle = layout.zone_x + layout.zone_w / 2
        canvas.path(line((middle, layout.zone_bottom), (middle, layout.zone_bottom + SLOT)),
                    source="_zone", target="_dependencies")


def svg_flow_overview(flow, prefix):
    """Callers on top, the service zone with one box per part, dependencies below, all in a narrow column."""
    layout = FlowLayout(flow)
    canvas = Canvas(prefix, caption("flow", flow))
    draw_flow_boxes(canvas, layout)
    draw_flow_arrows(canvas, layout)
    return canvas.svg()


def flow_cards_html(flow):
    def items(pairs):
        return "<ul>%s</ul>" % "".join("<li>%s</li>" % esc("%s: %s" % pair if pair[1] else pair[0]) for pair in pairs)

    cards = []
    for card in part_cards(flow):
        body = "".join('<p class="muted">%s</p>%s' % (title, items(pairs))
                       for title, pairs in (("called by", card["called_by"]), ("calls", card["calls"])) if pairs)
        cards.append('<section class="card part-card"><h4>%s</h4>%s</section>' % (esc(card["label"]), body))
    return '<div class="cards">%s</div>' % "".join(cards)


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


def label_width(item):
    return text_width(item.get("label", ""))


def state_arrows(transitions, column, row):
    """Split transitions into loops, forward arrows, back arrows and same-column arrows.

    One small loop sits on top of a state. A second loop on the same state is a same-column arrow.
    Back arrows sort by span and same-column arrows by label width, so back + same is the order of the lanes below
    the boxes, shallowest first.
    """
    loops, looped = [], set()
    for t in transitions:
        if t["from"] == t["to"] and t["from"] not in looped:
            loops.append(t)
            looped.add(t["from"])
    forward = sorted([t for t in transitions if column[t["to"]] == column[t["from"]] + 1],
                     key=lambda t: (column[t["from"]], row[t["to"]], row[t["from"]]))
    back = sorted([t for t in transitions if column[t["to"]] < column[t["from"]]],
                  key=lambda t: column[t["from"]] - column[t["to"]])
    same = sorted([t for t in transitions if column[t["to"]] == column[t["from"]] and not any(t is o for o in loops)],
                  key=label_width)
    return loops, forward, back, same


def state_legs(same, back, column, widths):
    """Each leg's distance from its box side, keyed (id(t), side), and each leg zone's width, keyed (column, side).

    A same-column label sits centered under its column, so each deeper same-column arrow puts its legs outside it.
    Back legs go outside those, the shallowest one outermost, so no back lane crosses another back leg.
    """
    outermost, leg = [FIRST_LEG - LEG] * len(widths), {}
    for t in same:
        c = column[t["from"]]
        outermost[c] = max(outermost[c] + LEG, (label_width(t) - widths[c]) / 2 + 8)
        leg[(id(t), "left")] = leg[(id(t), "right")] = outermost[c]
    backs_beside = collections.defaultdict(list)
    for t in back:
        backs_beside[(column[t["from"]], "left")].append(t)
        backs_beside[(column[t["to"]], "right")].append(t)
    for (c, side), items in backs_beside.items():
        for k, t in enumerate(items):
            leg[(id(t), side)] = outermost[c] + LEG * (len(items) - k)
    zone = {(c, side): max(40, outermost[c] + LEG * len(backs_beside[(c, side)]) + 10)
            for c in range(len(widths)) for side in ("left", "right")}
    return leg, zone


def state_boxes(stacks, widths, zone, forward, back, column):
    """Each box as (x, y, w, h), and each label band between two columns as (left, right).

    A band holds the labels of the forward arrows that cross it and of the back arrows into the column on its left.
    """
    top = PAD + 16  # room above the first row for loop labels
    x, box, band = PAD + zone.get((0, "left"), 0), {}, {}
    for c, width in enumerate(widths):
        for r, name in enumerate(stacks[c]):
            box[name] = (x, top + STATE_ROW * r, width, STATE_H)
        x += width + zone[(c, "right")]
        room = max([label_width(t) for t in forward if column[t["from"]] == c]
                   + [label_width(t) for t in back if column[t["to"]] == c] + [20]) + 16
        band[c] = (x, x + room)
        x += room + zone.get((c + 1, "left"), 0)
    return box, band


def state_ports(box, forward, below, leg):
    """The y of each arrow end on a box side, keyed (id(t), "out" or "in").

    Forward ends come first on a side. Below-lane ends follow, the one with the outermost leg highest, so the ends
    of one side never cross each other. The ends of one side spread evenly over its height.
    """
    forward_ends, lane_ends = collections.defaultdict(list), collections.defaultdict(list)
    for t in forward:
        forward_ends[(t["from"], "right")].append((id(t), "out"))
        forward_ends[(t["to"], "left")].append((id(t), "in"))
    for t in below:
        lane_ends[(t["from"], "left")].append((leg[(id(t), "left")], (id(t), "out")))
        lane_ends[(t["to"], "right")].append((leg[(id(t), "right")], (id(t), "in")))
    port = {}
    for name, side in set(forward_ends) | set(lane_ends):
        outermost_first = sorted(lane_ends[(name, side)], key=lambda end: -end[0])
        order = forward_ends[(name, side)] + [key for _, key in outermost_first]
        for k, key in enumerate(order):
            port[key] = box[name][1] + STATE_H * (k + 1) / (len(order) + 1)
    return port


def forward_rows(forward, column, port):
    """The y of the straight middle of each forward arrow: its target end, moved down to keep rows in one band
    LANE apart."""
    row_y, last = {}, {}
    for t in forward:
        c = column[t["from"]]
        row_y[id(t)] = last[c] = max(port[(id(t), "in")], last.get(c, -LANE) + LANE)
    return row_y


def forward_arrows(forward, box, band, column, port, row_y):
    """Paths as (d, transition) and labels as (x, y, text, anchor) for forward arrows.

    Each one bends inside the zone right of its source, runs straight across the band on its own row, and bends
    inside the zone left of its target. Its label sits 6px above that row, centered in the band.
    """
    paths, labels = [], []
    for t in forward:
        x0, x1 = box[t["from"]][0] + box[t["from"]][2], box[t["to"]][0]
        y0, y1, y = port[(id(t), "out")], port[(id(t), "in")], row_y[id(t)]
        xa, xb = band[column[t["from"]]]
        bend_a, bend_b = (x0 + xa) / 2, (xb + x1) / 2
        paths.append(("M%s %s C%s %s %s %s %s %s L%s %s C%s %s %s %s %s %s" % tuple(num(v) for v in (
            x0, y0, bend_a, y0, bend_a, y, xa, y, xb, y, bend_b, y, bend_b, y1, x1, y1)), t))
        if t.get("label"):
            labels.append(((xa + xb) / 2, y - 6, t["label"], "middle"))
    return paths, labels


def lane_arrows(back, same, box, band, column, port, leg, lane_top):
    """Paths and labels for back and same-column arrows, one lane each below the boxes, shallowest first.

    Each one leaves its source on the left side, goes down a leg, runs along its lane, goes up a leg, and enters its
    target on the right side. A same-column label sits centered under its column. A back label sits centered in the
    band right of its target column.
    """
    paths, labels = [], []
    for k, t in enumerate(back + same):
        y = lane_top + LANE * k
        sx, _, sw, _ = box[t["from"]]
        ex, _, ew, _ = box[t["to"]]
        down_x, up_x = sx - leg[(id(t), "left")], ex + ew + leg[(id(t), "right")]
        y0, y1 = port[(id(t), "out")], port[(id(t), "in")]
        paths.append((rounded((sx, y0), (down_x, y0), (down_x, y), (up_x, y), (up_x, y1), (ex + ew, y1)), t))
        if t.get("label"):
            spot = sx + sw / 2 if any(t is s for s in same) else sum(band[column[t["to"]]]) / 2
            labels.append((spot, y - 6, t["label"], "middle"))
    return paths, labels


def loop_arrows(loops, box):
    """Paths and labels for loops: a small loop on the top edge, its label above the box and left of the loop."""
    paths, labels = [], []
    for t in loops:
        sx, sy, sw, _ = box[t["from"]]
        right = sx + sw - 8
        paths.append((curve((right - 20, sy), (right - 20, sy - 22), (right, sy - 22), (right, sy)), t))
        if t.get("label"):
            labels.append((right - 24 - label_width(t), sy - 6, t["label"], "start"))
    return paths, labels


def svg_states(lifecycle, prefix):
    """Columns by breadth-first distance, so every arrow goes one column forward, stays in its column, or goes back.

    Beside each column is a zone for vertical legs. Between two zones is a band that holds only labels and the
    straight middle of forward arrows, each on its own row. Back and same-column arrows each get a lane below all
    boxes. The helpers above place each part.
    """
    transitions = lifecycle.get("transitions") or []
    names = sequence_participants(transitions)
    initial = lifecycle.get("initial") if lifecycle.get("initial") in names else None
    column = state_columns(transitions, initial or (names[0] if names else None))
    stacks = collections.defaultdict(list)
    for name in names:
        stacks[column[name]].append(name)
    row = {name: stacks[column[name]].index(name) for name in names}
    loops, forward, back, same = state_arrows(transitions, column, row)
    # A loop label sits above its box, left of the loop, so the box is wide enough to hold it.
    widths = [max([text_width(n) + 28 for n in stacks[c]]
                  + [label_width(t) + 40 for t in loops if column[t["from"]] == c])
              for c in range(max(stacks) + 1 if stacks else 0)]
    leg, zone = state_legs(same, back, column, widths)
    box, band = state_boxes(stacks, widths, zone, forward, back, column)
    port = state_ports(box, forward, back + same, leg)
    row_y = forward_rows(forward, column, port)
    lane_top = max([by + bh for _, by, _, bh in box.values()] + list(row_y.values()) + [0]) + 26

    canvas = Canvas(prefix, caption("states", lifecycle))
    for name, (bx, by, bw, bh) in box.items():
        canvas.rect(bx, by, bw, bh, "node", rx=12, node=name)
        canvas.text(bx + bw / 2, by + 20, name)
    if initial:
        bx, by = box[initial][:2]
        canvas.shapes.append('<circle class="start" cx="%s" cy="%s" r="5"/>' % (num(bx - 25), num(by + STATE_H / 2)))
        canvas.path(line((bx - 20, by + STATE_H / 2), (bx, by + STATE_H / 2)))
    drawn = [forward_arrows(forward, box, band, column, port, row_y),
             lane_arrows(back, same, box, band, column, port, leg, lane_top), loop_arrows(loops, box)]
    for paths, _ in drawn:
        for d, t in paths:
            canvas.path(d, source=t["from"], target=t["to"])
    for _, labels in drawn:
        for x, y, text, anchor in labels:
            canvas.text(x, y, text, "lbl", anchor=anchor)
    return canvas.svg()


def lane_pairs(implements, layers, siblings):
    """The implements pairs that need their own lanes: a sibling pill with a nested pill, or two nested pills more
    than one layer apart. A straight line between those can cross the pills of the rows between them."""
    row_of = {c["id"]: (depth, False) for depth, layer in enumerate(layers) for c in layer.get("components") or []}
    row_of.update({c["id"]: (0, True) for layer in siblings for c in layer.get("components") or []})
    ends = [(pair, row_of.get(pair["adapter"]), row_of.get(pair["port"])) for pair in implements]
    return [pair for pair, adapter, port in ends
            if adapter and port and (adapter[1] != port[1] or abs(adapter[0] - port[0]) > 1)]


def lane_route(adapter, port, lane, lane_count, group_right, gap):
    # Run orthogonally through the gap beside the nested group and the free band under each pill row, so no
    # other pill is crossed. Each such edge gets its own band and its own vertical in the gap.
    gap_x = group_right + gap * (lane + 1) / (lane_count + 1)
    band = 42 + 3 * lane
    return [(adapter[0], adapter[2]), (adapter[0], adapter[1] - 12 + band), (gap_x, adapter[1] - 12 + band),
            (gap_x, port[1] - 12 + band), (port[0], port[1] - 12 + band), (port[0], port[2])]


def place_layers(layers, siblings, widths, heights, sibling_heads, row_h, gap):
    placed = [(layer, PAD + 24 * depth, PAD + row_h * depth, widths[depth], heights[depth])
              for depth, layer in enumerate(layers)]
    # Each sibling is a head-high box to the right of the nested group, top-aligned with it.
    next_x = PAD + (widths[0] + gap if layers else 0)
    for layer, head in zip(siblings, sibling_heads):
        placed.append((layer, next_x, PAD, head, row_h))
        next_x += head + 24
    return placed, PAD + (widths[0] if layers else 0)


def svg_architecture(architecture, prefix):
    layers = architecture.get("layers") or []
    labels = {c["id"]: str(c.get("label") or c["id"]) for layer in layers for c in layer.get("components") or []}
    heads_of = lambda group: [30 + text_width(layer.get("name", ""))
                              + sum(text_width(labels[c["id"]]) + 34 for c in layer.get("components") or []) for layer in group]
    siblings = [layer for layer in layers if layer.get("sibling")]
    layers = [layer for layer in layers if not layer.get("sibling")]
    crossing = lane_pairs(architecture.get("implements") or [], layers, siblings)
    # Lane k runs 42 + 3k below its row's top and 3px from its neighbors in the gap beside the nested group.
    # The rows and the gap grow so the last band stays 4px above the next row's pills.
    row_h, gap = max(LAYER_HEAD, 31 + 3 * len(crossing)), max(24, 3 * (len(crossing) + 1))
    heads = heads_of(layers)
    widths, heights, inner_w, inner_h = [0] * len(layers), [0] * len(layers), 0, 0
    for depth in reversed(range(len(layers))):
        widths[depth] = inner_w = max(heads[depth], inner_w + 48 if inner_w else 0)
        heights[depth] = inner_h = row_h + (inner_h + 24 if inner_h else 0)
    canvas = Canvas(prefix, caption("architecture", architecture))
    pills = {}
    placed, group_right = place_layers(layers, siblings, widths, heights, heads_of(siblings), row_h, gap)
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
    pairs = [(pair, pills.get(pair["adapter"]), pills.get(pair["port"])) for pair in architecture.get("implements") or []]
    lane_of = {id(pair): lane for lane, pair in enumerate(crossing)}
    for pair, adapter, port in pairs:
        if not adapter or not port:
            continue
        if id(pair) in lane_of:
            d = line(*lane_route(adapter, port, lane_of[id(pair)], len(crossing), group_right, gap))
        elif adapter[1] < port[1]:
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
    draw = {"flow": svg_flow_overview, "sequence": svg_sequence, "states": svg_states, "architecture": svg_architecture}
    out = ["<h2>Diagrams</h2>"]
    for subject, value in present.items():
        kind = subject.partition(":")[0]
        cards = flow_cards_html(value) if kind == "flow" else ""
        out.append('<figure class="diagram"><figcaption>%s</figcaption>%s%s</figure>' % (
            esc(caption(kind, value)), draw[kind](value, subject_slug(subject)), cards))
    if deep_dives:
        items = "".join('<li><a href="%s">%s</a>%s</li>' % (
            esc("file://" + quote(d["path"])), esc(d["name"]),
            "" if d["state"] == "fresh" else ' <span class="badge">%s</span>' % esc(d["state"])) for d in deep_dives)
        out.append("<h3>Deep dives</h3><ul>%s</ul>" % items)
    return "\n".join(out)

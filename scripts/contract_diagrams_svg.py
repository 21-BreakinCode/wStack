#!/usr/bin/env python3
"""Inline SVG drawings of contract diagrams, and the Diagrams section of the contract page.

The SVG carries classes only. The page CSS colors them with its theme variables.
"""
import collections
import html
import math
import re
from urllib.parse import quote

from contract_diagrams import (display_width, flow_overview, key_line, part_cards, sequence_participants, state_columns,
                               state_key, state_order, state_start, subject_slug, subjects)

COLUMN_PX = 7.5  # estimated width of one display column of 13px text
PAD = 12
BOX_H = 30
SLOT = 36  # flow overview: vertical distance between two edge ends on one side of a part
LANE_GAP = 10  # flow overview: space between a part and its nearest lane, and between the last lane and the zone edge
LANE_PITCH = 8  # flow overview: distance between two lanes
CALLBACK_GAP = 36  # flow overview: space between a callback box and the zone
LOOP_W = 28  # sequence: width of a self-step loop
STEP = 36  # sequence: vertical distance between two steps
STATE_H = 32
STATE_GAP = 44  # states: vertical gap between two boxes of one column
BAND = 56  # states: distance between two columns while both side spaces next to it are at their minimum
SIDE_MIN = 16  # states: smallest side space beside a column
START_ROOM = 30  # states: left space of the first column, for the start dot
END_GAP = 18  # states: smallest distance between two arrow ends on one box side
LANE = 24  # states: vertical distance between two lanes below the boxes
LEG = 10  # states: horizontal distance between two vertical legs beside one column
FIRST_LEG = 12  # states: distance from a box side to the nearest leg
BAND_MARK = 14  # states: distance of a band marker from its arrow's end on the right column of the band
LOOP_ROOM = 48  # states: the right part of a box edge that a loop and its marker take
LOOP_DEPTH = 24  # states: room above or below a box for a loop and its marker
LAYER_HEAD = 56
MARKER_R = 8  # radius of a step number marker
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
    """Collects SVG elements and grows the view box to hold them. Number markers paint last."""

    def __init__(self, prefix, title):
        self.arrow_id, self.title = "%s-arrow" % prefix, title
        self.shapes, self.markers, self.right, self.bottom = [], [], 0.0, 0.0

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
        self.shapes.append(element)

    def marker(self, x, y, number):
        self.grow(x + MARKER_R, y + MARKER_R)
        self.markers.append('<circle class="mk" data-n="%d" cx="%s" cy="%s" r="%d"/>' % (number, num(x), num(y), MARKER_R))
        self.markers.append('<text class="mkt" x="%s" y="%s" text-anchor="middle">%d</text>' % (num(x), num(y + 4), number))

    def path(self, d, cls="edge", source=None, target=None, arrow=True, number=None):
        numbers = [float(v) for v in NUMBER.findall(d)]
        self.grow(max(numbers[0::2]), max(numbers[1::2]))
        data = ' data-from="%s" data-to="%s"' % (esc(source), esc(target)) if source is not None else ""
        data += ' data-n="%d"' % number if number is not None else ""
        end = ' marker-end="url(#%s)"' % esc(self.arrow_id) if arrow else ""
        self.shapes.append('<path class="%s"%s d="%s"%s/>' % (cls, data, d, end))

    def svg(self):
        width, height = num(self.right + PAD), num(self.bottom + PAD)
        marker = ('<defs><marker id="%s" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="9" markerHeight="9" '
                  'markerUnits="userSpaceOnUse" orient="auto"><path class="head" d="M0 0 L10 5 L0 10 z"/>'
                  '</marker></defs>' % esc(self.arrow_id))
        return ('<svg xmlns="http://www.w3.org/2000/svg" role="img" viewBox="0 0 %s %s" width="%s" height="%s">'
                '<title>%s</title>%s%s</svg>') % (
            width, height, width, height, esc(self.title), marker, "".join(self.shapes + self.markers))


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
    for step in steps:
        low, high = sorted((names.index(step["from"]), names.index(step["to"])))
        if low == high and high + 1 < len(names):  # a self-step loop and its marker need room before the next lifeline
            gaps[low] = max(gaps[low], LOOP_W + 2 * MARKER_R + 8)
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
        if source == target:
            canvas.path(line((source, y - 10), (source + LOOP_W, y - 10), (source + LOOP_W, y + 4), (source, y + 4)),
                        source=step["from"], target=step["to"], number=row + 1)
            canvas.marker(source + LOOP_W + MARKER_R + 4, y - 3, row + 1)
            continue
        canvas.path(line((source, y), (target, y)), source=step["from"], target=step["to"], number=row + 1)
        canvas.marker((source + target) / 2, y, row + 1)
    return canvas.svg()


SIDES_OF_ROUTE = {"forward": ("right", "left"), "back": ("left", "right"), "lane": ("left", "right"),
                  "leg": ("right", "right")}  # the box side of the source end and of the target end


class StatesLayout:
    """Boxes and arrow ends of the states ladder.

    A forward or back arrow is a curve in the band between two columns. A down or up arrow is a straight line between
    two neighbor rows of one column. A leg runs beside its column, on the right. A lane runs below all boxes. A top or
    bottom loop sits on that edge of its box. A side space is the part of a band next to a column, where legs run.
    """

    def __init__(self, lifecycle):
        transitions = lifecycle.get("transitions") or []
        self.start = state_start(lifecycle)
        names = state_order(lifecycle)
        self.column = state_columns(transitions, self.start or (names[0] if names else None))
        column_count = max(self.column.values(), default=-1) + 1
        self.stacks = [[n for n in names if self.column[n] == c] for c in range(column_count)]
        self.row = {name: stack.index(name) for stack in self.stacks for name in stack}
        loops, self.routes = collections.Counter(), []  # each key transition with its route kind
        for t in state_key(lifecycle):
            source, target = t["from"], t["to"]
            step = self.column[target] - self.column[source]  # breadth-first columns: at most one column forward
            if source == target:
                loops[source] += 1
                kind = {1: "top", 2: "bottom"}.get(loops[source], "leg")
            elif step:
                kind = {1: "forward", -1: "back"}.get(step, "lane")
            elif abs(self.row[target] - self.row[source]) == 1:
                kind = "down" if self.row[target] > self.row[source] else "up"
            else:
                kind = "leg"
            self.routes.append((t, kind))
        self.kind = {t["number"]: kind for t, kind in self.routes}
        self.lanes = sorted((t for t, kind in self.routes if kind == "lane"),
                            key=lambda t: (self.column[t["from"]] - self.column[t["to"]], t["number"]))
        self.ends = collections.defaultdict(list)
        for t, kind in self.routes:
            if kind in SIDES_OF_ROUTE:
                self.ends[(t["from"], SIDES_OF_ROUTE[kind][0])].append((t, "from"))
                self.ends[(t["to"], SIDES_OF_ROUTE[kind][1])].append((t, "to"))
        self.place_legs()
        self.place_boxes()
        self.place_ends()

    def place_legs(self):
        """Each leg's distance from its column, keyed by number, and the side spaces that hold the legs.

        A shorter leg sits nearer its column. A lane's down leg sits left of its source column, outside the band
        markers there. Its up leg sits right of its target column, outside the legs there. A deeper lane takes the
        nearer leg on both sides.
        """
        self.left_offset, self.right_offset = {}, {}
        self.left_space = [START_ROOM if c == 0 and self.start else SIDE_MIN for c in range(len(self.stacks))]
        self.right_space = [SIDE_MIN] * len(self.stacks)
        first_down = BAND_MARK + MARKER_R + 4
        for c in range(len(self.stacks)):
            legs = sorted((t for t, kind in self.routes if kind == "leg" and self.column[t["from"]] == c),
                          key=lambda t: (abs(self.row[t["from"]] - self.row[t["to"]]), t["number"]))
            ups = [t for t in reversed(self.lanes) if self.column[t["to"]] == c]
            downs = [t for t in reversed(self.lanes) if self.column[t["from"]] == c]
            for k, t in enumerate(legs + ups):
                self.right_offset[t["number"]] = FIRST_LEG + LEG * k
            for k, t in enumerate(downs):
                self.left_offset[t["number"]] = first_down + LEG * k
            if legs or ups:
                self.right_space[c] = max(SIDE_MIN, FIRST_LEG + LEG * (len(legs + ups) - 1) + MARKER_R + 4)
            if downs:
                self.left_space[c] = max(self.left_space[c], first_down + LEG * (len(downs) - 1) + 4)

    def place_boxes(self):
        """Each box as (x, y, w, h), and the y of the first lane.

        A box grows taller when a side holds more ends than END_GAP allows. A column grows wider when its vertical
        arrows would be less than END_GAP apart. Two columns are BAND apart, plus what their side spaces need over
        SIDE_MIN.
        """
        self.loops = {(t["from"], kind) for t, kind in self.routes if kind in ("top", "bottom")}
        self.verticals = collections.defaultdict(list)  # (column, upper row): down arrows, then up arrows
        for t, kind in sorted(self.routes, key=lambda route: route[1] != "down"):
            if kind in ("down", "up"):
                self.verticals[(self.column[t["from"]], min(self.row[t["from"]], self.row[t["to"]]))].append(t)
        ends = {name: max(len(self.ends[(name, "left")]), len(self.ends[(name, "right")])) for name in self.row}
        heights = {name: max(STATE_H, END_GAP * (n + 1)) if n > 1 else STATE_H for name, n in ends.items()}
        widths = [max([text_width(name) + 28 for name in stack]
                      + [END_GAP * (len(self.verticals[(c, r)]) + 1) + self.loop_room(c, r)
                         for r in range(len(stack) - 1) if self.verticals[(c, r)]])
                  for c, stack in enumerate(self.stacks)]
        top = PAD + (LOOP_DEPTH if any((stack[0], "top") in self.loops for stack in self.stacks) else 0)
        x, self.box = PAD, {}
        for c, stack in enumerate(self.stacks):
            x, y = x + self.left_space[c], top
            for name in stack:
                self.box[name] = (x, y, widths[c], heights[name])
                y += heights[name] + STATE_GAP
            x += widths[c] + self.right_space[c] + BAND - 2 * SIDE_MIN
        self.lane_top = LANE + max([y + h + (LOOP_DEPTH if (name, "bottom") in self.loops else 0)
                                    for name, (_, y, _, h) in self.box.items()] + [0])

    def loop_room(self, c, r):
        """The width a loop takes on the facing edges of rows r and r + 1 of column c."""
        upper, lower = self.stacks[c][r], self.stacks[c][r + 1]
        return LOOP_ROOM if (upper, "bottom") in self.loops or (lower, "top") in self.loops else 0

    def place_ends(self):
        """The point of each side end, keyed (number, "from" or "to"). The ends spread evenly over their side."""
        self.end = {}
        for (name, side), ends in self.ends.items():
            x, y, width, height = self.box[name]
            for k, (t, which) in enumerate(sorted(ends, key=lambda end: self.end_order(name, end))):
                self.end[(t["number"], which)] = (x + (width if side == "right" else 0),
                                                  y + height * (k + 1) / (len(ends) + 1))

    def end_order(self, name, end):
        """The sort key of an end on one side of the box of name.

        Curve ends follow the y of the far box, so the curves of one band do not cross. A leg end sits above them when
        its far box is higher or is this box, and below them when its far box is lower. Leg ends sort from the lowest
        far box up, and of two legs between one pair of boxes the outer one ends outside, so nested legs do not cross.
        Lane ends sit between the curves and the lower legs, the shallowest lane highest.
        """
        t, which = end
        far = t["to"] if which == "from" else t["from"]
        kind, far_y = self.kind[t["number"]], self.box[far][1]
        if kind in ("forward", "back"):
            return (1, far_y, t["number"])
        if kind == "lane":
            return (2, self.lanes.index(t), 0)
        if self.row[far] > self.row[name]:
            return (3, -far_y, -t["number"])
        return (0, -far_y, t["number"])

    def band_curve(self, t):
        """The control points of the curve of a forward or back arrow, from end to end."""
        start, end = self.end[(t["number"], "from")], self.end[(t["number"], "to")]
        middle = (start[0] + end[0]) / 2
        return start, (middle, start[1]), (middle, end[1]), end

    def leg_crossings(self, t, leg_x):
        """The points where the arrows from the right sides of the rows between the two ends of a leg meet the x of
        the leg, and MARKER_R to either side of it."""
        low, high = sorted((self.row[t["from"]], self.row[t["to"]]))
        spots = []
        for name in self.stacks[self.column[t["from"]]][low + 1:high]:
            for other, which in self.ends[(name, "right")]:
                is_curve, y = self.kind[other["number"]] in ("forward", "back"), self.end[(other["number"], which)][1]
                spots += [point_at_x(self.band_curve(other), x) if is_curve else (x, y)
                          for x in (leg_x - MARKER_R, leg_x, leg_x + MARKER_R)]
        return spots


def point_at_x(points, x):
    """The point at x of a Bézier curve whose x only grows or only shrinks. It halves the range of t 30 times."""
    def point_at(t):  # de Casteljau
        level = points
        while len(level) > 1:
            level = [(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t) for a, b in zip(level, level[1:])]
        return level[0]

    low, high = 0.0, 1.0
    for _ in range(30):
        middle = (low + high) / 2
        if (point_at(middle)[0] - x) * (points[-1][0] - points[0][0]) < 0:
            low = middle
        else:
            high = middle
    return point_at((low + high) / 2)


def band_route(layout, t):
    """A curve from end to end. Its marker sits BAND_MARK from its end on the right column of the band."""
    points = layout.band_curve(t)
    return curve(*points), point_at_x(points, max(points[0][0], points[-1][0]) - BAND_MARK)


def vertical_route(layout, t):
    """A straight line in the gap between two neighbor rows, clear of a loop there. Its marker sits in the middle of
    the gap."""
    c, upper = layout.column[t["from"]], min(layout.row[t["from"]], layout.row[t["to"]])
    arrows = layout.verticals[(c, upper)]
    x, top, width, height = layout.box[layout.stacks[c][upper]]
    x += (width - layout.loop_room(c, upper)) * (arrows.index(t) + 1) / (len(arrows) + 1)
    gap_top, gap_bottom = top + height, layout.box[layout.stacks[c][upper + 1]][1]
    ends = (gap_top, gap_bottom) if layout.kind[t["number"]] == "down" else (gap_bottom, gap_top)
    return line((x, ends[0]), (x, ends[1])), (x, (gap_top + gap_bottom) / 2)


def leg_route(layout, t):
    """Out of a right side, along a leg beside the column, and into a right side. Its marker sits in the middle of the
    leg."""
    start, end = layout.end[(t["number"], "from")], layout.end[(t["number"], "to")]
    leg_x = start[0] + layout.right_offset[t["number"]]
    return rounded(start, (leg_x, start[1]), (leg_x, end[1]), end), (leg_x, (start[1] + end[1]) / 2)


def under_lane_route(layout, t):
    """Down a leg left of the source column, along a lane below all boxes, and up a leg right of the target column.
    Its marker sits in the middle of the lane."""
    start, end = layout.end[(t["number"], "from")], layout.end[(t["number"], "to")]
    down_x, up_x = start[0] - layout.left_offset[t["number"]], end[0] + layout.right_offset[t["number"]]
    lane_y = layout.lane_top + LANE * layout.lanes.index(t)
    return (rounded(start, (down_x, start[1]), (down_x, lane_y), (up_x, lane_y), (up_x, end[1]), end),
            ((down_x + up_x) / 2, lane_y))


def loop_route(layout, t):
    """A small loop on the top or the bottom edge, near the right. Its marker sits just left of the loop."""
    x, y, width, height = layout.box[t["from"]]
    toward = -1 if layout.kind[t["number"]] == "top" else 1
    edge, right = (y if toward < 0 else y + height), x + width - 8
    reach = edge + 22 * toward
    return (curve((right - 20, edge), (right - 20, reach), (right, reach), (right, edge)),
            (right - 32, edge + 12 * toward))


ROUTES = {"forward": band_route, "back": band_route, "down": vertical_route, "up": vertical_route, "leg": leg_route,
          "lane": under_lane_route, "top": loop_route, "bottom": loop_route}


def svg_states(lifecycle, prefix):
    """The states ladder: columns by breadth-first distance from the start, each arrow numbered as in the key."""
    layout = StatesLayout(lifecycle)
    canvas = Canvas(prefix, caption("states", lifecycle))
    for name, (x, y, width, height) in layout.box.items():
        canvas.rect(x, y, width, height, "node", rx=12, node=name)
        canvas.text(x + width / 2, y + height / 2 + 4, name)
    if layout.start:
        x, y, _, height = layout.box[layout.start]
        canvas.shapes.append('<circle class="start" cx="%s" cy="%s" r="5"/>' % (num(x - 25), num(y + height / 2)))
        canvas.path(line((x - 20, y + height / 2), (x, y + height / 2)))
    spots = []
    for t, kind in layout.routes:
        d, (x, y) = ROUTES[kind](layout, t)
        taken = (spots + layout.leg_crossings(t, x)) if kind == "leg" else spots
        # shortcut: a leg marker steps down past taken spots and can pass the end of a short leg, place it along
        # the free part of the leg if that shows up
        while kind == "leg" and any(math.dist((x, y), spot) < 2 * MARKER_R for spot in taken):
            y += 2 * MARKER_R
        spots.append((x, y))
        canvas.path(d, source=t["from"], target=t["to"], number=t["number"])
        canvas.marker(x, y, t["number"])
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


def html_key(lines):
    return '<ol class="key">%s</ol>' % "".join("<li>%s</li>" % esc(text) for text in lines)


def html_section(diagrams, deep_dives):
    present = subjects(diagrams)
    if not present and not deep_dives:
        return ""
    draw = {"flow": svg_flow_overview, "sequence": svg_sequence, "states": svg_states, "architecture": svg_architecture}
    out = ["<h2>Diagrams</h2>"]
    for subject, value in present.items():
        kind = subject.partition(":")[0]
        cards = flow_cards_html(value) if kind == "flow" else ""
        if kind == "sequence":
            cards = html_key([key_line(s["from"], s["to"], s.get("label")) for s in value.get("steps") or []])
        elif kind == "states":
            cards = html_key([key_line(t["from"], t["to"], t.get("label")) for t in state_key(value)])
        out.append('<figure class="diagram"><figcaption>%s</figcaption>%s%s</figure>' % (
            esc(caption(kind, value)), draw[kind](value, subject_slug(subject)), cards))
    if deep_dives:
        items = "".join('<li><a href="%s">%s</a>%s</li>' % (
            esc("file://" + quote(d["path"])), esc(d["name"]),
            "" if d["state"] == "fresh" else ' <span class="badge">%s</span>' % esc(d["state"])) for d in deep_dives)
        out.append("<h3>Deep dives</h3><ul>%s</ul>" % items)
    return "\n".join(out)

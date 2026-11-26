#!/usr/bin/env python3
"""The architecture picture of a contract: nested layers of pills, sibling layers, and implements lines.

contract_diagrams_svg imports svg_architecture and PAGE_LIMIT back, so import that module, not this one.
"""
import collections

from contract_diagrams_svg import LANE_PITCH, PAD, Canvas, caption, curve, line, text_width

LAYER_HEAD = 56
PAGE_LIMIT = 1100  # architecture: widest picture on the page
PILL_ROW = 36  # architecture: distance between two pill rows of one layer
LAYER_PAD_RIGHT = 12  # architecture: space right of the last pill of a row


def lane_pairs(implements, group_rows, sibling_rows):
    """The implements pairs that need their own lanes: a sibling pill with a nested pill, or two pills with a pill row
    between them. A straight line between those can cross the pills of the rows between them."""
    nested_rows = [row for rows in group_rows for row in rows]
    row_of = {name: (number, False) for number, row in enumerate(nested_rows) for name, _, _ in row}
    row_of.update({name: (number, True) for rows in sibling_rows for number, row in enumerate(rows) for name, _, _ in row})
    ends = [(pair, row_of.get(pair["adapter"]), row_of.get(pair["port"])) for pair in implements]
    return [pair for pair, adapter, port in ends
            if adapter and port and (adapter[1] != port[1] or abs(adapter[0] - port[0]) > 1)]


def lane_route(adapter_end, port_end, gap_x):
    # Run orthogonally through the gap beside the nested group and the free band under each pill row, so no
    # other pill is crossed. Each end is (x, pill bottom, band y).
    (adapter_x, adapter_edge, adapter_band), (port_x, port_edge, port_band) = adapter_end, port_end
    return [(adapter_x, adapter_edge), (adapter_x, adapter_band), (gap_x, adapter_band),
            (gap_x, port_band), (port_x, port_band), (port_x, port_edge)]


def plan_lane_ends(crossing, pills, gap_center):
    """The (x, pill bottom, band y) of both ends of each lane, and its place in the gap, 0 nearest the nested group.

    In each pill row, the lane end nearest the gap takes the band nearest the pills, LANE_PITCH apart, and a lane
    with both ends in one row runs both on one band. Of two ends on one pill, a lane that stays in the row goes
    first, the one with the nearer other end first. Then the lane with the nearer other row goes first at a lower
    end and last at an upper end, and then the lane whose other end is farther from the gap goes first. So the
    lanes nest. Ends on one pill spread LANE_PITCH apart around its center, the nearer band nearer the gap; a
    narrow pill squeezes them. In the gap, the shortest runs start innermost, and two neighbors swap while that
    lets fewer arms pass another lane's run."""
    distance = lambda name: abs(pills[name][0] - gap_center)
    by_row, by_pill, bands, xs = collections.defaultdict(list), collections.defaultdict(list), {}, {}
    for lane, pair in enumerate(crossing):
        for side, other in (("adapter", "port"), ("port", "adapter")):
            name, far = pair[side], pair[other]
            rows_apart, lower = pills[name][1] - pills[far][1], pills[name][1] > pills[far][1]
            tie = ((0, distance(far)) if not rows_apart else
                   (1, abs(rows_apart) if lower else -abs(rows_apart), -distance(far), lane if lower else -lane))
            by_row[pills[name][1]].append(((distance(name), tie), lane, side))
            by_pill[name].append((lane, side))
    for row_top, row_ends in by_row.items():
        row_lanes = list(dict.fromkeys(lane for _, lane, _ in sorted(row_ends)))
        for _, lane, side in row_ends:
            bands[(lane, side)] = row_top + 30 + LANE_PITCH * row_lanes.index(lane)
    for name, pill_ends in by_pill.items():
        center, width = pills[name][0], pills[name][3]
        pitch = min(LANE_PITCH, (width - 16) / max(len(pill_ends) - 1, 1)) * (1 if center < gap_center else -1)
        for place, end in enumerate(sorted(pill_ends, key=lambda end: -bands[end])):
            xs[end] = center + (place - (len(pill_ends) - 1) / 2) * pitch
    spans = {lane: sorted(bands[(lane, side)] for side in ("adapter", "port")) for lane in range(len(crossing))}

    def passes(first, second):  # arms that pass the gap run of another lane when first runs nearer the group
        inside = lambda y, lane: spans[lane][0] < y < spans[lane][1]
        arms = lambda lane, right: [bands[end] for end in ((lane, "adapter"), (lane, "port"))
                                    if (xs[end] > gap_center) == right]
        return sum(inside(y, first) for y in arms(second, False)) + sum(inside(y, second) for y in arms(first, True))

    order = sorted(range(len(crossing)), key=lambda lane: spans[lane][1] - spans[lane][0])
    swapped = True
    while swapped:  # each swap lowers the count of passing arms, so this ends
        swapped = False
        for k in range(len(order) - 1):
            if passes(order[k + 1], order[k]) < passes(order[k], order[k + 1]):
                order[k], order[k + 1], swapped = order[k + 1], order[k], True
    edge = lambda lane, side: pills[crossing[lane][side]][2]
    return {lane: tuple((xs[(lane, side)], edge(lane, side), bands[(lane, side)]) for side in ("adapter", "port"))
            + (order.index(lane),) for lane in range(len(crossing))}


def pill_rows(layer, labels, max_width):
    """The pills of a layer as rows of (id, x offset, width). A pill that would push the layer box past max_width
    starts a new row."""
    start = 28 + text_width(layer.get("name", ""))
    rows, x = [[]], start
    for component in layer.get("components") or []:
        width = text_width(labels[component["id"]]) + 24
        if rows[-1] and x + width + LAYER_PAD_RIGHT > max_width:
            rows.append([])
            x = start
        rows[-1].append((component["id"], x, width))
        x += width + 10
    return rows


def layer_width(layer, rows):
    ends = [row[-1][1] + row[-1][2] + LAYER_PAD_RIGHT for row in rows if row]
    return max([30 + text_width(layer.get("name", ""))] + ends)


def place_layers(layers, siblings, group_rows, sibling_rows, row_h, gap, row_pitch, lane_end_names):
    """Boxes as (layer, pill rows, x, y, width, height), and the x where the lanes' vertical gap starts.
    Siblings sit right of the nested group, or under it when beside would pass PAGE_LIMIT."""
    heights_of = lambda rows: row_h + (len(rows) - 1) * row_pitch
    # A band runs at most row_pitch + 8 below the line 12px above its pill row. No layer sits under a sibling or the
    # innermost layer, so those boxes grow to keep their last band 4px inside: the innermost one only if a lane ends
    # in it.
    holds_bands = lambda rows: max(heights_of(rows), len(rows) * row_pitch + 12)
    has_lane_end = lambda rows: any(name in lane_end_names for row in rows for name, _, _ in row)
    widths, heights, inner_w, inner_h = [0] * len(layers), [0] * len(layers), 0, 0
    for depth in reversed(range(len(layers))):
        widths[depth] = inner_w = max(layer_width(layers[depth], group_rows[depth]), inner_w + 48 if inner_w else 0)
        own_rows = group_rows[depth]
        innermost_h = holds_bands(own_rows) if has_lane_end(own_rows) else heights_of(own_rows)
        heights[depth] = inner_h = heights_of(own_rows) + inner_h + 24 if inner_h else innermost_h
    placed, y = [], PAD
    for depth, layer in enumerate(layers):
        placed.append((layer, group_rows[depth], PAD + 24 * depth, y, widths[depth], heights[depth]))
        y += heights_of(group_rows[depth])
    group_right = PAD + (widths[0] if layers else 0)
    sibling_widths = [layer_width(layer, rows) for layer, rows in zip(siblings, sibling_rows)]
    beside_width = group_right + gap + sum(sibling_widths) + 24 * (len(siblings) - 1) + PAD
    under = bool(layers and siblings) and beside_width > PAGE_LIMIT
    x, top = (PAD, PAD + heights[0] + 24) if under else (group_right + gap if layers else PAD, PAD)
    for layer, rows, width in zip(siblings, sibling_rows, sibling_widths):
        placed.append((layer, rows, x, top, width, holds_bands(rows)))
        x += width + 24
    return placed, max(group_right, x - 24) if under else group_right


def draw_layers(canvas, placed, labels, row_pitch):
    """Draw the layer boxes and pills. Returns each pill as (center x, top, bottom, width)."""
    pills = {}
    for layer, rows, x, y, width, height in placed:
        canvas.rect(x, y, width, height, "layer", rx=10)
        canvas.text(x + 12, y + 29, layer.get("name", ""), "layer-name", anchor="start")
        for number, row in enumerate(rows):
            for name, offset, pill_width in row:
                top = y + 12 + number * row_pitch
                canvas.rect(x + offset, top, pill_width, 26, "pill", rx=13, node=name)
                canvas.text(x + offset + pill_width / 2, top + 17, labels[name])
                pills[name] = (x + offset + pill_width / 2, top, top + 26, pill_width)
    return pills


def svg_architecture(architecture, prefix):
    layers = architecture.get("layers") or []
    labels = {c["id"]: str(c.get("label") or c["id"]) for layer in layers for c in layer.get("components") or []}
    siblings = [layer for layer in layers if layer.get("sibling")]
    layers = [layer for layer in layers if not layer.get("sibling")]
    crossing = []
    while True:  # wrapped rows can need more lanes, and more lanes take more width: wrap again until the count stays
        gap = max(24, LANE_PITCH * (len(crossing) + 1))  # the lanes' gap, drawn as wide as the rows left room for
        budget = PAGE_LIMIT - 2 * PAD - (gap if crossing else 0)
        # an outer layer is 48px wider than its inner layer, so each level takes 48px of budget
        group_rows = [pill_rows(layer, labels, budget - 48 * depth) for depth, layer in enumerate(layers)]
        sibling_rows = [pill_rows(layer, labels, budget) for layer in siblings]
        found = lane_pairs(architecture.get("implements") or [], group_rows, sibling_rows)
        if len(found) <= len(crossing):
            break
        crossing = found
    crossing = found
    # Lane k runs 42 + LANE_PITCH * k below its row's top and LANE_PITCH from its neighbors in the gap beside the
    # nested group. The rows, the pill rows and the gap grow so the last band stays 4px above the next pills.
    lane_room = 34 + LANE_PITCH * (len(crossing) - 1)
    row_h, row_pitch = max(LAYER_HEAD, lane_room), max(PILL_ROW, lane_room)
    canvas = Canvas(prefix, caption("architecture", architecture))
    lane_end_names = {pair[side] for pair in crossing for side in ("adapter", "port")}
    placed, group_right = place_layers(layers, siblings, group_rows, sibling_rows, row_h, gap, row_pitch,
                                       lane_end_names)
    pills = draw_layers(canvas, placed, labels, row_pitch)
    lane_ends = plan_lane_ends(crossing, pills, group_right + gap / 2)
    lane_of = {id(pair): lane for lane, pair in enumerate(crossing)}
    for pair in architecture.get("implements") or []:
        adapter, port = pills.get(pair["adapter"]), pills.get(pair["port"])
        if not adapter or not port:
            continue
        if id(pair) in lane_of:
            adapter_end, port_end, place = lane_ends[lane_of[id(pair)]]
            d = line(*lane_route(adapter_end, port_end, group_right + gap * (place + 1) / (len(crossing) + 1)))
        elif adapter[1] < port[1]:
            d = line((adapter[0], adapter[2]), (port[0], port[1]))
        elif adapter[1] > port[1]:
            d = line((adapter[0], adapter[1]), (port[0], port[2]))
        else:
            d = curve((adapter[0], adapter[2]), (adapter[0], adapter[2] + 14),
                      (port[0], port[2] + 14), (port[0], port[2]))
        canvas.path(d, cls="edge impl", source=pair["adapter"], target=pair["port"])
    return canvas.svg()

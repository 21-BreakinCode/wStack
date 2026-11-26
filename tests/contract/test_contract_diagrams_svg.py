"""Unit tests for scripts/contract_diagrams_svg.py: python3 tests/contract/test_contract_diagrams_svg.py"""
import ast
import collections
import copy
import itertools
import json
import math
import re
import subprocess
import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import contract_diagrams_svg as cds  # noqa: E402

DIAGRAMS = {}
MEDIA = {}
NASTY = '<b>&"x"'
NASTY_ESCAPED = "&lt;b&gt;&amp;&quot;x&quot;"


def sequence_participants_of(sequence):
    return {end for step in sequence["steps"] for end in (step["from"], step["to"])}


def setUpModule():
    out = subprocess.check_output(
        ["yq", "-o=json", str(ROOT / "tests/fixtures/contract/diagrams-block.yaml")])
    DIAGRAMS.update(json.loads(out)["diagrams"])
    media = subprocess.check_output(
        ["yq", "-o=json", str(ROOT / "tests/fixtures/contract/media-shaped-diagrams.yaml")])
    MEDIA.update(json.loads(media)["diagrams"])


def drawings():
    return [cds.svg_flow_overview(DIAGRAMS["flow"], "flow"),
            cds.svg_sequence(DIAGRAMS["sequences"][0], "sequence-create"),
            cds.svg_states(DIAGRAMS["states"][0], "states-item-status"),
            cds.svg_architecture(DIAGRAMS["architecture"], "architecture")]


def shapes(text):
    """Boxes by data-id as lists of (x, y, w, h), and edges as (from, to, first point, last point, all points)."""
    boxes, edges = {}, []
    for element in ET.fromstring(text).iter():
        if element.get("data-id") is not None:
            boxes.setdefault(element.get("data-id"), []).append(
                tuple(float(element.get(k)) for k in ("x", "y", "width", "height")))
        if element.get("data-from") is not None:
            numbers = [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", element.get("d"))]
            points = list(zip(numbers[0::2], numbers[1::2]))
            edges.append((element.get("data-from"), element.get("data-to"), points[0], points[-1], points))
    return boxes, edges


def rects_of_class(text, name):
    return [tuple(float(r.get(k)) for k in ("x", "y", "width", "height"))
            for r in ET.fromstring(text).iter() if r.get("class") == name]


def on_border(point, box):
    x, y = point
    left, top, width, height = box
    inside = left - 0.5 <= x <= left + width + 0.5 and top - 0.5 <= y <= top + height + 0.5
    return inside and min(abs(x - left), abs(x - left - width), abs(y - top), abs(y - top - height)) <= 0.5


def view_width(text):
    return float(ET.fromstring(text).get("viewBox").split()[2])


def transition(source, target, label):
    return {"from": source, "to": target, "label": label, "refs": ["a.go:1"]}


# The shape of a real lifecycle: 4 states, 8 transitions, 5 of them back or same-column arrows.
TASK_STATUS = {"id": "tray-amoral", "title": "Task status", "initial": "queued", "transitions": [
    transition("queued", "done", "worker reports completed"),
    transition("queued", "failed", "reputed, secesh finally, or youse xylol"),
    transition("failed", "done", "late completed message"),
    transition("queued", "waiting_result", "remote service accepts the job"),
    transition("failed", "waiting_result", "remote message for a failed task"),
    transition("waiting_result", "done", "remote result copied"),
    transition("waiting_result", "failed", "job fails or worker error"),
    transition("failed", "queued", "saker, saker_notum below 3")]}

# Three arrows from one state into one column, and two of them back.
SHARED_COLUMN = {"id": "fetch", "title": "Fetch", "initial": "queued", "transitions": [
    transition("queued", "fetching", "worker picks it"), transition("queued", "parsing", "cached file"),
    transition("queued", "failed", "bad input"), transition("fetching", "queued", "fetch timeout"),
    transition("parsing", "queued", "parse retry")]}

FORWARD_ONLY = {"id": "post", "title": "Post", "initial": "draft", "transitions": [
    transition("draft", "review", "submit"), transition("review", "published", "approve")]}

TWO_LOOPS = {"id": "link", "title": "Link", "initial": "idle", "transitions": [
    transition("idle", "idle", "ping"), transition("idle", "idle", "tick"), transition("idle", "open", "connect")]}

THREE_LOOPS = dict(TWO_LOOPS, id="link-3", transitions=TWO_LOOPS["transitions"] + [transition("idle", "idle", "sweep")])

# Legs beside one column: two that share an end, and two between the same pair of boxes.
NESTED_LEGS = {"id": "nested-legs", "initial": "s", "transitions": [
    {"from": s, "to": t} for s, t in [("s", "a"), ("s", "b"), ("s", "c"), ("s", "d"), ("d", "a"), ("d", "b")]]}
LEGS_BOTH_WAYS = {"id": "legs-both-ways", "initial": "s", "transitions": [
    {"from": s, "to": t} for s, t in [("s", "a"), ("s", "b"), ("s", "c"), ("a", "c"), ("c", "a")]]}


def legs_over_a_row(name, pairs):
    """Column 1 holds a, b and c. The pairs add legs between a and c, past b, and the arrow b -> d."""
    return {"id": name, "initial": "q", "transitions": [
        {"from": s, "to": t} for s, t in [("q", "a"), ("q", "b"), ("q", "c")] + pairs]}


LEGS_OVER_A_ROW = [legs_over_a_row("leg-up-over-a-row", [("b", "d"), ("c", "a")]),
                   legs_over_a_row("leg-down-over-a-row", [("b", "d"), ("a", "c")]),
                   legs_over_a_row("two-legs-over-a-row", [("b", "d"), ("a", "c"), ("c", "a")]),
                   # x sits above d, so b -> d is nearly flat where it meets the outer leg
                   legs_over_a_row("two-legs-over-a-flat-row",
                                   [("q", "e"), ("e", "x"), ("b", "d"), ("a", "c"), ("c", "a")])]

# q fans out to a, b and c, those fan in to d, and d goes back to q under the boxes.
LANE_PAST_FANS = {"id": "lane-past-fans", "initial": "q", "transitions": [
    {"from": s, "to": t} for s, t in [("q", "a"), ("q", "b"), ("q", "c"), ("a", "d"), ("b", "d"), ("c", "d"),
                                      ("d", "q")]]}

# Two lanes over overlapping column ranges: s2 back to s0, and s3 back to s1 past the first lane's marker.
OVERLAPPING_LANES = {"id": "overlapping-lanes", "initial": "s0", "transitions": [
    {"from": s, "to": t} for s, t in [("s0", "s1"), ("s1", "s2"), ("s2", "s3"), ("s2", "s0"), ("s3", "s1")]]}

# Back arrows by one and by two columns, and arrows both ways between two neighbor rows.
MANY_BACK_ROUTES = {"id": "many-back", "initial": "a", "transitions": [
    {"from": s, "to": t} for s, t in [("a", "b"), ("b", "c"), ("b", "d"), ("d", "a"), ("d", "a"), ("c", "d"),
                                      ("d", "c"), ("d", "b"), ("c", "b"), ("c", "b"), ("c", "b")]]}


def item_status_with_more_arrows():
    """The basic lifecycle plus a loop, a same-column pair, a second forward arrow, and a back arrow by two columns."""
    lifecycle = copy.deepcopy(DIAGRAMS["states"][0])
    lifecycle["transitions"] += [{"from": "queued", "to": "queued", "label": "wait"},
                                 {"from": "failed", "to": "done", "label": "manual fix"},
                                 {"from": "new", "to": "failed", "label": "fast fail"},
                                 {"from": "done", "to": "new", "label": "reopen"}]
    return lifecycle


def state_fixtures():
    with_second_loop = item_status_with_more_arrows()
    with_second_loop["transitions"].append({"from": "queued", "to": "queued", "label": "heartbeat"})
    return [MEDIA["states"][0], SHARED_COLUMN, TASK_STATUS, FORWARD_ONLY, TWO_LOOPS, THREE_LOOPS, MANY_BACK_ROUTES,
            NESTED_LEGS, LEGS_BOTH_WAYS, DIAGRAMS["states"][0], item_status_with_more_arrows(),
            with_second_loop, LANE_PAST_FANS, OVERLAPPING_LANES] + LEGS_OVER_A_ROW


def box_side(point, box):
    """The side of the box that the point is on, or None."""
    if not on_border(point, box):
        return None
    x, y = point
    left, top, width, height = box
    distance = {"left": abs(x - left), "right": abs(x - left - width), "top": abs(y - top),
                "bottom": abs(y - top - height)}
    return min(distance, key=distance.get)


def segments_meet(a, b, c, d):
    """True when segment ab and segment cd share a point, touching included."""
    def turn(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])

    def within(p, q, r):
        return min(p[0], q[0]) <= r[0] <= max(p[0], q[0]) and min(p[1], q[1]) <= r[1] <= max(p[1], q[1])

    turns = (turn(c, d, a), turn(c, d, b), turn(a, b, c), turn(a, b, d))
    if turns[0] * turns[1] < 0 and turns[2] * turns[3] < 0:
        return True
    return any(t == 0 and within(p, q, r) for t, (p, q, r) in zip(turns, ((c, d, a), (c, d, b), (a, b, c), (a, b, d))))


def bezier(points, t):
    while len(points) > 1:
        points = [(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t) for a, b in zip(points, points[1:])]
    return points[0]


def path_samples(d):
    """Points along a path of M, L, Q and C commands, about one pixel apart."""
    out = []
    for command, args in re.findall(r"([MLQC])([^MLQC]*)", d):
        values = [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", args)]
        controls = list(zip(values[0::2], values[1::2]))
        if command == "M":
            out.append(controls[0])
            continue
        controls = [out[-1]] + controls
        steps = max(1, int(sum(abs(b[0] - a[0]) + abs(b[1] - a[1]) for a, b in zip(controls, controls[1:]))))
        out += [bezier(controls, s / steps) for s in range(1, steps + 1)]
    return out


def strictly_inside(point, rect, margin=0.5):
    x, y, w, h = rect
    return x + margin < point[0] < x + w - margin and y + margin < point[1] < y + h - margin


class Base(unittest.TestCase):
    def assert_edges_touch(self, text, expected_pairs):
        boxes, edges = shapes(text)
        self.assertEqual(sorted((e[0], e[1]) for e in edges), sorted(expected_pairs))
        for source, target, first, last, _ in edges:
            name = "%s->%s" % (source, target)
            self.assertTrue(any(on_border(first, b) for b in boxes[source]), name + " starts off its source box")
            self.assertTrue(any(on_border(last, b) for b in boxes[target]), name + " ends off its target box")
        return boxes, edges

    def assert_no_box_crossing(self, boxes, edges):
        for source, target, _, _, points in edges:
            for name, ((bx, by, bw, bh),) in boxes.items():
                for (x0, y0), (x1, y1) in zip(points, points[1:]):
                    if x0 == x1 or y0 == y1:
                        crosses = (min(x0, x1) < bx + bw - 0.5 and max(x0, x1) > bx + 0.5
                                   and min(y0, y1) < by + bh - 0.5 and max(y0, y1) > by + 0.5)
                        self.assertFalse(crosses, "%s->%s crosses %s" % (source, target, name))

    def assert_clean_states(self, lifecycle):
        """Each transition has one path and one marker with its key number, and the numbers are 1..n. No path passes
        strictly inside a box other than its ends. No two markers overlap, and no marker overlaps a box. No other path
        passes strictly inside a marker. All of it is inside the view box.

        Returns paths as (number, (from, to), samples). The start arrow has no number."""
        text = cds.svg_states(lifecycle, "s")
        root = ET.fromstring(text)
        _, _, view_w, view_h = (float(v) for v in root.get("viewBox").split())
        boxes = {e.get("data-id"): tuple(float(e.get(k)) for k in ("x", "y", "width", "height"))
                 for e in root.iter() if e.get("data-id") is not None}
        paths = [(e.get("data-n"), (e.get("data-from"), e.get("data-to")), path_samples(e.get("d")))
                 for e in root.iter() if e.tag.endswith("path") and e.get("class") == "edge"]
        circles = [e for e in root.iter() if e.get("class") == "mk"]
        markers = {e.get("data-n"): (float(e.get("cx")), float(e.get("cy"))) for e in circles}
        key = [(str(t["number"]), (t["from"], t["to"])) for t in cds.state_key(lifecycle)]
        self.assertEqual([n for n, _ in key], [str(n) for n in range(1, len(lifecycle["transitions"]) + 1)])
        self.assertEqual(sorted(((n, owner) for n, owner, _ in paths if n is not None), key=lambda p: int(p[0])), key)
        self.assertEqual(sorted((e.get("data-n") for e in circles), key=int), [n for n, _ in key])
        in_view = lambda x, y: 0 <= x <= view_w and 0 <= y <= view_h
        radius = cds.MARKER_R
        for number, owner, points in paths:
            name = "%s->%s (%s)" % (owner + (number or "start",))
            self.assertTrue(all(in_view(*p) for p in points), name + " leaves the view box")
            for box_name, box in boxes.items():
                if box_name not in owner:
                    self.assertFalse(any(strictly_inside(p, box) for p in points), "%s crosses %s" % (name, box_name))
            for n, center in markers.items():
                nearest = min(math.dist(center, p) for p in points)
                if n == number:
                    self.assertLessEqual(nearest, 2 * radius, "marker %s is far from its arrow" % n)
                else:
                    self.assertGreaterEqual(nearest, radius - 0.5, "%s passes inside marker %s" % (name, n))
        for n, (x, y) in markers.items():
            self.assertTrue(in_view(x - radius, y - radius) and in_view(x + radius, y + radius),
                            "marker %s leaves the view box" % n)
            for other, center in markers.items():
                if other != n:
                    self.assertGreaterEqual(math.dist((x, y), center), 2 * radius, "marker %s overlaps %s" % (n, other))
            for box_name, (bx, by, bw, bh) in boxes.items():
                gap = math.hypot(max(bx - x, 0, x - bx - bw), max(by - y, 0, y - by - bh))
                self.assertGreaterEqual(gap, radius, "marker %s overlaps box %s" % (n, box_name))
        return text, boxes, paths, markers

    def assert_no_crossing(self, paths):
        """No segment between two neighbor samples of one path meets such a segment of another path. A meeting within
        2 px of an end point that the two paths share does not count. Segments are bucketed in 8 px cells."""
        cells = collections.defaultdict(list)
        for index, (_, _, points) in enumerate(paths):
            for a, b in zip(points, points[1:]):
                columns = range(int(min(a[0], b[0]) // 8), int(max(a[0], b[0]) // 8) + 1)
                rows = range(int(min(a[1], b[1]) // 8), int(max(a[1], b[1]) // 8) + 1)
                for cell in itertools.product(columns, rows):
                    cells[cell].append((index, a, b))
        for segments in cells.values():
            for k, (i, a, b) in enumerate(segments):
                for j, c, d in segments[k + 1:]:
                    if i == j or not segments_meet(a, b, c, d):
                        continue
                    ends_i, ends_j = (paths[i][2][0], paths[i][2][-1]), (paths[j][2][0], paths[j][2][-1])
                    shared = [p for p in ends_i for q in ends_j if math.dist(p, q) <= 2]
                    self.assertTrue(any(math.dist(a, p) <= 2 for p in shared),
                                    "path %s crosses path %s near %s" % (paths[i][0], paths[j][0], a))


class Svg(Base):
    def test_svgs_parse(self):
        titles = ["Component flow", "Sequence: Create an item", "States: Item status", "Architecture (clean)"]
        for text, title in zip(drawings(), titles):
            root = ET.fromstring(text)
            self.assertTrue(root.tag.endswith("svg"))
            self.assertTrue(root.get("viewBox"))
            self.assertTrue(root.get("role") == "img" and root[0].tag.endswith("title") and root[0].text == title)

    def test_labels_present_and_escaped(self):
        flow, sequence, states, architecture = drawings()
        for label in ("API", "Worker", "2 callers", "2 dependencies"):
            self.assertIn(">%s<" % label, flow)
        for label in ("web-ui", "api", "worker", "postgres"):
            self.assertIn(">%s<" % label, sequence)
        self.assertNotIn('class="lbl"', sequence)
        for label in ("new", "queued", "done", "failed"):
            self.assertIn(">%s<" % label, states)
        self.assertNotIn('class="lbl"', states)
        self.assertNotIn("a retry", states)
        for label in ("adapters", "use-cases", "entities", "SQL store", "Store port"):
            self.assertIn(">%s<" % label, architecture)

        flow = copy.deepcopy(DIAGRAMS["flow"])
        flow["parts"][0]["label"] = NASTY
        sequence = copy.deepcopy(DIAGRAMS["sequences"][0])
        sequence["steps"][0]["from"] = NASTY
        lifecycle = copy.deepcopy(DIAGRAMS["states"][0])
        lifecycle["transitions"][0]["to"] = NASTY
        architecture = copy.deepcopy(DIAGRAMS["architecture"])
        architecture["layers"][0]["name"] = NASTY
        for text in (cds.svg_flow_overview(flow, "flow"), cds.svg_sequence(sequence, "s"),
                     cds.svg_states(lifecycle, "t"), cds.svg_architecture(architecture, "a")):
            self.assertIn(NASTY_ESCAPED, text)
            self.assertNotIn("<b>", text)
            ET.fromstring(text)

    def test_marker_ids_unique(self):
        section = cds.html_section(DIAGRAMS, [])
        ids = re.findall(r'(?<![\w-])id="([^"]*)"', section)
        self.assertGreaterEqual(len(ids), 4)
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(section.count('<figure class="diagram">'), 4)
        for caption in ("Component flow", "Sequence: Create an item", "States: Item status", "Architecture (clean)"):
            self.assertIn("<figcaption>%s</figcaption>" % caption, section)

    def test_every_media_picture_fits_the_page(self):
        section = cds.html_section(MEDIA, [])
        self.assertEqual(section.count("<svg "), 1 + len(MEDIA["sequences"]) + len(MEDIA["states"]) + 1)
        for width in re.findall(r'\swidth="([^"]*)"', section):
            self.assertLessEqual(float(width), cds.PAGE_LIMIT)

    def test_text_width_counts_wide_characters_twice(self):
        self.assertEqual(cds.text_width("ab"), 2 * cds.COLUMN_PX)
        self.assertEqual(cds.text_width("漢字"), 4 * cds.COLUMN_PX)
        self.assertEqual(cds.text_width("a漢"), 3 * cds.COLUMN_PX)

    def test_long_label_widens(self):
        flow = copy.deepcopy(DIAGRAMS["flow"])
        flow["parts"][0]["label"] = "x" * 40
        self.assertGreater(view_width(cds.svg_flow_overview(flow, "flow")),
                           view_width(cds.svg_flow_overview(DIAGRAMS["flow"], "flow")))

    def test_unreachable_state(self):
        lifecycle = copy.deepcopy(DIAGRAMS["states"][0])
        lifecycle["transitions"].append({"from": "orphan", "to": "done", "refs": ["cmd/main.go:1"]})
        text = cds.svg_states(lifecycle, "states-item-status")
        boxes, _ = shapes(text)
        self.assertIn(">orphan<", text)
        self.assertGreater(boxes["orphan"][0][0], max(b[0][0] for name, b in boxes.items() if name != "orphan"))

    def test_section_empty(self):
        self.assertEqual(cds.html_section({}, []), "")

    def test_badges(self):
        dives = [{"path": "/v/diagrams/flow.html", "name": "flow.html", "subject": "flow", "state": "stale"},
                 {"path": "/v/diagrams/sequence-create.html", "name": "sequence-create.html",
                  "subject": "sequence:create", "state": "fresh"}]
        section = cds.html_section({}, dives)
        self.assertIn("<h3>Deep dives</h3>", section)
        self.assertIn('<a href="file:///v/diagrams/flow.html">flow.html</a>', section)
        self.assertIn('<span class="badge">stale</span>', section)
        self.assertEqual(section.count('class="badge"'), 1)


class Geometry(Base):
    def test_flow_overview_edges_touch(self):
        text = cds.svg_flow_overview(MEDIA["flow"], "flow")
        self.assert_edges_touch(text, [("_callers", "api"), ("api", "abuna-secesh"), ("ticky-let-2", "ticky-secesh"),
                                       ("abuna-let-2", "abuna-toozle-secesh"), ("_zone", "_dependencies")])

    def test_flow_overview_texts(self):
        text = cds.svg_flow_overview(MEDIA["flow"], "flow")
        for label in ["8 callers", "9 dependencies"] + [p["label"] for p in MEDIA["flow"]["parts"]]:
            self.assertIn(">%s<" % cds.esc(label), text)

    def test_flow_overview_fits(self):
        self.assertLessEqual(view_width(cds.svg_flow_overview(MEDIA["flow"], "flow")), 760)

    def test_flow_overview_without_callers_or_dependencies(self):
        flow = copy.deepcopy(MEDIA["flow"])
        flow["callers"], flow["dependencies"] = [], []
        flow["edges"] = [e for e in flow["edges"] if e["from"] in {p["id"] for p in flow["parts"]}]
        boxes, _ = shapes(cds.svg_flow_overview(flow, "flow"))
        self.assertNotIn("_callers", boxes)
        self.assertNotIn("_dependencies", boxes)
        self.assertIn("_zone", boxes)

    def test_flow_overview_one_caller_and_self_link(self):
        flow = copy.deepcopy(DIAGRAMS["flow"])
        flow["callers"] = flow["callers"][:1]
        flow["edges"] = [e for e in flow["edges"] if e["from"] != "batch-job"] + [{"from": "api", "to": "api"}]
        text = cds.svg_flow_overview(flow, "flow")
        self.assertIn(">1 caller<", text)
        self.assert_edges_touch(text, [("_callers", "api"), ("api", "worker"), ("api", "api"), ("other-svc", "worker"),
                                       ("_zone", "_dependencies")])

    def test_flow_overview_callbacks_cross_no_link_lane(self):
        flow = {"parts": [{"id": "a"}, {"id": "b"}, {"id": "c"}], "callers": [{"id": "ui"}],
                "dependencies": [{"id": "dep-b", "label": "dep-b"}, {"id": "dep-c"}],
                "edges": [{"from": "ui", "to": "a"}, {"from": "a", "to": "c"},
                          {"from": "dep-b", "to": "b"}, {"from": "dep-c", "to": "c"}]}
        text = cds.svg_flow_overview(flow, "flow")
        boxes, edges = self.assert_edges_touch(text, [("_callers", "a"), ("a", "c"), ("dep-b", "b"), ("dep-c", "c"),
                                                      ("_zone", "_dependencies")])
        link = [e for e in edges if (e[0], e[1]) == ("a", "c")][0]
        for source, target, _, _, points in edges:
            if source in ("dep-b", "dep-c"):
                for (x0, y0), (x1, y1) in zip(link[4], link[4][1:]):
                    if x0 == x1:  # a vertical run of the link
                        self.assertFalse(min(p[0] for p in points) < x0 < max(p[0] for p in points)
                                         and min(y0, y1) < points[0][1] < max(y0, y1), "%s crosses the link lane" % source)

    def test_flow_overview_links_do_not_cross(self):
        def flow(parts, links):
            return {"parts": [{"id": p} for p in parts], "callers": [{"id": "ui"}],
                    "edges": [{"from": "ui", "to": parts[0]}] + [{"from": s, "to": t} for s, t in links.split()]}

        # one part calls two or three parts, a call and its reply, a chain listed in either order, two parts call one
        flows = [flow("abc", "ab ac"), flow("abcd", "ab ac ad"), flow("ab", "ab ba"), flow("abc", "ab bc"),
                 flow("abc", "bc ab"), flow("abc", "ac bc"), MEDIA["flow"]]
        for value in flows:
            root = ET.fromstring(cds.svg_flow_overview(value, "f"))
            self.assert_no_crossing([("%s>%s" % (e.get("data-from"), e.get("data-to")), None, path_samples(e.get("d")))
                                     for e in root.iter() if e.get("class") == "edge"])

    def test_cards_list_every_edge(self):
        flow = MEDIA["flow"]
        labels = {n["id"]: n.get("label") or n["id"] for k in ("parts", "callers", "dependencies") for n in flow[k]}
        section = cds.flow_cards_html(flow)
        self.assertIn('<div class="cards">', section)
        for card in section.split('<section class="card part-card">')[1:]:
            part = [p for p in flow["parts"] if "<h4>%s</h4>" % cds.esc(labels[p["id"]]) in card][0]["id"]
            called_by, _, calls = card.partition('<p class="muted">calls</p>')
            for edge in flow["edges"]:
                for end, other, body in (("to", "from", called_by), ("from", "to", calls)):
                    if edge[end] == part:
                        name = labels[edge[other]]
                        item = "%s: %s" % (name, edge["label"]) if edge.get("label") else name
                        self.assertIn("<li>%s</li>" % cds.esc(item), body)

    def test_cards_escape_and_skip_empty_lists(self):
        flow = {"parts": [{"id": "a", "label": NASTY}, {"id": "b"}], "edges": [{"from": "a", "to": "b"}]}
        section = cds.flow_cards_html(flow)
        self.assertIn("<h4>%s</h4>" % NASTY_ESCAPED, section)
        self.assertNotIn("<b>", section)
        first, second = section.split('<section class="card part-card">')[1:]
        self.assertNotIn("called by", first)
        self.assertNotIn(">calls<", second)

    def test_sequence_steps_join_lifelines(self):
        sequence = DIAGRAMS["sequences"][0]
        boxes, edges = shapes(cds.svg_sequence(sequence, "sequence-create"))
        self.assertEqual([(e[0], e[1]) for e in edges], [(s["from"], s["to"]) for s in sequence["steps"]])
        centers = {name: box[0][0] + box[0][2] / 2 for name, box in boxes.items()}
        self.assertEqual(sorted(centers, key=centers.get), ["web-ui", "api", "worker", "postgres"])
        rows = []
        for source, target, first, last, points in edges:
            self.assertAlmostEqual(first[0], centers[source], delta=0.5)
            self.assertAlmostEqual(last[0], centers[target], delta=0.5)
            rows.append(first[1])
        self.assertEqual(rows, sorted(rows))
        loop = edges[1][4]
        self.assertGreater(max(p[0] for p in loop), centers["api"])

    def test_sequence_steps_are_numbered(self):
        for sequence in DIAGRAMS["sequences"] + MEDIA["sequences"]:
            root = ET.fromstring(cds.svg_sequence(sequence, "s"))
            paths = {e.get("data-n"): e for e in root.iter() if e.get("class") == "edge"}
            circles = {e.get("data-n"): e for e in root.iter() if e.get("class") == "mk"}
            numbers = [str(n + 1) for n in range(len(sequence["steps"]))]
            self.assertEqual(sorted(paths), sorted(numbers))
            self.assertEqual(sorted(circles), sorted(numbers))
            for n, step in zip(numbers, sequence["steps"]):
                center = (float(circles[n].get("cx")), float(circles[n].get("cy")))
                nearest = min(math.dist(center, p) for p in path_samples(paths[n].get("d")))
                self.assertLessEqual(nearest, 40 if step["from"] == step["to"] else 1)
            self.assertEqual(sorted(e.text for e in root.iter() if e.get("class") == "mkt"), sorted(numbers))

    def test_sequence_fits(self):
        sequence = next(s for s in MEDIA["sequences"] if s["id"] == "ake-abuna-tray")
        self.assertEqual(len(sequence_participants_of(sequence)), 7)
        self.assertLessEqual(view_width(cds.svg_sequence(sequence, "s")), 900)

    def test_key_escapes(self):
        self.assertIn(NASTY_ESCAPED, cds.html_key([NASTY]))
        self.assertTrue(cds.html_key(["a"]).startswith('<ol class="key"><li>a</li>'))

    def test_section_holds_sequence_key(self):
        section = cds.html_section(DIAGRAMS, [])
        self.assertIn("<li>web-ui → api: ", section)
        self.assertEqual(section.count('<ol class="key">'), len(DIAGRAMS["sequences"]) + len(DIAGRAMS["states"]))

    def test_section_holds_states_key(self):
        section = cds.html_section(DIAGRAMS, [])
        lifecycle = DIAGRAMS["states"][0]
        lines = [cds.key_line(t["from"], t["to"], t.get("label")) for t in cds.state_key(lifecycle)]
        self.assertEqual(len(lines), len(lifecycle["transitions"]))
        self.assertIn(cds.svg_states(lifecycle, "states-item-status") + cds.html_key(lines), section)
        self.assertIn("<li>failed → queued: a retry</li>", section)

    def test_states_edges_touch_their_boxes(self):
        lifecycle = DIAGRAMS["states"][0]
        boxes, edges = self.assert_edges_touch(cds.svg_states(lifecycle, "states-item-status"),
                                               [(t["from"], t["to"]) for t in lifecycle["transitions"]])
        columns = [boxes[name][0][0] for name in ("new", "queued", "done")]
        self.assertEqual(columns, sorted(columns))
        self.assertEqual(boxes["done"][0][0], boxes["failed"][0][0])
        back = [e for e in edges if (e[0], e[1]) == ("failed", "queued")][0]
        queued_right = boxes["queued"][0][0] + boxes["queued"][0][2]
        self.assertTrue(all(queued_right <= x <= boxes["failed"][0][0] for x, _ in back[4]),
                        "a back arrow by one column stays in the band between the two columns")

    def test_states_self_same_column_and_back_edges(self):
        lifecycle = item_status_with_more_arrows()
        boxes, edges = self.assert_edges_touch(cds.svg_states(lifecycle, "s"),
                                               [(t["from"], t["to"]) for t in lifecycle["transitions"]])
        self.assert_no_box_crossing(boxes, edges)

    def test_many_back_routes_are_clean(self):
        text, boxes, paths, _ = self.assert_clean_states(MANY_BACK_ROUTES)
        self.assert_edges_touch(text, [(t["from"], t["to"]) for t in MANY_BACK_ROUTES["transitions"]])
        floor = max(y + h for _, y, _, h in boxes.values())
        depths = sorted(max(y for _, y in points) for _, owner, points in paths if owner == ("d", "a"))
        self.assertEqual(len(depths), 2)
        self.assertTrue(floor < depths[0] and depths[1] - depths[0] == cds.LANE, "two lanes under the boxes")

    def test_media_lifecycle_is_clean_and_uncrossed(self):
        text, _, paths, _ = self.assert_clean_states(MEDIA["states"][0])
        self.assert_no_crossing(paths)
        self.assertLessEqual(view_width(text), 600)

    def test_lanes_through_bottom_edges_are_uncrossed(self):
        for lifecycle in (MANY_BACK_ROUTES, LANE_PAST_FANS):  # in MANY_BACK_ROUTES two lanes share both bottom edges
            _, boxes, paths, _ = self.assert_clean_states(lifecycle)
            self.assert_no_crossing(paths)
        lane = [points for _, owner, points in paths if owner == ("d", "q")][0]
        self.assertEqual([box_side(end, boxes[name]) for end, name in ((lane[0], "d"), (lane[-1], "q"))],
                         ["bottom", "bottom"], "the lane leaves and enters through the bottom edges")

    def test_shared_column_sample_is_uncrossed(self):
        _, _, paths, _ = self.assert_clean_states(SHARED_COLUMN)
        self.assert_no_crossing(paths)

    def test_task_status_is_clean(self):
        text, _, paths, _ = self.assert_clean_states(TASK_STATUS)
        self.assert_no_crossing(paths)
        self.assert_edges_touch(text, [(t["from"], t["to"]) for t in TASK_STATUS["transitions"]])

    def test_forward_only_is_not_wider_than_0_10_0(self):
        text, _, _, _ = self.assert_clean_states(FORWARD_ONLY)
        self.assertLessEqual(view_width(text), 457.5)

    def test_second_loop_on_bottom_edge(self):
        _, boxes, paths, _ = self.assert_clean_states(TWO_LOOPS)
        x, y, _, h = boxes["idle"]
        loops = [points for _, owner, points in paths if owner == ("idle", "idle")]
        above = [p for p in loops if min(v for _, v in p) < y and max(v for _, v in p) <= y + 0.5]
        below = [p for p in loops if max(v for _, v in p) > y + h and min(v for _, v in p) >= y + h - 0.5]
        self.assertEqual((len(loops), len(above), len(below)), (2, 1, 1))
        start_y = [points for n, _, points in paths if n is None][0][-1][1]
        self.assertAlmostEqual(start_y, y + h / 2)
        left_ends = [p for n, _, points in paths if n is not None for p in (points[0], points[-1])
                     if box_side(p, boxes["idle"]) == "left"]
        self.assertFalse([p for p in left_ends if abs(p[1] - start_y) < cds.END_GAP / 2])

    def test_nested_legs_are_clean_and_uncrossed(self):
        for lifecycle in (NESTED_LEGS, LEGS_BOTH_WAYS):
            _, boxes, paths, _ = self.assert_clean_states(lifecycle)
            self.assert_no_crossing(paths)
            right = boxes["a"][0] + boxes["a"][2]
            legs = [points for _, owner, points in paths if owner[0] != "s" and owner[0] is not None]
            self.assertEqual(len(legs), 2)
            self.assertTrue(all(x >= right - 0.5 for points in legs for x, _ in points), lifecycle["id"])

    def test_leg_marker_clears_the_arrows_of_the_rows_it_passes(self):
        for lifecycle in LEGS_OVER_A_ROW:
            _, _, paths, markers = self.assert_clean_states(lifecycle)
            for number, owner, points in paths:
                if owner in (("a", "c"), ("c", "a")):
                    leg_x = max(x for x, _ in points)
                    leg_ys = [y for x, y in points if abs(x - leg_x) < 0.01]
                    (x, y), name = markers[number], "%s: marker %s is off its leg" % (lifecycle["id"], number)
                    self.assertAlmostEqual(x, leg_x, msg=name)
                    self.assertTrue(min(leg_ys) < y < max(leg_ys), name)

    def test_module_functions_have_unique_names(self):
        tree = ast.parse(Path(cds.__file__).read_text(encoding="utf-8"))
        names = [node.name for node in tree.body if isinstance(node, (ast.FunctionDef, ast.ClassDef))]
        self.assertEqual(sorted({name for name in names if names.count(name) > 1}), [])

    def test_third_loop_becomes_a_leg(self):
        _, boxes, paths, _ = self.assert_clean_states(THREE_LOOPS)
        x, _, width, _ = boxes["idle"]
        sweep = [points for n, owner, points in paths if owner == ("idle", "idle")][2]
        self.assertTrue(all(x + width - 0.5 <= px for px, _ in sweep), "the third loop runs right of its box")
        self.assertGreaterEqual(max(px for px, _ in sweep), x + width + cds.FIRST_LEG - 0.5)

    def test_every_state_fixture_is_clean(self):
        for lifecycle in state_fixtures():
            self.assert_clean_states(lifecycle)

    def test_ends_on_a_side_are_apart(self):
        for lifecycle in state_fixtures():
            root = ET.fromstring(cds.svg_states(lifecycle, "s"))
            boxes = {e.get("data-id"): tuple(float(e.get(k)) for k in ("x", "y", "width", "height"))
                     for e in root.iter() if e.get("data-id") is not None}
            along = collections.defaultdict(list)
            for element in (e for e in root.iter() if e.get("class") == "edge"):
                points = path_samples(element.get("d"))
                for end in (points[0], points[-1]):
                    for name, box in boxes.items():
                        side = box_side(end, box)
                        if side:
                            along[(name, side)].append(end[1] if side in ("left", "right") else end[0])
            for (name, side), places in along.items():
                places.sort()
                gaps = [b - a for a, b in zip(places, places[1:])]
                self.assertTrue(all(g >= cds.END_GAP - 0.5 for g in gaps),
                                "%s: ends on the %s side of %s are %s apart" % (lifecycle["id"], side, name, gaps))

    def test_missing_initial_has_no_start_dot(self):
        without = {k: v for k, v in FORWARD_ONLY.items() if k != "initial"}
        unknown = dict(FORWARD_ONLY, initial="nowhere")
        for lifecycle in (without, unknown):
            _, _, paths, _ = self.assert_clean_states(lifecycle)
            self.assertNotIn('class="start"', cds.svg_states(lifecycle, "s"))
            self.assertTrue(all(n is not None for n, _, _ in paths))

    def test_media_ladder_routes(self):
        lifecycle = MEDIA["states"][0]
        _, boxes, paths, _ = self.assert_clean_states(lifecycle)
        route = {owner + (n,): points for n, owner, points in paths}
        column_1 = boxes["success"]
        self.assertTrue(boxes["failed"][0] == boxes["earning_toozle"][0] == column_1[0])
        pending_right = boxes["pending"][0] + boxes["pending"][2]
        for (source, target, _), points in route.items():
            if "pending" in (source, target) and source != target and source is not None:
                self.assertTrue(all(pending_right <= x <= column_1[0] for x, _ in points), "%s->%s" % (source, target))
        verticals = {key: points for key, points in route.items()
                     if key[0] in ("failed", "earning_toozle") and key[1] in ("failed", "earning_toozle")}
        self.assertEqual(len(verticals), 3)
        self.assertEqual({len({round(x, 2) for x, _ in points}) for points in verticals.values()}, {1})
        down_x = [points[0][0] for key, points in verticals.items() if key[0] == "failed"]
        up_x = [points[0][0] for key, points in verticals.items() if key[0] == "earning_toozle"]
        self.assertLess(max(down_x), min(up_x), "down arrows sit left of up arrows")
        leg = [points for key, points in route.items() if key[:2] == ("earning_toozle", "success")][0]
        beside = [x for x, y in leg if abs(y - leg[0][1]) > 1 and abs(y - leg[-1][1]) > 1]
        self.assertGreater(min(beside), column_1[0] + column_1[2], "a leg runs right of its column")

    def test_states_other_lifecycles_are_clean(self):
        self.assert_clean_states(DIAGRAMS["states"][0])
        lifecycle = item_status_with_more_arrows()
        self.assert_clean_states(lifecycle)
        lifecycle["transitions"].append({"from": "queued", "to": "queued", "label": "heartbeat"})
        _, boxes, paths, _ = self.assert_clean_states(lifecycle)
        _, top, _, height = boxes["queued"]
        loops = [points for _, owner, points in paths if owner == ("queued", "queued")]
        self.assertEqual(len(loops), 2)
        self.assertLess(min(y for _, y in loops[0]), top)
        self.assertGreater(max(y for _, y in loops[1]), top + height)

    def test_far_back_arrow_keeps_a_lane_under_the_boxes(self):
        lifecycle = item_status_with_more_arrows()
        _, boxes, paths, markers = self.assert_clean_states(lifecycle)
        floor = max(y + h for _, y, _, h in boxes.values())
        number, _, points = [p for p in paths if p[1] == ("done", "new")][0]
        depth = max(y for _, y in points)
        self.assertGreater(depth, floor)
        lane = [x for x, y in points if abs(y - depth) < 0.01]
        self.assertAlmostEqual(markers[number][1], depth)
        self.assertAlmostEqual(markers[number][0], (min(lane) + max(lane)) / 2, delta=1)


if __name__ == "__main__":
    unittest.main()

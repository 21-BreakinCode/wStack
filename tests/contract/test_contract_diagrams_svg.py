"""Unit tests for scripts/contract_diagrams_svg.py: python3 tests/contract/test_contract_diagrams_svg.py"""
import copy
import hashlib
import json
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
NASTY = '<b>&"x"'
NASTY_ESCAPED = "&lt;b&gt;&amp;&quot;x&quot;"

SVG_ARCHITECTURE_SHA256 = "eca422da610b5ab5aa012fd65f8edb19fbd394aa0748f5084b8294e0548fe0b7"


def setUpModule():
    out = subprocess.check_output(
        ["yq", "-o=json", str(ROOT / "tests/fixtures/contract/diagrams-block.yaml")])
    DIAGRAMS.update(json.loads(out)["diagrams"])


def drawings():
    return [cds.svg_flow(DIAGRAMS["flow"], "flow"),
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


def label_rects(text):
    """Edge labels as (text, (x, y, w, h)), with the width the module estimates for 13px text."""
    out = []
    for element in ET.fromstring(text).iter():
        if element.get("class") == "lbl":
            width, x = cds.text_width(element.text), float(element.get("x"))
            left = {"start": x, "middle": x - width / 2, "end": x - width}[element.get("text-anchor")]
            out.append((element.text, (left, float(element.get("y")) - 12, width, 16)))
    return out


def strictly_inside(point, rect, margin=0.5):
    x, y, w, h = rect
    return x + margin < point[0] < x + w - margin and y + margin < point[1] < y + h - margin


def rects_overlap(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


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
        """Each transition has one path and one label. No path crosses a box other than its ends.
        No label touches another label, a box, or a path other than its own. All of it is inside the view box."""
        text = cds.svg_states(lifecycle, "s")
        root = ET.fromstring(text)
        _, _, view_w, view_h = (float(v) for v in root.get("viewBox").split())
        boxes = {e.get("data-id"): tuple(float(e.get(k)) for k in ("x", "y", "width", "height"))
                 for e in root.iter() if e.get("data-id") is not None}
        paths = [((e.get("data-from"), e.get("data-to")), path_samples(e.get("d")))
                 for e in root.iter() if e.tag.endswith("path") and e.get("class") == "edge"]
        pairs = [(t["from"], t["to"]) for t in lifecycle["transitions"]]
        self.assertEqual(sorted(owner for owner, _ in paths if owner[0] is not None), sorted(pairs))
        labels = label_rects(text)
        owner_of = {t["label"]: (t["from"], t["to"]) for t in lifecycle["transitions"] if t.get("label")}
        self.assertEqual(sorted(name for name, _ in labels), sorted(owner_of))
        in_view = lambda x, y: 0 <= x <= view_w and 0 <= y <= view_h
        for owner, points in paths:
            self.assertTrue(all(in_view(*p) for p in points), "%s->%s leaves the view box" % owner)
            for name, box in boxes.items():
                if name not in owner:
                    self.assertFalse(any(strictly_inside(p, box) for p in points),
                                     "%s->%s crosses %s" % (owner + (name,)))
        for index, (name, rect) in enumerate(labels):
            self.assertTrue(in_view(rect[0], rect[1]) and in_view(rect[0] + rect[2], rect[1] + rect[3]),
                            "label %r leaves the view box" % name)
            for other, other_rect in labels[index + 1:]:
                self.assertFalse(rects_overlap(rect, other_rect), "label %r overlaps label %r" % (name, other))
            for box_name, box in boxes.items():
                self.assertFalse(rects_overlap(rect, box), "label %r overlaps box %s" % (name, box_name))
            # A label sits 6px above its own line. Skip that line, and keep the rest of its own path 2px away.
            own_line_y, grown = rect[1] + rect[3] + 2, (rect[0] - 2, rect[1] - 2, rect[2] + 4, rect[3] + 4)
            for owner, points in paths:
                if owner != owner_of[name]:
                    self.assertFalse(any(strictly_inside(p, rect) for p in points),
                                     "label %r crosses the path %s->%s" % ((name,) + owner))
                else:
                    rest = [p for p in points if abs(p[1] - own_line_y) > 0.01]
                    self.assertFalse(any(strictly_inside(p, grown) for p in rest),
                                     "label %r crosses its own path" % name)
        return text, boxes, paths, labels


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
        for label in ("API", "Worker", "web-ui", "batch-job", "postgres", "other-svc", "GET /items", "items.created"):
            self.assertIn(">%s<" % label, flow)
        for label in ("web-ui", "api", "worker", "postgres", "validate the body"):
            self.assertIn(">%s<" % label, sequence)
        for label in ("new", "queued", "done", "failed", "a retry"):
            self.assertIn(">%s<" % label, states)
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
        for text in (cds.svg_flow(flow, "flow"), cds.svg_sequence(sequence, "s"),
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

    def test_text_width_counts_wide_characters_twice(self):
        self.assertEqual(cds.text_width("ab"), 2 * cds.COLUMN_PX)
        self.assertEqual(cds.text_width("漢字"), 4 * cds.COLUMN_PX)
        self.assertEqual(cds.text_width("a漢"), 3 * cds.COLUMN_PX)

    def test_long_label_widens(self):
        flow = copy.deepcopy(DIAGRAMS["flow"])
        flow["parts"][0]["label"] = "x" * 40
        self.assertGreater(view_width(cds.svg_flow(flow, "flow")), view_width(cds.svg_flow(DIAGRAMS["flow"], "flow")))

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
    def test_flow_edges_touch_their_boxes(self):
        flow = DIAGRAMS["flow"]
        text = cds.svg_flow(flow, "flow")
        boxes, edges = self.assert_edges_touch(text, [(e["from"], e["to"]) for e in flow["edges"]])
        service = rects_of_class(text, "svc")[0]
        inner = [e for e in edges if (e[0], e[1]) == ("api", "worker")][0]
        for point in inner[4]:
            self.assertTrue(on_border(point, service) or (
                service[0] < point[0] < service[0] + service[2] and service[1] < point[1] < service[1] + service[3]))
        self.assertLess(boxes["web-ui"][0][0], service[0])
        self.assertGreater(boxes["postgres"][0][0], service[0] + service[2])
        outer = [e for e in edges if "api" != e[0] or "worker" != e[1]]
        self.assertTrue(all(e[2][1] == e[3][1] for e in outer))

    def test_flow_reverse_self_and_skip_edges(self):
        flow = copy.deepcopy(DIAGRAMS["flow"])
        flow["parts"].append({"id": "cache", "label": "Cache", "refs": ["cmd/main.go:1"]})
        flow["edges"] += [{"from": "api", "to": "web-ui", "label": "callback"},
                          {"from": "worker", "to": "worker", "label": "retry"},
                          {"from": "api", "to": "cache"},
                          {"from": "cache", "to": "postgres", "label": "warm"}]
        text = cds.svg_flow(flow, "flow")
        boxes, edges = self.assert_edges_touch(text, [(e["from"], e["to"]) for e in flow["edges"]])
        self.assertEqual(len(boxes["web-ui"]), 1)
        self.assertGreater(boxes["web-ui"][0][3], boxes["batch-job"][0][3])
        outer = [e for e in edges if "web-ui" in e[:2] or "postgres" in e[:2]]
        self.assertTrue(all(e[2][1] == e[3][1] for e in outer))

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

    def test_states_edges_touch_their_boxes(self):
        lifecycle = DIAGRAMS["states"][0]
        boxes, edges = self.assert_edges_touch(cds.svg_states(lifecycle, "states-item-status"),
                                               [(t["from"], t["to"]) for t in lifecycle["transitions"]])
        columns = [boxes[name][0][0] for name in ("new", "queued", "done")]
        self.assertEqual(columns, sorted(columns))
        self.assertEqual(boxes["done"][0][0], boxes["failed"][0][0])
        back = [e for e in edges if (e[0], e[1]) == ("failed", "queued")][0]
        lowest_box = max(b[0][1] + b[0][3] for b in boxes.values())
        self.assertGreater(max(p[1] for p in back[4]), lowest_box)

    def test_states_self_same_column_and_back_edges(self):
        lifecycle = copy.deepcopy(DIAGRAMS["states"][0])
        lifecycle["transitions"] += [{"from": "queued", "to": "queued", "label": "wait"},
                                     {"from": "failed", "to": "done", "label": "manual fix"},
                                     {"from": "new", "to": "failed", "label": "fast fail"},
                                     {"from": "done", "to": "new", "label": "reopen"}]
        boxes, edges = self.assert_edges_touch(cds.svg_states(lifecycle, "s"),
                                               [(t["from"], t["to"]) for t in lifecycle["transitions"]])
        self.assert_no_box_crossing(boxes, edges)

    def test_states_many_back_routes_stay_in_their_gaps(self):
        back = [("d", "a"), ("d", "a"), ("c", "d"), ("d", "c"), ("d", "b"), ("c", "b"), ("c", "b"), ("c", "b")]
        lifecycle = {"initial": "a", "transitions": [{"from": "a", "to": "b"}, {"from": "b", "to": "c"},
                                                     {"from": "b", "to": "d"}]
                     + [{"from": s, "to": t} for s, t in back]}
        boxes, edges = self.assert_edges_touch(cds.svg_states(lifecycle, "s"),
                                               [(t["from"], t["to"]) for t in lifecycle["transitions"]])
        self.assert_no_box_crossing(boxes, edges)

    def test_states_task_lifecycle_is_clean(self):
        text, _, _, _ = self.assert_clean_states(TASK_STATUS)
        self.assert_edges_touch(text, [(t["from"], t["to"]) for t in TASK_STATUS["transitions"]])

    def test_states_other_lifecycles_are_clean(self):
        lifecycle = copy.deepcopy(DIAGRAMS["states"][0])
        self.assert_clean_states(lifecycle)
        lifecycle["transitions"] += [{"from": "queued", "to": "queued", "label": "wait"},
                                     {"from": "failed", "to": "done", "label": "manual fix"},
                                     {"from": "new", "to": "failed", "label": "fast fail"},
                                     {"from": "done", "to": "new", "label": "reopen"}]
        self.assert_clean_states(lifecycle)
        lifecycle["transitions"].append({"from": "queued", "to": "queued", "label": "heartbeat"})
        _, boxes, paths, _ = self.assert_clean_states(lifecycle)
        floor = max(y + h for _, y, _, h in boxes.values())
        loop_depths = sorted(max(y for _, y in points) for owner, points in paths if owner == ("queued", "queued"))
        self.assertEqual(len(loop_depths), 2)
        self.assertTrue(loop_depths[0] <= boxes["queued"][1] < floor < loop_depths[1])

    def test_states_back_and_same_column_arrows_get_own_lanes(self):
        _, boxes, paths, labels = self.assert_clean_states(TASK_STATUS)
        floor = max(y + h for _, y, _, h in boxes.values())
        column_of = {name: box[0] for name, box in boxes.items()}
        below = [t for t in TASK_STATUS["transitions"] if column_of[t["to"]] <= column_of[t["from"]]]
        self.assertEqual(len(below), 5)
        lowest = {}
        for t in below:
            points = [points for owner, points in paths if owner == (t["from"], t["to"])][0]
            depth = max(y for _, y in points)
            self.assertGreater(depth, floor, "%s->%s stays above the boxes" % (t["from"], t["to"]))
            bottom = [x for x, y in points if abs(y - depth) < 0.01]
            label = [rect for name, rect in labels if name == t["label"]][0]
            self.assertTrue(min(bottom) <= label[0] and label[0] + label[2] <= max(bottom),
                            "the label of %s->%s is off its lowest segment" % (t["from"], t["to"]))
            self.assertTrue(0 < depth - (label[1] + label[3]) <= 4,
                            "the label of %s->%s does not sit on its lowest segment" % (t["from"], t["to"]))
            lowest[(t["from"], t["to"])] = depth
        self.assertEqual(len(set(lowest.values())), len(below))

    def test_architecture_nests_and_joins_pills(self):
        architecture = DIAGRAMS["architecture"]
        text = cds.svg_architecture(architecture, "architecture")
        self.assert_edges_touch(text, [("sql-store", "store-port")])
        layers = rects_of_class(text, "layer")
        self.assertEqual(len(layers), 3)
        for outer, inner in zip(layers, layers[1:]):
            self.assertTrue(outer[0] < inner[0] and outer[1] < inner[1])
            self.assertTrue(inner[0] + inner[2] < outer[0] + outer[2] and inner[1] + inner[3] < outer[1] + outer[3])

    def test_architecture_without_siblings_is_unchanged(self):
        text = cds.svg_architecture(DIAGRAMS["architecture"], "architecture")
        self.assertEqual(hashlib.sha256(text.encode()).hexdigest(), SVG_ARCHITECTURE_SHA256)

    def test_architecture_sibling_sits_right_of_the_nested_group(self):
        architecture = copy.deepcopy(DIAGRAMS["architecture"])
        architecture["layers"].insert(1, {"name": "workers", "sibling": True, "components": [
            {"id": "job-runner", "label": "Job runner", "kind": "other"}]})
        architecture["implements"].append({"adapter": "job-runner", "port": "store-port"})
        text = cds.svg_architecture(architecture, "architecture")
        ET.fromstring(text)
        layers = rects_of_class(text, "layer")
        self.assertEqual(len(layers), 4)
        group, sibling = layers[0], layers[3]
        self.assertGreater(sibling[0], group[0] + group[2])
        self.assertEqual(sibling[1], group[1])
        self.assert_edges_touch(text, [("sql-store", "store-port"), ("job-runner", "store-port")])

    def test_architecture_all_siblings_sit_side_by_side(self):
        architecture = {"layers": [{"name": "alpha", "sibling": True, "components": [{"id": "a", "label": "A"}]},
                                   {"name": "beta", "sibling": True, "components": []}]}
        first, second = rects_of_class(cds.svg_architecture(architecture, "x"), "layer")
        self.assertGreater(second[0], first[0] + first[2])
        self.assertEqual(second[1], first[1])

    def pills_of(self, names):
        return {n: {"id": n, "label": n, "kind": "other", "refs": ["a.go:1"]} for n in names}

    def wide_architecture(self):
        pill = lambda name: {"id": name, "label": "Wide use case " + name, "kind": "use_case"}
        return {"layers": [
            {"name": "adapters", "components": [{"id": "http-in", "label": "HTTP in", "kind": "adapter"}]},
            {"name": "workers", "sibling": True, "components": [
                {"id": "job", "label": "Job", "kind": "adapter"}, {"id": "cron", "label": "Cron", "kind": "adapter"}]},
            {"name": "application", "components": [pill(n) for n in ("uc-one", "uc-two", "uc-three", "uc-four")]},
            {"name": "domain", "components": [{"id": "repo-port", "label": "Repo port", "kind": "port"},
                                              {"id": "mail-port", "label": "Mail port", "kind": "port"}]}],
            "implements": [{"adapter": "job", "port": "repo-port"}, {"adapter": "cron", "port": "mail-port"},
                           {"adapter": "http-in", "port": "mail-port"}, {"adapter": "repo-port", "port": "http-in"}]}

    def test_sibling_and_nested_implements_cross_no_other_pill(self):
        with_siblings = self.wide_architecture()
        without_siblings = copy.deepcopy(with_siblings)
        without_siblings["layers"].pop(1)
        without_siblings["implements"] = without_siblings["implements"][2:]
        for architecture in (with_siblings, without_siblings):
            self.assert_implements_cross_no_other_pill(architecture)

    def many_lanes_architecture(self, count):
        workers, ports = ["w%d" % k for k in range(count)], ["port-a", "port-b", "port-c"]
        return {"layers": [
            {"name": "adapters", "components": [{"id": "http-in", "label": "HTTP in", "kind": "adapter"}]},
            {"name": "workers", "sibling": True, "components": [{"id": w, "label": w.upper()} for w in workers]},
            {"name": "ports", "components": [{"id": p, "label": p, "kind": "port"} for p in ports]},
            {"name": "domain", "components": [{"id": n, "label": "Wide domain entity " + n}
                                              for n in ("one", "two", "three", "four")]}],
            "implements": [{"adapter": w, "port": ports[k % 3]} for k, w in enumerate(workers)]}

    def test_many_crossing_implements_get_own_bands(self):
        for count in (6, 12):
            architecture = self.many_lanes_architecture(count)
            self.assert_implements_cross_no_other_pill(architecture)
            _, edges = shapes(cds.svg_architecture(architecture, "a"))
            bands = [y0 for _, _, _, _, points in edges for (_, y0), (_, y1) in zip(points, points[1:]) if y0 == y1]
            self.assertEqual(len(bands), 2 * count)
            self.assertEqual(len(bands), len(set(bands)), "%d crossing edges share a band" % count)

    def assert_implements_cross_no_other_pill(self, architecture):
        text = cds.svg_architecture(architecture, "architecture")
        boxes, edges = self.assert_edges_touch(text, [(p["adapter"], p["port"]) for p in architecture["implements"]])
        for source, target, _, _, points in edges:
            for name, ((bx, by, bw, bh),) in boxes.items():
                if name in (source, target):
                    continue
                for (x0, y0), (x1, y1) in zip(points, points[1:]):
                    crosses = (min(x0, x1) < bx + bw - 0.5 and max(x0, x1) > bx + 0.5
                               and min(y0, y1) < by + bh - 0.5 and max(y0, y1) > by + 0.5)
                    self.assertFalse(crosses, "%s->%s crosses %s" % (source, target, name))
            lanes = {round(y, 1) for _, y in points[1:-1]}
            self.assertGreater(len(lanes), 1)

    def test_sibling_only_block_with_implements_stays_inside_view_box(self):
        architecture = {"layers": [
            {"name": "alpha", "sibling": True, "components": [{"id": "a", "label": "A", "kind": "adapter"}]},
            {"name": "beta", "sibling": True, "components": [{"id": "b", "label": "B", "kind": "port"}]}],
            "implements": [{"adapter": "a", "port": "b"}]}
        text = cds.svg_architecture(architecture, "architecture")
        boxes, _ = self.assert_edges_touch(text, [("a", "b")])
        width = view_width(text)
        for rect in rects_of_class(text, "layer"):
            self.assertLessEqual(rect[0] + rect[2], width)


if __name__ == "__main__":
    unittest.main()

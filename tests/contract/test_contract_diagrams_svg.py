"""Unit tests for scripts/contract_diagrams_svg.py: python3 tests/contract/test_contract_diagrams_svg.py"""
import copy
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

    def test_architecture_nests_and_joins_pills(self):
        architecture = DIAGRAMS["architecture"]
        text = cds.svg_architecture(architecture, "architecture")
        self.assert_edges_touch(text, [("sql-store", "store-port")])
        layers = rects_of_class(text, "layer")
        self.assertEqual(len(layers), 3)
        for outer, inner in zip(layers, layers[1:]):
            self.assertTrue(outer[0] < inner[0] and outer[1] < inner[1])
            self.assertTrue(inner[0] + inner[2] < outer[0] + outer[2] and inner[1] + inner[3] < outer[1] + outer[3])


if __name__ == "__main__":
    unittest.main()

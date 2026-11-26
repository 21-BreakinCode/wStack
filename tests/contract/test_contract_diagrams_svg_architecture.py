"""Unit tests for the architecture picture of scripts/contract_diagrams_svg.py:
python3 tests/contract/test_contract_diagrams_svg_architecture.py"""
import copy
import hashlib
import unittest
import xml.etree.ElementTree as ET

from test_contract_diagrams_svg import (  # noqa: F401 (setUpModule loads the fixtures)
    DIAGRAMS, MEDIA, Base, cds, rects_of_class, segments_meet, setUpModule, shapes, view_width)

SVG_ARCHITECTURE_SHA256 = "eca422da610b5ab5aa012fd65f8edb19fbd394aa0748f5084b8294e0548fe0b7"

TWO_LANES_FROM_ONE_PILL = {"layers": [
    {"name": "ports", "components": [{"id": "pa", "label": "Port A"}, {"id": "pb", "label": "Port B"}]},
    {"name": "mid", "components": [{"id": "m", "label": "Middle"}]},
    {"name": "adapters", "components": [{"id": "ad", "label": "Adapter"}]}],
    "implements": [{"adapter": "ad", "port": "pa"}, {"adapter": "ad", "port": "pb"}]}


class Architecture(Base):
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

    def test_lanes_from_sibling_pills_to_outer_pills_cross_no_other_pill(self):
        for count in (1, 2, 3, 4, 6):  # both ends of each lane sit in the top pill row
            architecture = {"layers": [
                {"name": "outer", "components": [{"id": "o%d" % k, "label": "Outer %d" % k} for k in range(count)]},
                {"name": "inner", "components": [{"id": "i0", "label": "Inner"}]},
                {"name": "jobs", "sibling": True, "components": [{"id": "j%d" % k, "label": "Job %d" % k}
                                                                 for k in range(count)]}],
                "implements": [{"adapter": "j%d" % k, "port": "o%d" % k} for k in range(count)]}
            self.assert_implements_cross_no_other_pill(architecture)
            text = cds.svg_architecture(architecture, "a")
            _, jobs_top, _, jobs_height = rects_of_class(text, "layer")[-1]
            lowest = max(y for _, _, _, _, points in shapes(text)[1] for _, y in points)
            self.assertLessEqual(lowest + 4, jobs_top + jobs_height, "%d lanes run below the sibling box" % count)

    def test_media_architecture_fits(self):
        text = cds.svg_architecture(MEDIA["architecture"], "architecture")
        self.assertLessEqual(view_width(text), cds.PAGE_LIMIT)
        layers = rects_of_class(text, "layer")
        group, workers = layers[0], layers[-1]
        self.assertGreaterEqual(workers[1], group[1] + group[3])
        self.assertEqual(workers[0], group[0])

    def test_wide_layer_wraps_pills(self):
        architecture = {"layers": [{"name": "wide", "components": [
            {"id": "p%02d" % k, "label": "twelve chars"} for k in range(14)]}]}
        text = cds.svg_architecture(architecture, "x")
        self.assertLessEqual(view_width(text), cds.PAGE_LIMIT)
        boxes, _ = shapes(text)
        self.assertEqual(len({round(rect[0][1]) for rect in boxes.values()}), 2)

    def test_lanes_are_eight_apart(self):
        architecture = self.many_lanes_architecture(6)
        _, edges = shapes(cds.svg_architecture(architecture, "a"))
        bands = sorted({y0 for _, _, _, _, points in edges for (_, y0), (_, y1) in zip(points, points[1:]) if y0 == y1})
        near = [b - a for a, b in zip(bands, bands[1:]) if b - a < 30]
        self.assertTrue(near)
        self.assertEqual(set(near), {cds.LANE_PITCH})

    def test_two_lanes_from_one_pill_leave_apart(self):
        _, edges = shapes(cds.svg_architecture(TWO_LANES_FROM_ONE_PILL, "a"))
        starts = sorted(points[0][0] for _, _, _, _, points in edges)
        self.assertEqual(len(starts), 2)
        self.assertAlmostEqual(starts[1] - starts[0], cds.LANE_PITCH)

    def test_deep_nested_wide_layer_fits(self):
        pills = [{"id": "p%02d" % k, "label": "8 chars!"} for k in range(14)]
        architecture = {"layers": [{"name": "outer", "components": []}, {"name": "middle", "components": []},
                                   {"name": "inner", "components": pills}]}
        self.assertLessEqual(view_width(cds.svg_architecture(architecture, "x")), cds.PAGE_LIMIT)

    def test_lanes_leaving_one_pill_do_not_cross(self):
        _, edges = shapes(cds.svg_architecture(TWO_LANES_FROM_ONE_PILL, "a"))
        first, second = [points for _, _, _, _, points in edges]
        # the first lane has the higher band, so it leaves right of the second lane
        self.assertGreater(first[0][0], second[0][0])
        for a, b in zip(first, first[1:]):
            for c, d in zip(second, second[1:]):
                self.assertFalse(segments_meet(a, b, c, d), "lanes cross at %s-%s and %s-%s" % (a, b, c, d))

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
            # a lane: down, along a band, through the gap, along a band, up; both bands are one band in one pill row
            self.assertEqual(len(points), 6, "%s->%s does not run in a lane" % (source, target))

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

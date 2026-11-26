"""Unit tests for the architecture picture of scripts/contract_diagrams_svg.py:
python3 tests/contract/test_contract_diagrams_svg_architecture.py"""
import copy
import hashlib
import itertools
import unittest
import xml.etree.ElementTree as ET

from test_contract_diagrams_svg import (  # noqa: F401 (setUpModule loads the fixtures)
    DIAGRAMS, MEDIA, Base, cds, rects_of_class, segments_meet, setUpModule, shapes, view_width)

SVG_ARCHITECTURE_SHA256 = "bef253d91c5a2f1e9d593e79e5af17423a2ad6d04b8213167dd01160481a2232"

TWO_LANES_FROM_ONE_PILL = {"layers": [
    {"name": "ports", "components": [{"id": "pa", "label": "Port A"}, {"id": "pb", "label": "Port B"}]},
    {"name": "mid", "components": [{"id": "m", "label": "Middle"}]},
    {"name": "adapters", "components": [{"id": "ad", "label": "Adapter"}]}],
    "implements": [{"adapter": "ad", "port": "pa"}, {"adapter": "ad", "port": "pb"}]}


def two_rows_apart(mirrored):
    """Adapters a1 and a2 in one row implement ports p1 and p2 two layers down. Mirrored: a1 -> p2 and a2 -> p1."""
    ports = ["p2", "p1"] if mirrored else ["p1", "p2"]
    return {"layers": [
        {"name": "outer", "components": [{"id": "a1", "label": "Adapter one"}, {"id": "a2", "label": "Adapter two"}]},
        {"name": "mid", "components": [{"id": "m", "label": "Middle"}]},
        {"name": "inner", "components": [{"id": "p1", "label": "Port one"}, {"id": "p2", "label": "Port two"}]}],
        "implements": [{"adapter": "a1", "port": ports[0]}, {"adapter": "a2", "port": ports[1]}]}


def sibling_row(count, mirrored):
    """A sibling beside one nested layer, all lane ends in one pill row. Job k implements core pill k, or pill
    count - 1 - k when mirrored."""
    return {"layers": [
        {"name": "core", "components": [{"id": "c%d" % k, "label": "C%d" % k} for k in range(count)]},
        {"name": "jobs", "sibling": True, "components": [{"id": "j%d" % k, "label": "J%d" % k} for k in range(count)]}],
        "implements": [{"adapter": "j%d" % k, "port": "c%d" % (count - 1 - k if mirrored else k)}
                       for k in range(count)]}


def sibling_to_outer(count):
    """Job k in a sibling implements pill k of the outer layer. No lane ends in the inner layer."""
    return {"layers": [
        {"name": "outer", "components": [{"id": "o%d" % k, "label": "Outer %d" % k} for k in range(count)]},
        {"name": "inner", "components": [{"id": "i0", "label": "Inner"}]},
        {"name": "jobs", "sibling": True, "components": [{"id": "j%d" % k, "label": "Job %d" % k}
                                                         for k in range(count)]}],
        "implements": [{"adapter": "j%d" % k, "port": "o%d" % k} for k in range(count)]}


def elbow_chain(heading, upward=False):
    """Pills p0..p5 in an outer layer and q0..q5 in the next layer, which sits 24 px right. Each pair heads one way
    and overlaps its neighbor pair, and their ends keep one order: p_k to q_(k + 1) right, or p_(k + 2) to q_k left.
    When upward, the q pill is the adapter."""
    pier = lambda prefix: [{"id": "%s%d" % (prefix, k), "label": "Pier"} for k in range(6)]
    pairs = ([("p%d" % k, "q%d" % (k + 1)) for k in range(5)] if heading == "right"
             else [("p%d" % (k + 2), "q%d" % k) for k in range(4)])
    return {"layers": [{"name": "outer", "components": pier("p")}, {"name": "inner", "components": pier("q")}],
            "implements": [{"adapter": q, "port": p} if upward else {"adapter": p, "port": q} for p, q in pairs]}


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
            architecture = sibling_to_outer(count)
            self.assert_implements_cross_no_other_pill(architecture)
            text = cds.svg_architecture(architecture, "a")
            _, jobs_top, _, jobs_height = rects_of_class(text, "layer")[-1]
            lowest = max(y for _, _, _, _, points in shapes(text)[1] for _, y in points)
            self.assertLessEqual(lowest + 4, jobs_top + jobs_height, "%d lanes run below the sibling box" % count)

    def test_innermost_box_grows_only_for_its_own_lanes(self):
        for count in (3, 6):
            outer, inner, _ = rects_of_class(cds.svg_architecture(sibling_to_outer(count), "a"), "layer")
            self.assertEqual(inner[3], inner[1] - outer[1], "%d lanes: the inner box is taller than one row" % count)

    def test_each_layer_box_holds_its_bands(self):
        for count in (3, 4, 6):
            architecture = sibling_row(count, mirrored=False)
            self.assert_implements_cross_no_other_pill(architecture)
            text = cds.svg_architecture(architecture, "a")
            boxes, edges = shapes(text)
            layers = rects_of_class(text, "layer")
            self.assertGreater(layers[1][0], layers[0][0] + layers[0][2], "the sibling sits beside")
            for source, target, _, _, points in edges:
                for name, band_y in ((source, points[1][1]), (target, points[4][1])):
                    (x, y, width, height), = boxes[name]
                    holder = min((r for r in layers if r[0] <= x and x + width <= r[0] + r[2]
                                  and r[1] <= y and y + height <= r[1] + r[3]), key=lambda r: r[3])
                    self.assertLessEqual(band_y + 4, holder[1] + holder[3],
                                         "%d lanes: the band under %s runs below its layer box" % (count, name))

    def assert_lane_crossings(self, architecture, most):
        """No two implements paths meet more than most times, for the implements list in either order."""
        for implements in (architecture["implements"], architecture["implements"][::-1]):
            _, edges = shapes(cds.svg_architecture(dict(architecture, implements=implements), "a"))
            for (s1, t1, _, _, p), (s2, t2, _, _, q) in itertools.combinations(edges, 2):
                count = sum(segments_meet(a, b, c, d) for a, b in zip(p, p[1:]) for c, d in zip(q, q[1:]))
                self.assertLessEqual(count, most, "%s->%s and %s->%s meet %d times" % (s1, t1, s2, t2, count))

    def test_lanes_nest_when_the_orders_mirror(self):
        # Both lane ends leave from a pill bottom, so lanes nest when the adapter order seen from below mirrors the
        # port order. The same order forces one crossing per pair.
        for mirrored, most in ((True, 0), (False, 1)):
            for architecture in [two_rows_apart(mirrored)] + [sibling_row(count, mirrored) for count in (2, 3, 6)]:
                self.assert_implements_cross_no_other_pill(architecture)
                self.assert_lane_crossings(architecture, most)

    def test_media_architecture_fits(self):
        text = cds.svg_architecture(MEDIA["architecture"], "architecture")
        self.assertLessEqual(view_width(text), cds.PAGE_LIMIT)
        layers = rects_of_class(text, "layer")
        group, workers = layers[0], layers[-1]
        self.assertGreaterEqual(workers[1], group[1] + group[3])
        self.assertEqual(workers[0], group[0])

    def test_pair_past_a_wrapped_pill_row_gets_a_lane(self):
        architecture = {"layers": [
            {"name": "wide", "components": [{"id": "w%02d" % k, "label": "Quillon gate"} for k in range(14)]},
            {"name": "next", "components": [{"id": "nib", "label": "Nib port"}]}],
            "implements": [{"adapter": "w00", "port": "nib"}]}
        boxes, _ = shapes(cds.svg_architecture(architecture, "a"))
        self.assertEqual(len({boxes["w%02d" % k][0][1] for k in range(14)}), 2, "the wide layer wraps onto two rows")
        self.assert_implements_cross_no_other_pill(architecture)

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

    def assert_elbows(self, architecture):
        """Every implements path runs only across and down: no segment slants, and no path crosses a pill. Returns
        the paths by (adapter, port)."""
        text = cds.svg_architecture(architecture, "a")
        boxes, edges = self.assert_edges_touch(text, [(p["adapter"], p["port"]) for p in architecture["implements"]])
        self.assert_no_box_crossing(boxes, edges)
        for source, target, _, _, points in edges:
            self.assertTrue(all(a[0] == b[0] or a[1] == b[1] for a, b in zip(points, points[1:])),
                            "%s->%s has a slanted segment: %s" % (source, target, points))
        return {(source, target): points for source, target, _, _, points in edges}

    def test_neighbor_layers_join_with_elbows(self):
        # Each adapter center of these pairs sits over its port, 13 px in from the port's rounded ends, so each pair
        # is one vertical line from the adapter's center. The elbow_chain fixtures hold the elbows.
        for architecture in (DIAGRAMS["architecture"], MEDIA["architecture"]):
            boxes, _ = shapes(cds.svg_architecture(architecture, "a"))
            for pair, points in self.assert_elbows(architecture).items():
                (x, _, width, _), = boxes[pair[0]]
                self.assertEqual([px for px, _ in points], [x + width / 2] * 2, "%s->%s: %s" % (pair + (points,)))

    def test_elbows_of_one_gap_nest_8_apart(self):
        for heading, upward in itertools.product(("right", "left"), (False, True)):
            architecture = elbow_chain(heading, upward)
            paths = self.assert_elbows(architecture)
            self.assert_lane_crossings(architecture, 0)
            bands = sorted(points[1][1] for points in paths.values())
            self.assertEqual(len(paths), len(architecture["implements"]))
            self.assertEqual({b - a for a, b in zip(bands, bands[1:])}, {cds.LANE_PITCH}, (heading, upward))

    def test_bands_keep_4_px_from_layer_borders(self):
        three_elbows = elbow_chain("right")
        three_elbows["implements"] = three_elbows["implements"][:3]
        fixtures = [elbow_chain(heading, upward) for heading, upward in itertools.product(("right", "left"), (0, 1))]
        fixtures += [three_elbows, sibling_to_outer(3), sibling_to_outer(4), self.many_lanes_architecture(6)]
        for number, architecture in enumerate(fixtures):
            text = cds.svg_architecture(architecture, "a")
            borders = [(x, x + width, y_border) for x, y, width, height in rects_of_class(text, "layer")
                       for y_border in (y, y + height)]
            for source, target, _, _, points in shapes(text)[1]:
                for (x0, y0), (x1, y1) in zip(points, points[1:]):
                    near = [y for left, right, y in borders
                            if y0 == y1 and min(x0, x1) < right and max(x0, x1) > left and abs(y0 - y) < 4]
                    self.assertFalse(near, "fixture %d: the band of %s->%s at y %s is near a layer border at %s"
                                     % (number, source, target, y0, near))

    def test_vertical_pair_stays_straight_and_one_row_pair_keeps_its_curve(self):
        architecture = {"layers": [
            {"name": "wide", "components": [{"id": "w%02d" % k, "label": "Quillon gate"} for k in range(14)]}],
            "implements": [{"adapter": "w00", "port": "w08"}, {"adapter": "w01", "port": "w10"},
                           {"adapter": "w02", "port": "w03"}]}
        text = cds.svg_architecture(architecture, "a")
        boxes, _ = shapes(text)
        self.assertEqual(boxes["w00"][0][0], boxes["w08"][0][0], "w08 starts the second row under w00")
        paths = {(e.get("data-from"), e.get("data-to")): e.get("d") for e in ET.fromstring(text).iter()
                 if e.get("data-from")}
        self.assertEqual(paths[("w00", "w08")].count("L"), 1, "a vertical pair is one straight line")
        self.assertIn("C", paths[("w02", "w03")], "a pair in one row keeps its curve")
        elbow = self.assert_elbows(dict(architecture, implements=architecture["implements"][:2]))[("w01", "w10")]
        self.assertEqual(len(elbow), 4)
        self.assertLessEqual(elbow[1][1] + 4, boxes["w10"][0][1], "the elbow runs 4 px above the next row")

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

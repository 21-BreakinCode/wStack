"""Unit tests for scripts/contract_diagrams.py: python3 tests/contract/test_contract_diagrams.py"""
import copy
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import contract_diagrams as cd  # noqa: E402

DIAGRAMS = {}


def setUpModule():
    out = subprocess.check_output(
        ["yq", "-o=json", str(ROOT / "tests/fixtures/contract/diagrams-block.yaml")])
    DIAGRAMS.update(json.loads(out)["diagrams"])


def first_bar_column(line):
    return cd.display_width(line[:line.index("│")])


class SubjectsAndHash(unittest.TestCase):
    def test_subjects_order(self):
        self.assertEqual(list(cd.subjects(DIAGRAMS)),
                         ["flow", "sequence:create", "states:item-status", "architecture"])

    def test_slug(self):
        self.assertEqual(cd.subject_slug("sequence:create"), "sequence-create")

    def test_hash_ignores_refs(self):
        flow = copy.deepcopy(DIAGRAMS["flow"])
        before = cd.shape_hash(flow)
        flow["edges"][0]["refs"] = ["other/file.go:9"]
        self.assertEqual(cd.shape_hash(flow), before)
        flow["edges"][0]["label"] = "changed"
        self.assertNotEqual(cd.shape_hash(flow), before)

    def test_hash_is_key_order_free(self):
        self.assertEqual(cd.shape_hash({"a": 1, "b": {"c": 2, "d": 3}}),
                         cd.shape_hash({"b": {"d": 3, "c": 2}, "a": 1}))


class Ascii(unittest.TestCase):
    def test_ascii_flow(self):
        text = cd.ascii_flow(DIAGRAMS["flow"])
        lines = text.split("\n")
        self.assertIn("┌", text)
        self.assertIn("└", text)
        self.assertTrue(any("web-ui" in l and "GET /items" in l and "▶" in l for l in lines))
        done = [l for l in lines if "items.done" in l][0]
        self.assertIn("◀", done)
        self.assertGreater(done.index("◀"), done.index("│"))
        inside = [l for l in lines if l.startswith("inside:")]
        self.assertEqual(len(inside), 1)
        self.assertIn("items.created", inside[0])
        columns = {first_bar_column(l) for l in lines if "│" in l}
        self.assertEqual(len(columns), 1)

    def test_ascii_flow_rows_sit_beside_their_part(self):
        lines = cd.ascii_flow(DIAGRAMS["flow"]).split("\n")
        worker_row = next(i for i, l in enumerate(lines) if "Worker" in l)
        self.assertLess(next(i for i, l in enumerate(lines) if "POST /items" in l), worker_row)
        self.assertLess(next(i for i, l in enumerate(lines) if "API" in l),
                        next(i for i, l in enumerate(lines) if "POST /items" in l))
        self.assertIn("Worker", [l for l in lines if "SQL" in l][0])
        self.assertGreater(next(i for i, l in enumerate(lines) if "items.done" in l), worker_row)
        self.assertFalse(any(re.search(r"▶ {2,}│", l) for l in lines))

    def test_ascii_flow_part_with_two_edges_grows(self):
        lines = cd.ascii_flow(DIAGRAMS["flow"]).split("\n")
        api_rows = [l for l in lines if "│" in l][:2]
        self.assertIn("GET /items", api_rows[0])
        self.assertIn("POST /items", api_rows[1])
        self.assertIn("API", api_rows[0])
        self.assertNotIn("API", api_rows[1])

    def test_ascii_flow_wide_label(self):
        flow = copy.deepcopy(DIAGRAMS["flow"])
        flow["parts"][0]["label"] = "圖片服務"
        lines = [l for l in cd.ascii_flow(flow).split("\n") if "│" in l]
        right = {cd.display_width(l[:l.rindex("│")]) for l in lines}
        self.assertEqual(len(right), 1)
        self.assertIn("圖片服務", "\n".join(lines))

    def test_ascii_flow_edge_without_label(self):
        flow = copy.deepcopy(DIAGRAMS["flow"])
        del flow["edges"][0]["label"]
        self.assertRegex(cd.ascii_flow(flow), r"web-ui ─+▶ │")

    def test_ascii_truncates(self):
        flow = copy.deepcopy(DIAGRAMS["flow"])
        flow["edges"][0]["label"] = "x" * 45
        text = cd.ascii_flow(flow)
        marked = [l for l in text.split("\n") if "…[1]" in l]
        self.assertTrue(marked)
        self.assertNotIn("x" * 32, marked[0])
        self.assertIn("x" * 27 + "…[1]", marked[0])
        self.assertIn("\n\nlabels:\n[1] " + "x" * 45, text)

    def test_ascii_footnote_numbers(self):
        flow = copy.deepcopy(DIAGRAMS["flow"])
        flow["edges"][0]["label"] = "a" * 40
        flow["edges"][1]["label"] = "b" * 40
        text = cd.ascii_flow(flow)
        self.assertIn("[1] " + "a" * 40 + "\n[2] " + "b" * 40, text)
        flow["edges"][1]["label"] = "a" * 40
        text = cd.ascii_flow(flow)
        self.assertIn("[1] " + "a" * 40, text)
        self.assertNotIn("[2]", text)

    def test_ascii_sequence_footnote(self):
        sequence = copy.deepcopy(DIAGRAMS["sequences"][0])
        sequence["steps"][0]["label"] = "s" * 50
        text = cd.ascii_sequence(sequence)
        self.assertIn("…[1]", text)
        self.assertTrue(text.endswith("labels:\n[1] " + "s" * 50))

    def test_ascii_short_labels_have_no_footnotes(self):
        self.assertNotIn("labels:", cd.ascii_flow(DIAGRAMS["flow"]))
        self.assertNotIn("labels:", cd.ascii_sequence(DIAGRAMS["sequences"][0]))

    def test_short_label_width_limits(self):
        exact = "圖" * 16
        self.assertEqual(cd.short(exact), exact)
        self.assertEqual(cd.short(exact, {}), exact)
        notes = {}
        cut = cd.short("圖" * 20, notes)
        self.assertEqual(cut, "圖" * 14 + "…[1]")
        self.assertEqual(cd.display_width(cut), 32)
        plain = cd.short("圖" * 20)
        self.assertEqual(plain, "圖" * 15 + "…")
        self.assertEqual(cd.display_width(plain), 31)

    def test_ascii_footnote_from_inside_edge(self):
        flow = copy.deepcopy(DIAGRAMS["flow"])
        flow["edges"][2]["label"] = "i" * 40
        text = cd.ascii_flow(flow)
        self.assertTrue(any(l.startswith("inside:") and "…[1]" in l for l in text.split("\n")))
        self.assertIn("[1] " + "i" * 40, text)

    def test_ascii_footnote_numbers_follow_edge_order(self):
        flow = copy.deepcopy(DIAGRAMS["flow"])
        for index, letter in ((0, "a"), (3, "b"), (4, "c")):
            flow["edges"][index]["label"] = letter * 40
        text = cd.ascii_flow(flow)
        self.assertIn("[1] " + "a" * 40 + "\n[2] " + "b" * 40 + "\n[3] " + "c" * 40, text)

    def test_ascii_flow_wide_node_name_is_cut(self):
        flow = copy.deepcopy(DIAGRAMS["flow"])
        flow["parts"][0]["label"] = "圖" * 20
        text = cd.ascii_flow(flow)
        lines = [l for l in text.split("\n") if "│" in l]
        self.assertIn("圖" * 15 + "…", text)
        self.assertNotIn("labels:", text)
        self.assertEqual(len({cd.display_width(l[:l.rindex("│")]) for l in lines}), 1)
        self.assertTrue(all(cd.display_width(l[l.index("│"):l.rindex("│") + 1]) <= cd.MAX_LABEL + 4 for l in lines))

    def test_ascii_sequence_self_step_footnote(self):
        sequence = copy.deepcopy(DIAGRAMS["sequences"][0])
        step = next(st for st in sequence["steps"] if st["from"] == st["to"])
        step["label"] = "z" * 50
        text = cd.ascii_sequence(sequence)
        self.assertTrue(any("┐" in l and "…[1]" in l for l in text.split("\n")))
        self.assertTrue(text.endswith("labels:\n[1] " + "z" * 50))

    def test_ascii_states_footnote(self):
        text = cd.ascii_states({"initial": "a", "transitions": [{"from": "a", "to": "b", "label": "k" * 45}]})
        self.assertIn("k" * 27 + "…[1]", text)
        self.assertTrue(text.endswith("labels:\n[1] " + "k" * 45))

    def test_ascii_sequence(self):
        lines = cd.ascii_sequence(DIAGRAMS["sequences"][0]).split("\n")
        header = lines[0]
        order = [header.index(n) for n in ("web-ui", "api", "worker", "postgres")]
        self.assertEqual(order, sorted(order))
        self.assertTrue(any("▶" in l and "POST /items" in l for l in lines))
        self.assertTrue(any("┐" in l and "validate the body" in l for l in lines))

    def test_ascii_sequence_right_to_left(self):
        lines = cd.ascii_sequence({"steps": [
            {"from": "a", "to": "b", "label": "go"}, {"from": "b", "to": "a", "label": "back"}]})
        self.assertTrue(any("◀" in l and "back" in l for l in lines.split("\n")))

    def test_ascii_states(self):
        lines = cd.ascii_states(DIAGRAMS["states"][0]).split("\n")
        self.assertEqual(lines[0], "initial: new")
        self.assertEqual(len(lines), 5)
        self.assertEqual(len({cd.display_width(l[:l.index("──▶")]) for l in lines[1:]}), 1)

    def test_ascii_states_without_label(self):
        text = cd.ascii_states({"initial": "a", "transitions": [{"from": "a", "to": "b"}]})
        self.assertIn("──▶ b", text)

    def test_ascii_architecture(self):
        text = cd.ascii_architecture(DIAGRAMS["architecture"])
        lines = text.split("\n")
        tops = [l for l in lines if "┌" in l]
        self.assertEqual(len(tops), 3)
        positions = [next(i for i, t in enumerate(tops) if n in t) for n in ("adapters", "use-cases", "entities")]
        self.assertEqual(positions, [0, 1, 2])
        self.assertTrue(lines[-1].startswith("ports:"))
        self.assertIn("Store port <- SQL store", lines[-1])

    def test_ascii_architecture_without_labels(self):
        arch = {"layers": [{"name": "l", "components": [{"id": "store-port"}, {"id": "sql-store"}]}],
                "implements": [{"adapter": "sql-store", "port": "store-port"}]}
        self.assertIn("store-port <- sql-store", cd.ascii_architecture(arch))


class DeepDives(unittest.TestCase):
    def test_read_deep_dives(self):
        def page(subject, digest):
            return ('<html><head><meta name="wstack-subject" content="%s">'
                    '<meta name="wstack-subject-hash" content="%s"></head></html>' % (subject, digest))
        present = cd.subjects(DIAGRAMS)
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "diagrams"
            target.mkdir()
            (target / "flow.html").write_text(page("flow", cd.shape_hash(present["flow"])))
            (target / "sequence-create.html").write_text(page("sequence:create", "0" * 64))
            (target / "states-gone.html").write_text(page("states:gone", "0" * 64))
            (target / "hand.html").write_text("<html><head></head></html>")
            (target / "notes.txt").write_text("x")
            result = cd.read_deep_dives(folder, DIAGRAMS)
        self.assertEqual([(d["name"], d["state"]) for d in result], [
            ("flow.html", "fresh"), ("hand.html", "not stamped"),
            ("sequence-create.html", "stale"), ("states-gone.html", "subject removed")])
        self.assertEqual(result[0]["subject"], "flow")
        self.assertIsNone(result[1]["subject"])

    def test_invalid_utf8_is_not_stamped(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "diagrams"
            target.mkdir()
            (target / "bad.html").write_bytes(b"\xff\xfe<html>")
            result = cd.read_deep_dives(folder, DIAGRAMS)
        self.assertEqual([d["state"] for d in result], ["not stamped"])

    def test_no_diagrams_folder(self):
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(cd.read_deep_dives(folder, DIAGRAMS), [])


class Note(unittest.TestCase):
    def test_note_lines_empty(self):
        self.assertEqual(cd.note_lines({}, []), [])


if __name__ == "__main__":
    unittest.main()

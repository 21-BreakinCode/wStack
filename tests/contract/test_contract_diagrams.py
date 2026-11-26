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
MEDIA = {}


def setUpModule():
    out = subprocess.check_output(
        ["yq", "-o=json", str(ROOT / "tests/fixtures/contract/diagrams-block.yaml")])
    DIAGRAMS.update(json.loads(out)["diagrams"])
    media = subprocess.check_output(
        ["yq", "-o=json", str(ROOT / "tests/fixtures/contract/media-shaped-diagrams.yaml")])
    MEDIA.update(json.loads(media)["diagrams"])


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


class Models(unittest.TestCase):
    def test_state_key_groups_by_source(self):
        key = cd.state_key(MEDIA["states"][0])
        self.assertEqual([(t["from"], t["to"]) for t in key], [
            ("pending", "success"), ("pending", "failed"), ("pending", "earning_toozle"),
            ("success", "failed"),
            ("failed", "success"), ("failed", "earning_toozle"), ("failed", "pending"),
            ("earning_toozle", "success"), ("earning_toozle", "failed"), ("earning_toozle", "failed")])

    def test_state_start_falls_back(self):
        lifecycle = {"initial": "nope", "transitions": [{"from": "a", "to": "b"}]}
        self.assertIsNone(cd.state_start(lifecycle))
        self.assertEqual(cd.state_order(lifecycle), ["a", "b"])

    def test_flow_overview_media(self):
        overview = cd.flow_overview(MEDIA["flow"])
        self.assertEqual(overview["callers"], 8)
        self.assertEqual(overview["dependencies"], 9)
        self.assertEqual(overview["caller_targets"], ["api"])
        self.assertEqual(overview["links"], [("api", "abuna-secesh")])
        self.assertEqual(overview["callbacks"],
                         [("ticky-let-2", "ticky-secesh"), ("abuna-let-2", "abuna-toozle-secesh")])

    def test_part_cards_keep_duplicate_pairs(self):
        api = cd.part_cards(MEDIA["flow"])[0]
        self.assertEqual(api["label"], "API (FastAPI)")
        self.assertEqual(len(api["called_by"]), 8)
        self.assertIn(("ticky-let-2", "mozzetta.angionoma (Pub/Sub)"), api["calls"])
        self.assertIn(("ticky-let-2", "POST /confide"), api["calls"])
        self.assertIn(("abuna secesh", "tray id on abuna-swish pursy"), api["calls"])

    def test_flow_without_callers_or_dependencies(self):
        flow = {"parts": [{"id": "p"}], "edges": []}
        self.assertEqual(cd.flow_overview(flow)["callers"], 0)
        self.assertEqual(cd.part_cards(flow), [{"id": "p", "label": "p", "called_by": [], "calls": []}])

    def test_sibling_false_hashes_like_missing(self):
        with_flag = {"layers": [{"name": "a", "sibling": False, "components": []}]}
        without = {"layers": [{"name": "a", "components": []}]}
        self.assertEqual(cd.shape_hash(with_flag), cd.shape_hash(without))
        self.assertNotEqual(cd.shape_hash({"layers": [{"name": "a", "sibling": True, "components": []}]}),
                            cd.shape_hash(without))

    def test_key_line_and_short_width(self):
        self.assertEqual(cd.key_line("a", "b", "go"), "a → b: go")
        self.assertEqual(cd.key_line("a", "b", ""), "a → b")
        self.assertEqual(cd.short("x" * 50, width=10), "x" * 9 + "…")


class ShortLabels(unittest.TestCase):
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

    def test_note_flow_overview_media(self):
        lines = cd.note_flow(MEDIA["flow"])
        self.assertEqual("\n".join(lines[:15]), """```text
8 callers
  ▼
┌ parts ───────────────────────────────┐
│ API (FastAPI) ◀ callers              │
│   ─▶ abuna secesh                    │
│ ticky secesh                         │
│   ◀─ ticky-let-2                     │
│ abuna secesh                         │
│ abuna toozle secesh                  │
│   ◀─ abuna-let-2                     │
└──────────────────────────────────────┘
  ▼
9 dependencies
```""")
        self.assertEqual(lines[15:19], ["", "**API (FastAPI)**", "", "- called by:"])
        self.assertIn("  - druse-dog-in: GET /outcrow, POST saker", lines)

    def test_note_states_media_head(self):
        lines = cd.note_states(MEDIA["states"][0])
        self.assertEqual("\n".join(lines[:11]), """Start: pending

**pending**

1. → success: ticky mozzetta.bisegment
2. → failed: reputed, secesh finally, or youse xylol
3. → earning_toozle: abuna-let-2 benzoxy the alloquy

**success**

4. → failed: helicorubin abuna indexer""")
        self.assertEqual(lines[-1], "10. → failed: helicorubin abuna indexer")

    def test_note_architecture_media(self):
        text = "\n".join(cd.note_architecture(MEDIA["architecture"]))
        self.assertTrue(text.startswith("""```text
ports (frameworks and drivers)
├─ FastAPI routes
├─ GCS, Pub/Sub, DB, HTTP clients
└─ adapters
   ├─ burred inspective
   ├─ tray inspective
   ├─ TrayLubricator
   ├─ LendeeLubricator
   └─ use cases
      ├─ TraySwaCape
      ├─ LendeeSwaCape
      ├─ TrayLubricatorPastoress
      ├─ LendeeLubricatorPastoress
      └─ entities
         ├─ Lendee and Kitish
         ├─ Tray and TrayGlady
         └─ eld decagram

workers (beside the nested layers)
└─ Pub/Sub workers
```

Implements:

- TrayLubricator ─▶ TrayLubricatorPastoress
"""))

    def test_note_code_blocks_fit_a_phone(self):
        for diagrams in (DIAGRAMS, MEDIA):
            in_block = False
            for line in cd.note_lines(diagrams, []):
                if line.startswith("```"):
                    in_block = not in_block
                elif in_block:
                    self.assertLessEqual(cd.display_width(line), cd.NOTE_COLUMNS, line)

    def test_wide_characters_fit_and_keep_footnotes(self):
        architecture = {"style": "clean", "layers": [{"name": "外層", "components": [
            {"id": "c", "label": "處理中的非常長的元件名稱一二三四五六七八九十", "refs": ["a:1"]}]}]}
        lines = "\n".join(cd.note_architecture(architecture))
        self.assertIn("…[1]", lines)
        drawn_rows = filter(lambda row: row[:2] != "- ", lines.split("\n"))
        self.assertTrue(all(cd.display_width(row) <= 40 for row in drawn_rows))

    def test_footnote_wraps_with_indent(self):
        notes = {}
        cd.short("word " * 20, notes)
        wrapped = cd.with_footnotes([], notes)[2:]
        self.assertTrue(wrapped[0].startswith("[1] word"))
        self.assertTrue(all(row.startswith("    ") for row in wrapped[1:]))
        self.assertTrue(all(cd.display_width(row) <= 40 for row in wrapped))

    def test_note_sequence_lines(self):
        lines = cd.note_sequence(MEDIA["sequences"][0])
        self.assertEqual(lines[0], "1. caller → api: POST /outcrow (ethonomic)")
        self.assertEqual(len(lines), 7)

    def test_note_flow_without_callers_or_dependencies(self):
        text = "\n".join(cd.note_flow({"parts": [{"id": "p", "refs": ["a:1"]}], "edges": []}))
        self.assertNotIn("caller", text)
        self.assertNotIn("dependenc", text)
        self.assertNotIn("called by", text)

    def test_note_list_collapses_newlines(self):
        sequence = {"steps": [{"from": "a", "to": "b", "label": "two\nlines"}]}
        self.assertEqual(cd.note_sequence(sequence), ["1. a → b: two lines"])

    def test_callers_marker_stays_on_a_cut_part_label(self):
        label = "a part label that is far too long for the box"
        flow = {"parts": [{"id": "p", "label": label}], "callers": [{"id": "ui"}], "edges": [{"from": "ui", "to": "p"}]}
        lines = cd.note_flow(flow)
        self.assertIn("│ %s │" % cd.pad(cd.short(label, {}, 26) + " ◀ callers", 36), lines)
        footnote = lines[lines.index("labels:") + 1:lines.index("```")]
        self.assertEqual(" ".join(" ".join(footnote).split()), "[1] " + label)

    def test_null_label_prints_no_none(self):
        self.assertEqual(cd.note_sequence({"steps": [{"from": "a", "to": "b", "label": None}]}), ["1. a → b"])
        lifecycle = {"initial": "a", "transitions": [{"from": "a", "to": "b", "label": None}]}
        self.assertIn("1. → b", cd.note_states(lifecycle))

    def test_note_lists_keep_angle_brackets(self):
        flow = {"parts": [{"id": "p", "label": "<p>"}], "callers": [{"id": "ui"}],
                "edges": [{"from": "ui", "to": "p", "label": "GET /items/<id>"}]}
        lines = cd.note_flow(flow)
        self.assertIn("│ <p> ◀ callers", "\n".join(lines))  # a code block keeps the text as it is
        self.assertIn("**&lt;p>**", lines)
        self.assertIn("  - ui: GET /items/&lt;id>", lines)
        sequence = {"steps": [{"from": "ui", "to": "api", "label": "GET /items/<id>"}]}
        self.assertEqual(cd.note_sequence(sequence), ["1. ui → api: GET /items/&lt;id>"])
        lifecycle = {"initial": "<a>", "transitions": [{"from": "<a>", "to": "<b>", "label": "on <event>"}]}
        self.assertEqual(cd.note_states(lifecycle),
                         ["Start: &lt;a>", "", "**&lt;a>**", "", "1. → &lt;b>: on &lt;event>"])
        architecture = {"layers": [{"name": "l", "components": [{"id": "a", "label": "<A>"}, {"id": "b"}]}],
                        "implements": [{"adapter": "a", "port": "b"}]}
        self.assertEqual(cd.note_architecture(architecture)[-1], "- &lt;A> ─▶ b")


if __name__ == "__main__":
    unittest.main()

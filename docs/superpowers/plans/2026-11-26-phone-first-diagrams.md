# Phone-first contract diagrams Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The vault note shows every contract diagram in 40 columns or less. The HTML page shows every diagram without sideways scroll on a laptop.

**Architecture:** `scripts/contract_diagrams.py` gets the shared models (state order and key, flow overview, part cards) and the new note views. `scripts/contract_diagrams_svg.py` gets the flow overview SVG with part cards, numbered sequence and states pictures with a key, and a wrapping architecture picture. `scripts/contract_render.py` gets the page CSS and the plural fix. A new script and some skill text close the tooling items.

**Tech Stack:** Python 3.9 standard library, Bash 3.2, yq 4.30.8 or later, unittest.

**Spec:** `docs/superpowers/specs/2026-11-26-phone-first-diagrams-design.md`

## Global Constraints

- Python scripts use only the standard library and run on Python 3.9. Bash scripts start with `#!/usr/bin/env bash` and `set -euo pipefail`, run on `/bin/bash` 3.2, and quote every path variable.
- Functions are under 50 lines. Files are under 800 lines. Use self-explaining names over comments.
- `NOTE_COLUMNS = 40`. No line inside a note code block is wider than 40 display columns (a wide character counts as 2).
- Every page SVG for `tests/fixtures/contract/media-shaped-diagrams.yaml` is at most 1100 px wide (`PAGE_LIMIT = 1100`).
- The page figure width is `min(1200px, calc(100vw - 32px))`, centered on the page.
- Number markers: radius 8 px (`MARKER_R = 8`). Arrow ends on one box side are at least 18 px apart (`END_GAP = 18`). A state side space is at least 16 px.
- Architecture implements lanes are 8 px apart (`LANE_PITCH = 8`).
- A key line is `<from> → <to>: <label>`, or `<from> → <to>` with no label.
- Layout changes never change `shape_hash`. The only hash change is that `sibling: false` hashes like a missing `sibling`.
- No Appier-internal names in code or tests. Tests never write into `$HOME/Projects/LifeOS/`.
- Docs and skill text follow simple English. The simple-english hook lints every `.md` write.
- Before each commit, run the unit tests of the task and then the full suite: `PATH="<bash32 shim dir>:$PATH" bash tests/run-all.sh`. The controller gives the shim path.
- End each commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A flow with parts but no callers or no dependencies: no `0 callers` line, no empty list headings, no crash. Tests in Tasks 1, 2 and 3.
2. Wide characters (for example `處理中`) in state names, part labels, and layer components: the 40-column limit still holds, and cut text keeps its `…[n]` footnote. Test in Task 2.
3. Two edges with the same pair (the fixture has `api → ticky-let-2` twice): both appear in the part cards and the note lists, each with its own label. Tests in Tasks 1 and 3.
4. A lifecycle whose `initial` is missing or names no state in the transitions: the key starts at the first state, and the picture has no start dot. Tests in Tasks 1 and 5.
5. Labels with HTML or Markdown specials (`<b>&"x"`, a newline): HTML-escaped in cards and keys, and collapsed to one line in note lists. Tests in Tasks 2 and 4.

---

### Task 1: Shared models and the sibling hash fix

**Files:**
- Modify: `scripts/contract_diagrams.py`
- Modify: `scripts/contract_diagrams_svg.py` (import `state_columns` instead of defining it)
- Create: `tests/fixtures/contract/media-shaped-diagrams.yaml` (the controller already wrote it, commit it in this task)
- Test: `tests/contract/test_contract_diagrams.py`

**Interfaces:**
- Produces, all in `contract_diagrams.py`:
  - `NOTE_COLUMNS = 40`
  - `short(text, notes=None, width=MAX_LABEL) -> str`: today's `short` with a width parameter. Callers that pass no width keep today's output.
  - `state_columns(transitions, start) -> dict` moved here unchanged from `contract_diagrams_svg.py`.
  - `state_start(lifecycle) -> str or None`: the value of `initial`, but None for an `initial` that names no state in the transitions.
  - `state_order(lifecycle) -> list[str]`: the states in column order, then in first-appearance order inside a column. Columns come from `state_columns(transitions, state_start(lifecycle) or first state)`.
  - `state_key(lifecycle) -> list[dict]`: the transitions grouped by source state in `state_order`, YAML order inside a group. A transition's number is its index + 1.
  - `flow_overview(flow) -> dict` with these keys:
    - `parts`: the part ids in YAML order.
    - `callers` and `dependencies`: the counts, as int.
    - `caller_targets`: the part ids that a caller edge reaches, in part order.
    - `links`: unique `(from_part, to_part)` pairs, in edge order.
    - `callbacks`: unique `(dependency_id, part_id)` pairs of edges from a dependency to a part, in edge order.
  - `part_cards(flow) -> list[dict]`, one per part in YAML order, with keys `id`, `label`, `called_by`, and `calls`. `called_by` holds `(name, label)` for each edge whose `to` is the part. `calls` holds `(name, label)` for each edge whose `from` is the part. `name` is the other end's label or id. `label` is the edge label or `""`. Edge order. Duplicate pairs give duplicate entries.
  - `shape_hash(value)`: drops a `sibling` key whose value is `false` before hashing, at any depth.
  - `key_line(source, target, label) -> str`: the key line form of the Global Constraints.

- [ ] **Step 1: Write the failing tests** in a new class `Models` that loads both fixtures:

```python
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
    self.assertEqual(overview["callbacks"], [("ticky-let-2", "ticky-secesh"), ("abuna-let-2", "abuna-toozle-secesh")])

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
```

`MEDIA` is the `diagrams` map of `media-shaped-diagrams.yaml`, loaded in `setUpModule` the same way as `DIAGRAMS`.

- [ ] **Step 2: Run** `python3 tests/contract/test_contract_diagrams.py`. Expected: the new tests fail with `AttributeError`.
- [ ] **Step 3: Implement** the interfaces above. Move `state_columns` and import it in `contract_diagrams_svg.py`. Add `sibling: false` dropping inside the function `shape_hash` uses to strip refs.
- [ ] **Step 4: Run** both unit test files, then the full suite. Expected: all pass.
- [ ] **Step 5: Commit** `feat: shared diagram models and sibling false hash`.

### Task 2: Phone-sized note views

**Files:**
- Modify: `scripts/contract_diagrams.py`
- Modify: `tests/contract/test_contract_diagrams.py`, `tests/test_contract_render.sh` (lines 129-131)

**Interfaces:**
- Consumes: Task 1 models and `short(..., width=)`.
- Produces: `note_flow(flow) -> list[str]`, `note_sequence(sequence) -> list[str]`, `note_states(lifecycle) -> list[str]`, `note_architecture(architecture) -> list[str]`. `note_lines` keeps its signature and headings, and calls these. Remove `ascii_flow`, `ascii_sequence`, `ascii_states`, `ascii_architecture`, and any helper they alone used, with their tests.

Exact formats. Every list text is collapsed to one line with `" ".join(text.split())`.

- `note_flow`: a `text` code block with the overview, then one block per part:

```text
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
```

  The box lines are exactly `NOTE_COLUMNS` wide. Write `1 caller` and `1 dependency` for one. With no callers, the first two lines are left out. With no dependencies, the last two lines are left out. A box line text that does not fit 36 columns is cut with `short(text, notes, 36)`. After the overview, each part gets these lines in order. First `**<label>**` and a blank line. Then `- called by:` with one `  - <name>: <label>` line per entry. Then `- calls:` the same way, and a blank line. Leave out an empty list and its heading line. An entry with no label is `  - <name>`.
- `note_sequence`: one line per step, `<n>. <from> → <to>: <label>`, using the key line form.
- `note_states`: when `state_start` is set, the view starts with `Start: <state>` and a blank line. Then each source state of `state_key` gets `**<state>**`, a blank line, its lines `<n>. → <to>: <label>`, and a blank line. The fixture gives exactly:

```text
Start: pending

**pending**

1. → success: ticky mozzetta.bisegment
2. → failed: reputed, secesh finally, or youse xylol
3. → earning_toozle: abuna-let-2 benzoxy the alloquy

**success**

4. → failed: helicorubin abuna indexer
```

  and so on to `10. → failed: helicorubin abuna indexer`.
- `note_architecture`: a `text` code block with one tree per nested group and per sibling layer, then `Implements:`, a blank line, and `- <adapter label> ─▶ <port label>` lines. The fixture gives exactly:

```text
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

  The nested group lists the non-sibling layers in YAML order, outermost first. Each level indents 3 columns. A component label that does not fit is cut with `short(text, notes, NOTE_COLUMNS - indent - 3)`.
- Footnotes: a code block with cut text ends with a blank line, `labels:`, and `[n] <full text>` lines. Wrap each footnote line at 40 columns, with continuation lines indented 4 spaces.

- [ ] **Step 1: Write the failing tests.** Golden tests for the three exact blocks above (`test_note_flow_overview_media`, `test_note_states_media_head`, `test_note_architecture_media`). Plus:

```python
def test_note_code_blocks_fit_a_phone(self):
    for diagrams in (DIAGRAMS, MEDIA):
        in_block = False
        for line in cd.note_lines(diagrams, []):
            if line.startswith("```"):
                in_block = not in_block
            elif in_block:
                for row in line.split("\n"):
                    self.assertLessEqual(cd.display_width(row), cd.NOTE_COLUMNS, row)

def test_wide_characters_fit_and_keep_footnotes(self):
    architecture = {"style": "clean", "layers": [{"name": "外層", "components": [
        {"id": "c", "label": "處理中的非常長的元件名稱一二三四五六七八九十", "refs": ["a:1"]}]}]}
    lines = "\n".join(cd.note_architecture(architecture))
    self.assertIn("…[1]", lines)
    drawn_rows = filter(lambda row: row[:2] != "- ", lines.split("\n"))
    self.assertTrue(all(cd.display_width(row) <= 40 for row in drawn_rows))

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
```

  In `tests/test_contract_render.sh`, the heading loop keeps the `text` block check for `Component flow` and `Architecture (clean)`. For `Sequence: Create an item`, check that the line 2 below the heading is `1. web-ui → api: POST /items`. For `States: Item status`, check that it is `Start: new`.
- [ ] **Step 2: Run** the unit tests and `bash tests/test_contract_render.sh`. Expected: the new checks fail.
- [ ] **Step 3: Implement** the four functions and the new `note_lines` body. Remove the old ASCII functions and their tests.
- [ ] **Step 4: Run** the unit tests, `bash tests/test_contract_render.sh`, then the full suite. Expected: all pass.
- [ ] **Step 5: Commit** `feat: phone-sized note views for contract diagrams`.

### Task 3: Flow overview SVG, part cards, and the page width

**Files:**
- Modify: `scripts/contract_diagrams_svg.py`, `scripts/contract_render.py` (CSS only)
- Modify: `tests/contract/test_contract_diagrams_svg.py`, `tests/test_contract_render.sh`

**Interfaces:**
- Consumes: `flow_overview`, `part_cards`.
- Produces: `svg_flow_overview(flow, prefix) -> str` and `flow_cards_html(flow) -> str`. `html_section` draws the flow figure as caption, overview SVG, then cards. Remove `svg_flow`, `outer_column`, `lane_width`, `other_end`, and their tests.

The overview SVG is top to bottom. These are the node `data-id` values:

- each part id and each callback dependency id
- `_callers` for the `N callers` box
- `_zone` for the zone rectangle (class `svc`)
- `_dependencies` for the `N dependencies` box
 Paths carry `data-from` and `data-to`: `_callers` to each caller target, each link, each callback, and one `_zone` to `_dependencies`. The overview has no arrow labels. The look inside these rules is the builder's call.

The cards are `<div class="cards">`, then one `<section class="card part-card">` per part: `<h4>label</h4>`, `<p class="muted">called by</p><ul>…</ul>`, `<p class="muted">calls</p><ul>…</ul>`. Each `<li>` is `name: label` (or `name`), escaped. Leave out an empty list and its `<p>`.

CSS in `contract_render.py`. Replace the `.diagram` rule with exactly `.diagram { overflow-x: auto; position: relative; left: 50%; transform: translateX(-50%); width: min(1200px, calc(100vw - 32px)); margin: 12px 0; }`. The existing render test still finds its prefix. Add `.cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 12px; }`.

- [ ] **Step 1: Write the failing tests:**
  - `test_flow_overview_edges_touch`: `assert_edges_touch` with the pairs `("_callers", "api")`, `("api", "abuna-secesh")`, `("ticky-let-2", "ticky-secesh")`, `("abuna-let-2", "abuna-toozle-secesh")`, and `("_zone", "_dependencies")`.
  - `test_flow_overview_texts`: `8 callers`, `9 dependencies`, and each part label are text nodes.
  - `test_flow_overview_fits`: `view_width ≤ 760` for MEDIA.
  - `test_flow_overview_without_callers`: no `_callers` node, no crash.
  - `test_cards_list_every_edge`: each `(name, label)` of every part card is one `<li>` in the right section and list.
  - `test_cards_escape`: a part label `<b>&"x"` shows only as `&lt;b&gt;&amp;&quot;x&quot;`.
  - In `test_contract_render.sh`: the page has `class="cards"` and the `minmax(320px, 1fr)` rule. "four SVG diagrams" stays true.
- [ ] **Step 2: Run** the tests. Expected: they fail.
- [ ] **Step 3: Implement** the two functions, the `html_section` change, and the CSS.
- [ ] **Step 4: Run** the unit tests, the render test, then the full suite. Expected: all pass.
- [ ] **Step 5: Commit** `feat: flow overview with part cards on the contract page`.

### Task 4: Numbered sequence pictures with a key

**Files:**
- Modify: `scripts/contract_diagrams_svg.py`, `scripts/contract_render.py` (CSS only)
- Modify: `tests/contract/test_contract_diagrams_svg.py`

**Interfaces:**
- Consumes: `key_line` from Task 1.
- Produces, used by Task 5:
  - `MARKER_R = 8`
  - `Canvas.path(d, cls="edge", source=None, target=None, arrow=True, number=None)`: with a number, the path also gets `data-n="<number>"`.
  - `Canvas.marker(x, y, number)`: appends `<circle class="mk" data-n="n" cx cy r="8"/>` and `<text class="mkt" x="x" y="y + 4" text-anchor="middle">n</text>` to the list that paints last, and grows the view box by `MARKER_R` around the center.
  - `html_key(lines) -> str`: `<ol class="key">` with one escaped `<li>` per line.
- `svg_sequence` draws no step label. Each step path gets `number=<step index + 1>`, and its marker sits on the middle of the arrow (beside the loop for a self-step). The space between two lifelines no longer grows for labels, only for names and markers. `html_section` adds the key under the sequence picture.
- CSS: `.diagram .mk { fill: var(--card); stroke: var(--link); stroke-width: 1.5; }`, `.diagram .mkt { font: 600 11px system-ui, sans-serif; fill: var(--link); }`, `.key { margin: 8px 0 0; padding-left: 28px; }`.

- [ ] **Step 1: Write the failing tests:**
  - `test_sequence_steps_are_numbered`: for each step n there is one path and one marker with `data-n="n"`. The marker center is within 1 px of the path, or within 40 px for a self-step.
  - `test_sequence_fits`: the 7-participant MEDIA sequence `ake-abuna-tray` has `view_width ≤ 900`.
  - `test_key_escapes`: `html_key(['<b>&"x"'])` contains `&lt;b&gt;&amp;&quot;x&quot;`.
  - Update `test_sequence_steps_join_lifelines` and `test_labels_present_and_escaped`. The sequence now has no `lbl` text.
- [ ] **Step 2: Run** the tests. Expected: they fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the unit tests, then the full suite. Expected: all pass.
- [ ] **Step 5: Commit** `feat: numbered sequence pictures with a key`.

### Task 5: The states ladder with numbered arrows

**Files:**
- Modify: `scripts/contract_diagrams_svg.py`
- Modify: `tests/contract/test_contract_diagrams_svg.py`

**Interfaces:**
- Consumes: `state_order`, `state_key`, `state_start`, `Canvas.path(number=)`, `Canvas.marker`, `html_key`, `key_line`.
- Produces: `svg_states(lifecycle, prefix) -> str` with the same signature. `html_section` adds the key under the states picture. The key lines and the arrow numbers come from `state_key`.

Layout rules, from the spec section "The states ladder layout". These are the decisions that the tests do not pin:

- Columns and the row order come from `state_order`. Boxes are `STATE_H = 32` px tall. When a side holds more ends than `END_GAP` allows, its box grows to `max(32, END_GAP * (ends + 1))`.
- The band between two columns is 56 px wide. It holds the forward arrows and the back arrows to the previous column, as cubic curves from end to end. A back arrow leaves the left side of its source and enters the right side of its target.
- The ends on one box side are ordered by the y of the far end, so arrows in one band do not cross. Ends are `END_GAP` apart.
- An arrow between neighbor rows of one column is a straight vertical line in the 44 px gap between the boxes. Down arrows sit left of up arrows, spread evenly across the box width. When its arrows are less than 18 px apart, the box widens.
- An arrow back by two or more columns keeps a lane under the boxes, `LANE = 24` px apart, as today.
- An arrow between two non-neighbor rows of one column runs as a leg right of the column. The first leg is 12 px out, and each next leg is 10 px further out.
- The first self-loop sits on the top edge, as today. A second self-loop sits on the bottom edge. A third or later self-loop becomes a leg right of the column.
- The start dot and the start arrow keep their slot at the middle of the start state's left side. No other end on that side is within `END_GAP / 2` of it.
- A side space is as wide as its legs need, with at least 16 px. The left space of the first column is at least 30 px for the start dot.
- Markers: a band arrow's marker is 14 px from its column-side end. A vertical arrow's marker is at the middle of the gap. A lane's or leg's marker is at the middle of its long segment. A loop's marker is just outside the loop.

The controller hands you the throwaway spike `spike_states.py`. It draws this layout for the media lifecycle, so read it for one way to do it. Do not copy its constants where this list differs.

- [ ] **Step 1: Write the failing tests.** Replace `assert_clean_states` with a marker version: each transition has one path and one marker with the same `data-n`, and the numbers are 1..len. No path passes strictly inside a box other than its ends. No two markers overlap (center distance ≥ `2 * MARKER_R`). No marker overlaps a box. No other path passes strictly inside a marker circle. Everything stays inside the view box. Add `assert_no_crossing(paths)`. When a segment between two neighbor samples of one path meets such a segment of another path, the two paths cross. Points within 2 px of a shared box border point do not count. Then:
  - `test_media_lifecycle_is_clean_and_uncrossed` (MEDIA lifecycle, `view_width ≤ 600`)
  - `test_shared_column_sample_is_uncrossed`: `queued` goes to `fetching`, `parsing` and `failed`, and `fetching` and `parsing` go back to `queued`
  - `test_task_status_is_clean` (the existing `TASK_STATUS`, plus no crossings)
  - `test_forward_only_is_not_wider_than_0_10_0`: `draft → review` "submit" and `review → published` "approve" give `view_width ≤ 457.5`
  - `test_second_loop_on_bottom_edge`: `idle → idle` "ping", `idle → idle` "tick", `idle → open` "connect". One loop is above the box and one below, and no end on idle's left side is within 9 px of the start arrow y.
  - `test_ends_on_a_side_are_apart`: across all fixtures, every two path ends on one box side are at least `END_GAP - 0.5` apart.
  - `test_missing_initial_has_no_start_dot`

  Remove or rewrite the old lane tests (`test_states_back_and_same_column_arrows_get_own_lanes`, `test_states_many_back_routes_stay_in_their_gaps`, and the label checks of `test_states_other_lifecycles_are_clean`) for the new rules.
- [ ] **Step 2: Run** the tests. Expected: they fail.
- [ ] **Step 3: Implement** `svg_states` with helpers, each under 50 lines. Remove the old helpers that nothing uses any more.
- [ ] **Step 4: Run** the unit tests, then the full suite. Expected: all pass.
- [ ] **Step 5: Commit** `feat: states ladder with numbered arrows and a key`.

### Task 6: Architecture that fits the page

**Files:**
- Modify: `scripts/contract_diagrams_svg.py`
- Modify: `tests/contract/test_contract_diagrams_svg.py`

**Interfaces:**
- Produces: `svg_architecture(architecture, prefix)`, same signature, plus `PAGE_LIMIT = 1100` and `LANE_PITCH = 8`.

Rules:
- The pills of a layer flow left to right. When the next pill pushes the layer box past `PAGE_LIMIT`, that pill starts a new pill row 36 px lower. The layer grows by 36 px for each extra row. The inner layers sit under the last pill row.
- If the siblings beside the nested group make the picture wider than `PAGE_LIMIT`, every sibling goes under the nested group. They sit side by side, 24 px below it, left-aligned with it.
- Implements lanes are `LANE_PITCH` apart, in the bands and in the gap. When m lanes leave or enter one pill, lane k uses `x = center + (k - (m - 1) / 2) * LANE_PITCH`, with k counted from 0. Rows and the gap grow as today. The last lane stays 4 px above the next pill row.
- The basic fixture output stays the same, so `SVG_ARCHITECTURE_SHA256` keeps its value.

- [ ] **Step 1: Write the failing tests:**
  - `test_media_architecture_fits`: `view_width ≤ 1100`, and the `workers` layer rect is below the nested group, not beside it.
  - `test_wide_layer_wraps_pills`: one layer with 14 components of 12 characters each is at most 1100 px wide, with pills on two rows.
  - `test_lanes_are_eight_apart`: `test_many_crossing_implements_get_own_bands` with an 8 px pitch.
  - `test_two_lanes_from_one_pill_leave_apart`: one adapter implements two far ports. The two paths start at x values 8 px apart.
  - The existing sibling and crossing tests keep passing.
- [ ] **Step 2: Run** the tests. Expected: they fail.
- [ ] **Step 3: Implement.** Keep `svg_architecture` under 50 lines with helpers.
- [ ] **Step 4: Run** the unit tests, then the full suite. Expected: all pass.
- [ ] **Step 5: Commit** `feat: architecture picture wraps and stacks siblings to fit the page`.

### Task 7: Plural forms in the page counts

**Files:**
- Modify: `scripts/contract_render.py`
- Test: `tests/test_contract_render.sh`

**Interfaces:**
- `CARD_ORDER` entries become `(key, singular, plural)`: `("gotchas", "gotcha", "gotchas")`, `("abilities", "ability", "abilities")`, `("interfaces", "interface", "interfaces")`, `("depends_on", "dependency", "dependencies")`, `("consumers", "consumer", "consumers")`, `("planned", "planned", "planned")`, `("open_questions", "open question", "open questions")`. `plural(count, singular, plural_form) -> str`. Update every caller.

- [ ] **Step 1: Write the failing test** in `test_contract_render.sh`: the page has no `abilitys`, `dependencys`, or `planneds`. A contract with 2 abilities shows `2 abilities`, and one with 1 dependency shows `1 dependency`.
- [ ] **Step 2: Run** `bash tests/test_contract_render.sh`. Expected: the new checks fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the render test, then the full suite. Expected: all pass.
- [ ] **Step 5: Commit** `fix: plural forms in the contract page counts`.

### Task 8: Ref shift script and draft reuse in a rebuild

**Files:**
- Create: `scripts/contract-ref-shift.sh`
- Create: `tests/test_contract_ref_shift.sh`
- Modify: `skills/start-task/references/execute.md` (step 6 of "Contract work")
- Modify: `tests/test_contract_skills.sh`

**Interfaces:**
- `contract-ref-shift.sh <repo_dir> <contract.yaml> <old_commit> <new_commit>`. It reads every ref of the contract: all sections, `planned`, and `diagrams`, the same set as `contract-refs.sh`. A local ref is `path:lines`. A ref with `@` is cross-repo. It reads the changed files with `git -C <repo_dir> diff --name-only --no-renames <old> <new>`. Output: one `changed: <ref>` line per local ref whose path changed, one `unchecked: <ref>: cross-repo` line per cross-repo ref, then `refs: <c> changed, <u> unchanged, <x> unchecked`. Exit 0. When the arguments are wrong, the contract file is missing, or a commit is unknown, it prints `contract-ref-shift: <reason>` on stderr and exits 2.
- In `execute.md`, step 6 of "Contract work" ends with the rule from the spec. A rebuild can start from the current contract. When the user undid the last contract task, it can start from that task's `contract.draft.yaml`. The agent copies it, runs `contract-ref-shift.sh` between its `verified_commit` and the new one, and reads each changed ref again. The run log names the draft it started from. The reviewer still judges the whole draft.

- [ ] **Step 1: Write the failing tests.** In `test_contract_ref_shift.sh`, HOME is a temp folder:
  - A temp git repo has commits A and B. B changes `a.py` and not `b.py`.
  - The contract has the refs `a.py:1`, `b.py:2`, `other/repo@abc123:x.py:1`, and a diagrams edge ref `a.py:3`.
  - Expected output, exit 0: `changed: a.py:1`, `changed: a.py:3`, `unchecked: other/repo@abc123:x.py:1: cross-repo`, `refs: 2 changed, 1 unchanged, 1 unchecked`.
  - A bad commit gives exit 2. Missing arguments give exit 2.

   In `test_contract_skills.sh`: `execute.md` names `contract-ref-shift.sh` and the sentence `The reviewer still judges the whole draft.`
- [ ] **Step 2: Run** both test files. Expected: they fail.
- [ ] **Step 3: Implement** the script and the `execute.md` text.
- [ ] **Step 4: Run** both test files, then the full suite. Expected: all pass.
- [ ] **Step 5: Commit** `feat: contract-ref-shift.sh and draft reuse in a contract rebuild`.

### Task 9: Reviewer check, browser note, and docs

**Files:**
- Modify: `agents/reviewer.md` (line 44), `skills/draw-contract/SKILL.md`, `README.md`, `docs/spec.md` (section 9.3), `CHANGELOG.md`
- Modify: `tests/test_contract_skills.sh`

**Interfaces:**
- `reviewer.md` line 44 becomes: a flow that misses a caller in `consumers`, or any service, database, queue, or other network peer in `depends_on`, is a blocking finding. `Where` is `diagrams.flow`.
- `draw-contract` gets a note for looking at an HTML file with `playwright-cli`. Serve the folder with `python3 -m http.server --bind 127.0.0.1`, because `playwright-cli` blocks `file://` URLs. Find an SVG node with `querySelector('[data-id="<id>"]')`, because a node id is not a DOM id. In `playwright-cli eval`, use the `() => { ...; return x }` form.
- `docs/spec.md` 9.3: replace the ASCII paragraph with the new note views, the page views, the key, and the width limits. Keep the rest.
- `README.md`: describe the phone note and the laptop page in its diagrams part.
- `CHANGELOG.md`: a `## 0.12.0 - 2026-11-26` entry with one line per user-visible change, in the style of 0.11.0.

- [ ] **Step 1: Write the failing asserts** in `test_contract_skills.sh`: the reviewer names `network peer`, and `draw-contract` names `http.server`, `file://`, and `data-id`.
- [ ] **Step 2: Run** `bash tests/test_contract_skills.sh`. Expected: they fail.
- [ ] **Step 3: Write** the text changes.
- [ ] **Step 4: Run** the full suite. Expected: all pass.
- [ ] **Step 5: Commit** `docs: phone-first diagram views, reviewer check, browser note`.

---

## After the plan (controller only)

The final whole-branch review and its fix wave come first. Then merge `feat/phone-first-diagrams` into `main`. Commit `chore: release 0.12.0` with the version in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `tests/test_manifest.sh`. Run the full suite, then run `release-push.sh 0.12.0` from the session scratchpad and poll the catalog. Send the user a push notification. Then tell MC-contractor to rerun the whole media-center contract.

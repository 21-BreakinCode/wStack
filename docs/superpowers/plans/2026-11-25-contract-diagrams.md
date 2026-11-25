# Contract Diagrams Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `diagrams` block to the service contract. Draw it as ASCII in the vault note and as SVG on the HTML page. Add diagram-design deep dives with `/wstack:draw-contract`.

**Architecture:** The contract YAML gets an optional top-level `diagrams` block. Two new Python modules draw it, `contract_diagrams.py` for ASCII, subjects, hashes, and deep dive state, and `contract_diagrams_svg.py` for SVG. `contract_render.py` calls them. A new script, `contract-diagram.sh`, stamps, installs, lists, and restores deep dives. Skill text wires the drawing into the task stages, the contract gate, and the retro.

**Tech Stack:** bash 3.2, jq, mikefarah yq 4.22.1 or later, Python 3.9 standard library.

**Spec:** `docs/superpowers/specs/2026-11-25-contract-diagrams-design.md`

## Global Constraints

- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`, runs on `/bin/bash` 3.2, and quotes every path variable.
- Python uses only the standard library and runs on Python 3.9. If `/usr/bin/python3` exists, tests run Python with it.
- Run `bash tests/run-all.sh` before each commit, under the bash 3.2 shim: `PATH="/private/tmp/claude-502/-Users-william-hung-Projects-breakincode-wStack/5a117309-887d-4dd8-9415-b838f528a718/scratchpad/bash32:$PATH" bash tests/run-all.sh`.
- Tests never write into `$HOME/Projects/LifeOS/`. A test that touches `~/.wstack` sets `HOME` to a temp folder.
- Test data uses neutral names (`acme-org/svc`, `other-svc`). No company-internal names.
- Docs and skill text follow the simple-english rules. The hook lints every `.md` write.
- A contract with no `diagrams` key, `diagrams: {}`, or `diagrams: null` is valid and renders as in 0.9.0, with no `Diagrams` heading.
- Subjects: `flow`, `sequence:<id>`, `states:<id>`, `architecture`. The slug of a subject replaces `:` with `-`.
- Deep dives live in `<contract folder>/diagrams/<slug>.html`. Their `meta` names are `wstack-subject`, `wstack-subject-hash`, and `wstack-drawn-at`.
- The shape hash is the SHA-256 hex digest of `json.dumps(value_without_refs, sort_keys=True, separators=(",", ":"), ensure_ascii=False)` in UTF-8, where every `refs` key is removed at every depth. Only `contract_diagrams.py` computes it. Ruling: this replaces the `yq -I=0` command of the spec, so that the renderer and the script share one function.
- Warnings only: a diagram with more than 30 nodes, a label with more than 40 characters. ASCII labels longer than 32 characters become the first 31 characters and `…`.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Old contracts: no `diagrams` key, `diagrams: {}`, or `diagrams: null`. `contract-validate.sh` passes, the views show no `Diagrams` heading, and the check never lists `diagrams`. Tests in Tasks 1, 2, 3, and 5.
2. Wide characters in labels, such as Chinese text: the ASCII boxes stay aligned, because widths count East Asian wide characters as 2 columns. Test in Task 2.
3. A file in `diagrams/` without the three `meta` tags, or a file that is not `.html`: the renderer skips a non-HTML file and lists an unstamped HTML file as `not stamped`. It does not crash. Test in Task 2.
4. Labels with `<`, `&`, quotes, and a state that `initial` cannot reach: the SVG escapes the text, parses as XML, and puts an unreachable state in a last column. Tests in Task 3.
5. Two draws of one subject in one task: the backup keeps the file from before the first draw, so an undo restores the state from before the task. Test in Task 4.

---

### Task 1: Schema, validation, refs, and the template

**Files:**
- Create: `tests/fixtures/contract/diagrams-block.yaml`
- Modify: `templates/contract.yaml`, `scripts/contract-validate.sh`, `scripts/contract-refs.sh`
- Test: `tests/test_contract_validate.sh`, `tests/test_contract_refs.sh`

**Interfaces:**
- Produces: the fixture `tests/fixtures/contract/diagrams-block.yaml`, a YAML file with one top-level key, `diagrams`. Later tasks merge it into the fixture contract with `yq -i '. *= load("<fixture>")' "$CONTRACT"`. Its refs cite only `cmd/main.go:1` and `api/routes.go:1`, which exist at `FIRST_COMMIT` of `tests/fixtures/contract/setup.sh`.
- Produces: the error lines below, which later tasks and the skill text quote.

The fixture holds all four kinds:
- `flow`: callers `web-ui` and `batch-job`. Parts `api` (label `API`) and `worker` (label `Worker`). Dependencies `postgres` and `other-svc`. Five edges: `web-ui → api` (`GET /items`), `batch-job → api` (`POST /items`), `api → worker` (`items.created`), `worker → postgres` (`SQL`), and `other-svc → worker` (`items.done`).
- `sequences`: one, id `create`, title `Create an item`, four steps. One step goes from `api` to `api`.
- `states`: one, id `item-status`, title `Item status`, `initial: new`, with the transitions `new → queued`, `queued → done`, `queued → failed`, and `failed → queued`.
- `architecture`: `style: clean`, three layers `adapters`, `use-cases`, `entities`. It has one component of kind `port` (`store-port`), one of kind `adapter` (`sql-store`), and `implements: [{adapter: sql-store, port: store-port}]`.

- [ ] **Step 1: Write the failing tests in `tests/test_contract_validate.sh`**

Add one case for each line, each on a copy of a valid contract:
- `no diagrams key is valid`, `diagrams: {} is valid`, `diagrams: null is valid`: exit 0.
- `the full fixture block is valid`: merge the fixture, exit 0, and empty stderr.
- `diagrams that is a list fails`: exit 1, stderr has `diagrams must be a map: diagrams`.
- `a bad id fails`: a part id `Bad_Id`, stderr has `bad diagram id: diagrams.flow.parts[0]: Bad_Id`.
- `a duplicate id fails`: a caller with id `api`, stderr has `duplicate diagram id: diagrams.flow.callers[0]: api`.
- `an edge to an unknown id fails`: stderr has `edge names an unknown id: diagrams.flow.edges[0]: nobody`.
- `an edge that touches no part fails`: `web-ui → postgres`, stderr has `edge touches no part: diagrams.flow.edges[0]`.
- `a part without refs fails`: stderr has `diagram entry without refs: diagrams.flow.parts[0]`. Same for an edge, a step, a transition, and an architecture component, each with its own `where`.
- `a node without a label fails`: stderr has `diagram entry without label: diagrams.flow.parts[0]`. Labels are required on parts, callers, dependencies, steps, and architecture components. They are optional on edges and transitions.
- `a caller without refs is valid`.
- `a sequence without steps fails`: `sequence without steps: diagrams.sequences[0]`. `a state lifecycle without transitions fails`: `state lifecycle without transitions: diagrams.states[0]`.
- `initial that names no state fails`: `initial names no state: diagrams.states[0]: gone`.
- `a bad style fails`: `bad architecture style: diagrams.architecture.style: onion`. The allowed values are `clean`, `hexagonal`, and `layered`.
- `a bad component kind fails`: `bad component kind: diagrams.architecture.layers[0].components[0]: thing`. The allowed kinds are `entity`, `use_case`, `port`, `adapter`, `controller`, and `other`.
- `an implements pair with a wrong kind fails`: `implements needs an adapter and a port: diagrams.architecture.implements[0]`.
- `a bad ref form in a diagram fails`: `bad ref form: diagrams.flow.edges[0]: nofile`.
- `31 flow nodes only warn`: exit 0, stderr has `diagrams.flow has 31 nodes`. `a 41-character label only warns`: exit 0, stderr has `label has 41 characters`.

Node counts: `flow` counts parts, callers, and dependencies. A sequence counts its distinct participants. A state lifecycle counts its distinct states. `architecture` counts its components.

- [ ] **Step 2: Write the failing test in `tests/test_contract_refs.sh`**

`diagram refs are checked`: merge the fixture, then set the first edge's refs to `[nofile.go:1]`. Expect exit 1, the line `bad: nofile.go:1: no file nofile.go at <FIRST_COMMIT>`, and a `refs:` count line that counts the diagram refs.

- [ ] **Step 3: Run the tests and see them fail**

Run: `bash tests/test_contract_validate.sh; bash tests/test_contract_refs.sh`
Expected: the new cases FAIL.

- [ ] **Step 4: Implement**

- `contract-validate.sh`: add the rules to the jq program as `E <rule>: <where>` and `W warning: <text>` lines. `where` uses the paths in Step 1. An absent or null `diagrams` adds no rule.
- `contract-refs.sh`: add `(.diagrams // {} | .. | objects | select(has("refs")) | .refs | arrays | .[])` to the jq list that feeds the loop.
- `templates/contract.yaml`: add `diagrams: {}` between `sections:` and `planned: []`.

- [ ] **Step 5: Run the tests and see them pass**

Run: `bash tests/test_contract_validate.sh; bash tests/test_contract_refs.sh`
Expected: every case PASSES.

- [ ] **Step 6: Run the suite, then commit**

```bash
git add tests/fixtures/contract/diagrams-block.yaml templates/contract.yaml scripts/contract-validate.sh scripts/contract-refs.sh tests/test_contract_validate.sh tests/test_contract_refs.sh
git commit -m "feat: validate the contract diagrams block and check its refs"
```

### Task 2: Subjects, hashes, deep dive state, ASCII, and the note

**Files:**
- Create: `scripts/contract_diagrams.py`, `tests/contract/test_contract_diagrams.py`, `tests/test_contract_diagrams.sh`
- Modify: `scripts/contract_render.py`
- Test: `tests/test_contract_render.sh`

**Interfaces:**
- Consumes: the fixture of Task 1.
- Produces, in `scripts/contract_diagrams.py`:
  - `subjects(diagrams: dict) -> "collections.OrderedDict[str, object]"`: the present subjects in the order `flow`, each `sequence:<id>`, each `states:<id>`, `architecture`.
  - `subject_slug(subject: str) -> str`: `sequence:create` gives `sequence-create`.
  - `shape_hash(value: object) -> str`: the hash in Global Constraints.
  - `display_width(text: str) -> int`: East Asian `W` and `F` characters count 2.
  - `read_deep_dives(contract_folder: str, diagrams: dict) -> list`: one dict for each `*.html` file in `<contract_folder>/diagrams/`, sorted by file name: `{"path": <absolute path>, "name": <file name>, "subject": <str or None>, "state": "fresh" | "stale" | "subject removed" | "not stamped"}`.
  - `ascii_flow(flow: dict) -> str`, `ascii_sequence(sequence: dict) -> str`, `ascii_states(lifecycle: dict) -> str`, `ascii_architecture(architecture: dict) -> str`.
  - `note_lines(diagrams: dict, deep_dives: list) -> list`: the note's `## Diagrams` section. With no subject and no deep dive, it returns `[]`.
  - CLI: `python3 contract_diagrams.py hash <subject>` and `python3 contract_diagrams.py subject <subject>` read the contract JSON on stdin. `hash` prints the hash. `subject` prints the subject's JSON with an indent of 2. A missing subject exits 1 with `no subject: <subject>` and `subjects: <comma-separated list>` on stderr.

- [ ] **Step 1: Write the failing unit tests in `tests/contract/test_contract_diagrams.py`**

Use `unittest`. Load the fixture with `yq -o=json` once in `setUpModule`. Cases:
- `test_subjects_order`: the keys are `["flow", "sequence:create", "states:item-status", "architecture"]`.
- `test_hash_ignores_refs`: change only the refs of a flow edge, and the hash stays. Change a label, and the hash changes.
- `test_hash_is_key_order_free`: the same dict built in two key orders gives one hash.
- `test_ascii_flow`: the output has `┌` and `└`. A line holds `web-ui`, `GET /items`, and `▶`. The edge `other-svc → worker` draws `◀` on the right side. The part-to-part edge is on a line that starts with `inside:`. Every line that crosses the box has its left `│` at the same display column.
- `test_ascii_flow_wide_label`: a part label `圖片服務` keeps the right `│` of every box line at the same display column.
- `test_ascii_truncates`: a 40-character label shows as its first 31 characters and `…`.
- `test_ascii_sequence`: the first line names the participants in order of first use. A left-to-right step has `▶`, a right-to-left step has `◀`, and the step from `api` to `api` draws `┐`.
- `test_ascii_states`: the first line is `initial: new`. Then one line for each transition, each with `──▶` at the same display column.
- `test_ascii_architecture`: three `┌` lines that hold the layer names in order, and a last line that starts with `ports:` and holds `store-port <- sql-store`. If a component has a label, use the label.
- `test_read_deep_dives`: in a temp folder, write five files in `diagrams/`. `flow.html` has the right hash. `sequence-create.html` has a wrong hash. `states-gone.html` is for the subject `states:gone`. `hand.html` has no `meta` tag. The fifth file is `notes.txt`. Expect the states `fresh`, `stale`, `subject removed`, and `not stamped`, with no entry for `notes.txt`.
- `test_note_lines_empty`: `note_lines({}, [])` is `[]`.

The runner `tests/test_contract_diagrams.sh` compiles `scripts/contract_diagrams.py` and runs the test file, in the style of `tests/test_handover_python.sh`.

- [ ] **Step 2: Write the failing render tests in `tests/test_contract_render.sh`**

- `a contract without diagrams has no Diagrams heading`: the current fixture.
- `the note shows Diagrams after the summary and before Gotchas`: merge the fixture block, render, and expect `## Diagrams` between the summary line and `## Gotchas`. Expect `### Component flow`, `### Sequence: Create an item`, `### States: Item status`, and `### Architecture (clean)`, each followed by a line of three backticks and `text`.
- `the note lists deep dives with their state`: put a stale `diagrams/flow.html` next to the contract. Expect `### Deep dives` and the line `- [flow.html](diagrams/flow.html) (stale)`. A fresh file has no mark.

- [ ] **Step 3: Run the tests and see them fail**

Run: `bash tests/test_contract_diagrams.sh; bash tests/test_contract_render.sh`
Expected: FAIL, because `contract_diagrams.py` does not exist.

- [ ] **Step 4: Implement `scripts/contract_diagrams.py` and wire it into `render_note`**

Layouts, as in the spec's sketches:
- Flow: callers on the left, one box with the part labels in the middle, dependencies on the right. Each edge to or from a caller is a left row, and each edge to or from a dependency is a right row. The arrowhead points to `to`. The rows are paired by index, and the box is as tall as the larger of its parts plus 2 and the row count. Part-to-part edges go under the box as `inside: <from> ── <label> ──▶ <to>`.
- Sequence: one column for each participant, with a `│` lifeline. One row for each step, with the label on the arrow. A self step is `│──┐ <label>` and then `│◀─┘`.
- States: `initial: <id>`, then one aligned line for each transition: `<from> ──<label>──▶ <to>`.
- Architecture: nested boxes, outer layer first. Each top border holds the layer name. Each box lists its component labels. A last `ports:` line lists each pair as `<port label> <- <adapter label>`.

Deep dive `meta` parsing: a regex on `<meta name="wstack-…" content="…">` in the file text, with `html.unescape` on the content. Wiring: `render_note(data, contract_name, deep_dives)` puts `note_lines` after the line `Verified at …` and its blank line. `main` computes `deep_dives = read_deep_dives(os.path.dirname(os.path.abspath(note_path)), data.get("diagrams") or {})`.

- [ ] **Step 5: Run the tests and see them pass**

Run: `bash tests/test_contract_diagrams.sh; bash tests/test_contract_render.sh`
Expected: PASS.

- [ ] **Step 6: Run the suite, then commit**

```bash
git add scripts/contract_diagrams.py scripts/contract_render.py tests/contract/test_contract_diagrams.py tests/test_contract_diagrams.sh tests/test_contract_render.sh
git commit -m "feat: draw contract diagrams as ASCII in the vault note"
```

### Task 3: SVG diagrams on the HTML page

**Files:**
- Create: `scripts/contract_diagrams_svg.py`, `tests/contract/test_contract_diagrams_svg.py`
- Modify: `scripts/contract_render.py`, `tests/test_contract_diagrams.sh`
- Test: `tests/test_contract_render.sh`

**Interfaces:**
- Consumes: `subjects`, `subject_slug`, `display_width`, and `read_deep_dives` from Task 2.
- Produces, in `scripts/contract_diagrams_svg.py`:
  - `svg_flow(flow: dict, prefix: str) -> str`, `svg_sequence(sequence: dict, prefix: str) -> str`, `svg_states(lifecycle: dict, prefix: str) -> str`, `svg_architecture(architecture: dict, prefix: str) -> str`. Each returns one `<svg>` element. `prefix` makes the `id` of each arrow marker unique on the page. Use the subject slug.
  - `html_section(diagrams: dict, deep_dives: list) -> str`: `<h2>Diagrams</h2>`, then one `<figure class="diagram">` with a `<figcaption>` for each subject, then `<h3>Deep dives</h3>` and a list of `<a href="file://<path>">` links. A deep dive in any state other than `fresh` gets `<span class="badge">` with the state. With no subject and no deep dive, it returns `""`.

- [ ] **Step 1: Write the failing unit tests in `tests/contract/test_contract_diagrams_svg.py`**

- `test_svgs_parse`: each of the four functions on the fixture returns text that `xml.etree.ElementTree.fromstring` parses, with a root tag that ends in `svg` and a `viewBox`.
- `test_labels_present_and_escaped`: every node label of the fixture is in the SVG text. A label `<b>&"x"` shows as `&lt;b&gt;&amp;&quot;x&quot;`, and the SVG still parses.
- `test_marker_ids_unique`: in `html_section` of the fixture, every `id="…"` value is unique.
- `test_long_label_widens`: a flow with a 40-character part label has a wider `viewBox` than the fixture flow.
- `test_unreachable_state`: add the transition `orphan → done`. `svg_states` still parses and holds `orphan`.
- `test_section_empty`: `html_section({}, [])` is `""`.
- `test_badges`: a `stale` deep dive gets `<span class="badge">stale</span>`, and a `fresh` one gets no badge.

- [ ] **Step 2: Write the failing page tests in `tests/test_contract_render.sh`**

- `a page without diagrams has no Diagrams heading`.
- `the page has four SVG diagrams`: with the fixture block, the page has `<h2>Diagrams</h2>` and four `<svg`.
- `the page wraps diagrams for horizontal scroll`: the CSS has `.diagram` with `overflow-x: auto`.

- [ ] **Step 3: Run the tests and see them fail**

Run: `bash tests/test_contract_diagrams.sh; bash tests/test_contract_render.sh`
Expected: the new cases FAIL.

- [ ] **Step 4: Implement**

The SVG uses classes, not fixed colors. Add CSS rules to `CSS` in `contract_render.py` that use the page variables: shapes `fill: var(--card); stroke: var(--line)`, lines `stroke: var(--muted)`, the service box and arrowheads `var(--link)` as the one accent color, and text `fill: var(--fg)`. Use flat shapes, no shadows, and 1.5px lines. Estimate text width as 7.5px for each display column at 13px. Layouts:
- Flow: three columns of boxes. The service box holds the part boxes. Straight arrows go from each caller or dependency box to the service box edge, with the label above the line. Part-to-part arrows run inside the service box.
- Sequence: participant boxes at the top, dashed lifelines, one row for each step with 36px between rows, and a loop path for a self step.
- States: rounded boxes in columns by breadth-first distance from `initial`. A state that `initial` cannot reach goes in a last column. Forward arrows are straight or curved. An arrow to the same column or to an earlier column bends below the row.
- Architecture: nested rounded rectangles with 24px padding. Each layer shows its components as pills, and each `implements` pair is a dashed line from the adapter pill to the port pill.

Wiring: `render_html` puts `html_section` after the summary card. Add the CSS `.diagram { overflow-x: auto; margin: 12px 0; } .diagram svg { display: block; max-width: none; } .badge { … }`. `contract_render.py` stays under 400 lines.

- [ ] **Step 5: Run the tests and see them pass**

Run: `bash tests/test_contract_diagrams.sh; bash tests/test_contract_render.sh`
Expected: PASS.

- [ ] **Step 6: Run the suite, then commit**

```bash
git add scripts/contract_diagrams_svg.py scripts/contract_render.py tests/contract/test_contract_diagrams_svg.py tests/test_contract_diagrams.sh tests/test_contract_render.sh
git commit -m "feat: draw contract diagrams as SVG on the contract page"
```

### Task 4: `contract-diagram.sh` and `contract-open.sh --contract`

**Files:**
- Create: `scripts/contract-diagram.sh`, `tests/test_contract_diagram.sh`
- Modify: `scripts/contract-open.sh`, `tests/test_contract_open.sh`

**Interfaces:**
- Consumes: the CLI of `contract_diagrams.py` (Task 2), and `contract-edit.sh lock|unlock`.
- Produces:
  - `contract-diagram.sh subject <contract.yaml> <subject>`: prints `hash: <hex>`, then the subject JSON. Exit 0, 1 for no subject (stderr lists the subjects), 2 for a bad call.
  - `contract-diagram.sh install <contract.yaml> <subject> <drawn.html> [--backup-dir <dir> --record <list file>]`: prints `installed: <path>`. If it made a backup, it also prints `backup: <path>`. Exit 0, 1 for no subject, 2 for bad input, 4 for a busy lock.
  - `contract-diagram.sh stale <contract.yaml>`: one line `stale: <subject> <path>` for each stamped deep dive whose subject exists and whose hash differs. Always exit 0, unless the call is bad (exit 2).
  - `contract-diagram.sh restore <list file>`: prints `restored: <path>` or `removed: <path>` for each line. Exit 0. If a listed backup is missing, exit 1 and change nothing. A missing list file prints nothing and exits 0.
  - The list file format: one line for each installed deep dive, `<installed path><TAB><backup path or empty>`.
  - `contract-open.sh --vault <vault> --contract [<service>]`: prints the contract YAML path and exits 0. It renders nothing and opens nothing. Exit 1 and 2 are as before.

- [ ] **Step 1: Write the failing tests in `tests/test_contract_diagram.sh`**

Build the world with `tests/fixtures/contract/setup.sh`, merge the fixture block into `$CONTRACT`, and set `HOME` to a temp folder. Cases:
- `subject prints the hash and the JSON`: the hash equals the output of `yq -o=json . "$CONTRACT" | python3 scripts/contract_diagrams.py hash flow`.
- `an unknown subject exits 1 and lists the subjects`: stderr has `subjects: flow, sequence:create, states:item-status, architecture`.
- `install stamps and places the file`: `<folder>/diagrams/flow.html` exists with three `meta` tags right after `<head>`. The hash equals the subject hash, and `wstack-drawn-at` equals `verified_commit`.
- `install replaces old wstack meta tags`: install a file that already holds `wstack-*` tags, and each name appears once.
- `install refuses a file with no head`: exit 2.
- `a second install keeps the first backup`: install, change nothing, install again with `--backup-dir` and `--record`. The backup holds the first drawn file, and the list has one line for the path.
- `--backup-dir without --record exits 2`.
- `stale is empty when fresh`, `stale lists a changed label`: after `yq -i '.diagrams.flow.parts[0].label = "API v2"'`, stale prints `stale: flow <path>`.
- `stale ignores a refs-only change`.
- `restore puts back the backup and removes a new deep dive`.
- `restore with a missing backup changes nothing`: exit 1, and both files stay.
- `a busy lock exits 4`: make `$CONTRACT.lock` as a folder first.

Add to `tests/test_contract_open.sh`: `--contract prints the YAML path` for no argument in `$REPO` and for `svc`. No page is written.

- [ ] **Step 2: Run the tests and see them fail**

Run: `bash tests/test_contract_diagram.sh; bash tests/test_contract_open.sh`
Expected: FAIL.

- [ ] **Step 3: Implement**

`install` takes the lock with `contract-edit.sh lock`, and `unlock` runs in a trap. It removes old `<meta name="wstack-…">` tags, then inserts the three new tags after the first `<head…>` tag. It writes the result to `diagrams/<slug>.html` with `mkdir -p`. Three things must be true for a backup: the target exists, `--backup-dir` is set, and `<backup dir>/<slug>.html` does not exist yet. If no line of the record names the target, it appends one. `restore` checks every listed backup before it changes anything. If the `diagrams/` folder is empty after the restore, it removes the folder. It always removes the used list file.

- [ ] **Step 4: Run the tests and see them pass**

Run: `bash tests/test_contract_diagram.sh; bash tests/test_contract_open.sh`
Expected: PASS.

- [ ] **Step 5: Run the suite, then commit**

```bash
git add scripts/contract-diagram.sh scripts/contract-open.sh tests/test_contract_diagram.sh tests/test_contract_open.sh
git commit -m "feat: add contract-diagram.sh to stamp, install, list, and restore deep dives"
```

### Task 5: `contract-edit.sh apply --diagrams` and diagram staleness

**Files:**
- Modify: `scripts/contract-edit.sh`, `scripts/contract-check.sh`
- Test: `tests/test_contract_edit.sh`, `tests/test_contract_check.sh`

**Interfaces:**
- Produces:
  - A patch can hold a top-level `diagrams:` map, next to `sections:` and `remove_planned:`. If `diagrams:` is present, `sections:` is optional.
  - With no flag, `apply` applies every section of the patch. If the patch has the `diagrams` key, it applies the block too. With any flag, it applies only the flagged parts.
  - `--diagrams` (no value) sets `.diagrams` to the patch's block. If the patch has no block, it removes `.diagrams`. An undo from a snapshot without a block then works.
  - If `apply` applied the block, it prints `diagrams` on its own line, after the section keys.
  - Two things make `contract-check.sh` add `diagrams` to `stale_sections`: the contract's `diagrams` is a non-empty map, and `abilities`, `interfaces`, `depends_on`, or `consumers` is stale. In `--coverage` mode it never adds it.

- [ ] **Step 1: Write the failing tests**

In `tests/test_contract_edit.sh`:
- `apply with no flag applies diagrams`: the output has the line `diagrams`, and the block equals the patch.
- `--sections alone leaves diagrams`.
- `--diagrams from a snapshot without diagrams removes the block`.
- `a patch with only diagrams is accepted`.
- `a patch with diagrams as a list is refused`: exit non-zero, and the contract does not change.

In `tests/test_contract_check.sh`:
- `diagrams is stale when interfaces is stale`: merge the fixture block and commit a change under `api/`. `stale_sections` holds `"interfaces"` and `"diagrams"`.
- `an empty diagrams block is never stale`.
- `coverage mode never lists diagrams`.

- [ ] **Step 2: Run the tests and see them fail**

Run: `bash tests/test_contract_edit.sh; bash tests/test_contract_check.sh`
Expected: the new cases FAIL.

- [ ] **Step 3: Implement**

Extend four things: the patch shape check, the flag parser (`--diagrams`), the "patch holds nothing to apply" rule, and the usage lines in the header comments.

- [ ] **Step 4: Run the tests and see them pass**

Run: `bash tests/test_contract_edit.sh; bash tests/test_contract_check.sh`
Expected: PASS.

- [ ] **Step 5: Run the suite, then commit**

```bash
git add scripts/contract-edit.sh scripts/contract-check.sh tests/test_contract_edit.sh tests/test_contract_check.sh
git commit -m "feat: apply and check the contract diagrams block"
```

### Task 6: `contract-deliver.sh` keeps `diagrams/` and undoes drawn deep dives

**Files:**
- Modify: `scripts/contract-deliver.sh`
- Test: `tests/test_contract_deliver.sh`

**Interfaces:**
- Consumes: `contract-diagram.sh restore` (Task 4) and the list file `$task_dir/diagrams.drawn.txt`.

- [ ] **Step 1: Write the failing tests**

- `write leaves diagrams in place`: a `diagrams/flow.html` in the contract folder stays, is not in the archive, and the output has `unchanged: <folder>/diagrams`.
- `undo restores deep dive backups and removes drawn deep dives`: after `write`, make `diagrams/flow.html` (new) and `diagrams/sequence-create.html` (with a backup), and list both in `$task/diagrams.drawn.txt`. After `undo`, the new file is gone, the backup is back, and the folder matches the copy from before `write`.
- `undo with a missing deep dive backup changes nothing`: exit 1, and `same_as_copy` of the state after `write` holds.

- [ ] **Step 2: Run the tests and see them fail**

Run: `bash tests/test_contract_deliver.sh`
Expected: the new cases FAIL.

- [ ] **Step 3: Implement**

Add `diagrams` to the names that the archive step of `write` skips. `write` prints it as `unchanged:`. In `undo`, check the listed backups in the pre-check loop, before any change. Then run `contract-diagram.sh restore "$task_dir/diagrams.drawn.txt"` before the archive moves back. Extend the header comment.

- [ ] **Step 4: Run the tests and see them pass**

Run: `bash tests/test_contract_deliver.sh`
Expected: PASS.

- [ ] **Step 5: Run the suite, then commit**

```bash
git add scripts/contract-deliver.sh tests/test_contract_deliver.sh
git commit -m "feat: keep deep dives on contract delivery and restore them on undo"
```

### Task 7: The build path: `/wstack:draw-contract`, Execute, Verify, and Deliver

**Files:**
- Create: `skills/draw-contract/SKILL.md`
- Modify: `skills/start-task/references/execute.md`, `skills/start-task/references/verify.md`, `agents/reviewer.md`, `skills/deliver-task/SKILL.md` ("Contract files" and "Finish")
- Test: `tests/test_skills.sh`, `tests/test_contract_skills.sh`

**Interfaces:**
- Consumes: `contract-open.sh --contract`, `contract-diagram.sh subject|install|stale`, `contract-render.sh`.
- Produces: the "Draw steps" of `skills/draw-contract/SKILL.md`, which Task 8 calls with `--backup-dir` and `--record`. "Inside a task" is a mode of these steps: a missing diagram-design writes the `run-log.md` line `deep dive <subject> skipped: diagram-design is not installed` and returns, and a failed draw writes `deep dive <subject> failed: <reason>` and returns. Neither stops the task.

- [ ] **Step 1: Write the failing tests**

In `tests/test_skills.sh`: add `draw-contract` to `expected_skills`, and add `draw-contract stays model-invocable`: no `disable-model-invocation`, and the file names `contract-diagram.sh install`. Add `diagram-design stays a soft dependency`: the `dependencies` list of `.claude-plugin/plugin.json` does not name `diagram-design`.

In `tests/test_contract_skills.sh`, one `grep -qF` assert for each anchor:
- `skills/draw-contract/SKILL.md`: `diagram-design:diagram-design`, `faithful`, `contract-open.sh`, `--contract`, `contract-render.sh`, and `keep the default style`.
- `execute.md`: `diagrams.flow` and `architecture`.
- `agents/reviewer.md`: `diagrams.flow`.
- `verify.md`: `diagrams`.
- `deliver-task/SKILL.md`: `contract-diagram.sh stale`, `diagrams.backup`, `diagrams.drawn.txt`, and `/wstack:draw-contract`.

- [ ] **Step 2: Run the tests and see them fail**

Run: `bash tests/test_skills.sh; bash tests/test_contract_skills.sh`
Expected: FAIL.

- [ ] **Step 3: Write the skill text**

`skills/draw-contract/SKILL.md`:
- Front matter: `name: draw-contract`. Description: draw a diagram of a service contract with the diagram-design skill, from the contract's `diagrams` block. The trigger is a user request to draw, redraw, or visualize a contract, or one of its flows, sequences, state lifecycles, or architecture. No `disable-model-invocation`.
- Usage: `/wstack:draw-contract [<service>] [<what to draw>]`.
- Config: resolve the vault path as `skills/open-contract/SKILL.md` does.
- Draw steps:
  1. Run `contract-open.sh --vault "<vault>" --contract [<service>]`. On exit 1, show its list and ask. On exit 2, print stderr and stop.
  2. Map `<what to draw>` to one subject. The default is `flow`. Run `contract-diagram.sh subject`. On exit 1, show the `subjects:` line and ask.
  3. If `diagram-design:diagram-design` is not in the available skills, tell the user to run `/plugin marketplace add cathrynlavery/diagram-design` and `/plugin install diagram-design@diagram-design`, and stop. Inside a task, use the mode in Interfaces.
  4. Run the diagram-design skill with the subject JSON and these rules. The diagram type is architecture for `flow`, sequence for `sequence:`, state machine for `states:`, and layers for `architecture`. Use `faithful` density. Draw only what the JSON holds: merge, drop, or shorten for a readable picture, but add nothing. If diagram-design asks about its style guide, keep the default style. Skip its plan approval step. Write the HTML to a new file in `mktemp -d`.
  5. Run `contract-diagram.sh install "<contract>" <subject> "<drawn file>"`. If the caller gives `--backup-dir` and `--record`, pass them.
  6. Run `contract-render.sh "<contract>"`. Print the installed path.
- The user's request to draw is the approval to write that deep dive.

`execute.md`, Contract work, step 6: for an existing project, fill `diagrams` from the code at `origin/<base_branch>`, as the spec's "Changes to the task flow" says. The parts are the processes and modules of the service. The callers come from `consumers`. The dependencies are network services, databases, queues, and storage. Each call is one edge, labeled with its route, topic, or protocol. Add up to five sequences. Add one state lifecycle for each record with a status field. Add `architecture` only for code with clean, hexagonal, or layered layers. Every entry that needs refs cites them at `verified_commit`. For a new project, keep `diagrams: {}`.

`agents/reviewer.md` and `verify.md` step 4: the reviewer judges each diagram entry like an item. A ref that does not show its claim is a blocking `spec-mismatch`. A flow that misses a caller in `consumers`, or a network service in `depends_on`, is a blocking finding with `Where` `diagrams.flow`. An `architecture` block for code with no such layers is blocking.

`deliver-task/SKILL.md`, "Contract files": after `contract-deliver.sh write`, run `contract-diagram.sh stale "<contract>"` and run the Draw steps for each listed subject. If the contract has `diagrams.flow` and `diagrams/flow.html` does not exist, run the Draw steps for `flow` next. Pass `--backup-dir "$task_dir/diagrams.backup" --record "$task_dir/diagrams.drawn.txt"`, in the inside-a-task mode. The undo of the target is unchanged, because `contract-deliver.sh undo` restores the list. "Finish": add `/wstack:draw-contract <app_name>` next to `/wstack:open-contract <app_name>`.

- [ ] **Step 4: Run the tests and see them pass**

Run: `bash tests/test_skills.sh; bash tests/test_contract_skills.sh`
Expected: PASS.

- [ ] **Step 5: Run the suite, then commit**

```bash
git add skills/draw-contract/SKILL.md skills/start-task/references/execute.md skills/start-task/references/verify.md agents/reviewer.md skills/deliver-task/SKILL.md tests/test_skills.sh tests/test_contract_skills.sh
git commit -m "feat: add /wstack:draw-contract and draw deep dives on contract delivery"
```

### Task 8: The update path: reader, gate step 9, pending items, and the retro

**Files:**
- Modify: `agents/contract-reader.md`, `skills/start-task/references/confirmation.md` (step 9), `skills/deliver-task/SKILL.md` ("Pending items"), `skills/run-retro/SKILL.md` (D5 to D7)
- Test: `tests/test_contract_skills.sh`

**Interfaces:**
- Consumes: `apply --diagrams` and the `diagrams` line (Task 5), `contract-diagram.sh stale|restore` (Task 4), and the Draw steps in the inside-a-task mode (Task 7).

- [ ] **Step 1: Write the failing tests**

One `grep -qF` assert for each anchor in `tests/test_contract_skills.sh`:
- `contract-reader.md`: `diagrams:`.
- `confirmation.md`: `has("diagrams")`, `--diagrams`, `contract-diagram.sh stale`, and `contract-diagram.sh restore`.
- `deliver-task/SKILL.md` "Pending items": `--diagrams` and `contract-diagram.sh restore`.
- `run-retro/SKILL.md`: `--diagrams` and `contract-diagram.sh stale`.

- [ ] **Step 2: Run the tests and see them fail**

Run: `bash tests/test_contract_skills.sh`
Expected: the new cases FAIL.

- [ ] **Step 3: Write the text**

- `contract-reader.md`: the patch holds the whole new `diagrams:` block at the top level, next to `sections:`, in two cases. One case is a check that lists `diagrams`. The other is a task whose facts change a diagram.
- `confirmation.md` step 9: If the patch has the `diagrams` key, `patched_keys` also holds `"diagrams"`. Use `yq -p yaml -o json '(.sections // {} | keys) + (if has("diagrams") then ["diagrams"] else [] end)'`. If `apply` printed `diagrams`, the undo command adds `--diagrams`. After the call, run `contract-diagram.sh stale` and the Draw steps for each listed subject, with `--backup-dir "$task_dir/diagrams.backup" --record "$task_dir/diagrams.drawn.txt"`. If it drew anything, add `bash '<scripts>/contract-diagram.sh' restore '<task folder>/diagrams.drawn.txt'` to the undo line.
- `deliver-task/SKILL.md` "Pending items": after a `MERGED` item's call, do the same with the merged task's folder: backups in `<task folder>/diagrams.backup` and the list in `<task folder>/diagrams.drawn.txt`. Add `--diagrams` and the restore command to the undo of the `contract write-back` target in that task's `report.md`.
- `run-retro/SKILL.md` D5 to D7: offer `diagrams` with the stale sections. When the user picks it, the chosen patch keeps `.diagrams`, `apply` runs with `--diagrams`, and `still_stale` subtracts it. After the apply, run `contract-diagram.sh stale` and the Draw steps, with backups in `<retro file without .md>.diagram-backups/` and the list `drawn.txt` in that folder. Put the restore command in the retro's `## Contract` section.

- [ ] **Step 4: Run the tests and see them pass**

Run: `bash tests/test_contract_skills.sh`
Expected: PASS.

- [ ] **Step 5: Run the suite, then commit**

```bash
git add agents/contract-reader.md skills/start-task/references/confirmation.md skills/deliver-task/SKILL.md skills/run-retro/SKILL.md tests/test_contract_skills.sh
git commit -m "feat: redraw stale deep dives where contract updates are applied"
```

### Task 9: Docs and the changelog

**Files:**
- Modify: `README.md`, `docs/spec.md`, `CHANGELOG.md`
- Test: `tests/test_docs.sh`, `tests/test_changelog_format.sh`

- [ ] **Step 1: Write the text**

- `README.md`: add `/wstack:draw-contract [<service>] [<what to draw>]` to the command list. Say that contract views show diagrams from the `diagrams` block. Say that deep dives need the diagram-design plugin, give its two install commands, and say that wStack works without it.
- `docs/spec.md`: add the tree lines for `skills/draw-contract/SKILL.md`, `scripts/contract-diagram.sh`, `scripts/contract_diagrams.py`, and `scripts/contract_diagrams_svg.py`. Add a short subsection on the `diagrams` block, its four subjects, and the deep dive files.
- `CHANGELOG.md`: a `## 0.10.0 - 2026-11-25` entry. Its `**feat:**` lines cover the block and the generated views, the deep dives with `/wstack:draw-contract`, and the redraws at build and update. Add a `**change:**` line saying that existing contracts get diagrams through a contract task rerun.

- [ ] **Step 2: Run the suite**

Run: the full suite under the bash 3.2 shim.
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add README.md docs/spec.md CHANGELOG.md
git commit -m "docs: describe contract diagrams and /wstack:draw-contract"
```

The release commit (version `0.10.0` in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `tests/test_manifest.sh`) comes after the final review, with the user's approval.

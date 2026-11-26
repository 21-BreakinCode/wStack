# Phone-first contract diagrams

Status: draft of 2026-11-26. The user approved approach A and the numbered labels. The builder check ran. It ships as wStack 0.12.0.

## Intent

The user reads service contracts in two places. On the phone, the user reads the vault note in Obsidian. On the laptop, the user reads the local HTML page. Today both views are too wide for a human. In the media-center contract, the note drawings are 67 to 144 columns wide. The page pictures are 677 to 1435 px wide in a 760 px text column. The user asked for "a more readable human favored way", with the phone first. A picture that only fits a laptop is acceptable on the laptop page.

The same release closes the known limits of 0.11.0 and the items from the media-center run report that the user picked.

## Goals

- Every diagram view in the vault note fits a phone screen: 40 columns at most (`NOTE_COLUMNS = 40`).
- Every picture on the HTML page fits a laptop window with no sideways scroll.
- Text that a reader needs (arrow labels, step labels) is never cut in a list. Lists wrap to the screen.
- The states and sequence pictures carry small numbers on their arrows. A key next to the picture gives each number its full text.
- The 0.11.0 known limits are closed (see "Fixes").
- The run-report items the user picked are closed: page width, plurals, flow ASCII width, and contract-task tooling.

## Non-goals

- No change to the contract YAML schema. The `diagrams` block, its refs, and its validation rules stay as in 0.11.0.
- No change to deep dives. diagram-design draws them, and the user reads them on the laptop.
- No refs in the diagram views. Today the pictures show no refs, and the new lists and keys show none either. The refs stay in the YAML, and `contract-refs.sh` proves them.
- No Mermaid. The user picked approach A.
- No phone layout for the HTML page. The page is for the laptop.

## Anti-goals

- A drawing in the note that Obsidian wraps. Forum reports say Obsidian sometimes wraps long lines in code blocks, and a wrapped drawing is unreadable. So no note code block line is longer than `NOTE_COLUMNS`.
- A cut label with no way to read it in full. Every cut label keeps its `…[n]` footnote, as in 0.11.0.
- A view that states a fact the YAML does not state. The views only rearrange the YAML.
- A deep dive marked stale by this release. Layout changes do not change `shape_hash`. The only hash change is the `sibling: false` fix below.

## Constraints

- Python scripts use only the standard library and run on Python 3.9. Bash scripts run on `/bin/bash` 3.2.
- Functions are under 50 lines. `svg_flow` (86 lines today) goes away with the new flow view.
- Tests never write into `$HOME/Projects/LifeOS/`. A new test fixture in `tests/fixtures/contract/` has the shape of the media-center diagrams block. It has 4 parts, 8 callers, 9 dependencies, and 37 edges. It also has a 7-participant sequence, the 10-transition lifecycle, and a clean architecture with a sibling layer. Use made-up names that keep the shape and the label lengths. No Appier-internal names.
- Docs and skill text follow simple English.

## Approaches

The user picked A.

- A. Overview plus lists. The note gets small drawings of at most 40 columns, plus Markdown lists that wrap. The page gets a flow overview with part cards, and numbered pictures for states and sequences.
- B. Narrow drawings everywhere. Every note view is redrawn top to bottom at 40 columns, with labels cut and footnoted. The media-center flow has 37 arrows, so the result is very tall with many footnotes. It also needs the most code.
- C. Mermaid in the note. Obsidian draws Mermaid itself. Big pictures get tiny text on a phone, and forum threads report Mermaid failures on Obsidian mobile.

For the labels in the states picture, the user picked numbered arrows with a key over inline labels. A throwaway render of the media-center lifecycle was 497 px wide with numbers and 949 px with inline labels. Inline labels collided where several arrows meet.

For the states layout, two methods were considered. The "ladder" (below) keeps the current breadth-first columns. The Graphviz method reverses the fewest arrows and gives each state a column by longest path. It adds pass-through points for long arrows and orders rows by neighbor average. It moves every arrow into the gaps, but it needs about three times the code. The ladder was chosen because it removed every crossing in the media-center lifecycle.

## Design

### The vault note (phone)

Each diagram kind gets one phone-friendly form. Headings and the order of the views stay as in 0.11.0.

Component flow:

1. An overview drawing in a `text` code block of at most 40 columns. It shows the service zone with its parts, one per line. It shows one merged node `N callers` with an arrow into each part that a caller calls. It shows the arrows between two parts. A dependency that calls a part gets its own named node beside that part, with an arrow into it (designer's call). It still counts in `N dependencies`. It shows one merged node `N dependencies`, with one arrow from the zone. It shows no arrow labels.
2. One Markdown list per part, under a bold part name. The "called by" list holds the callers, parts, and dependencies that call this part. The "calls" list holds the dependencies and parts that this part calls. Each line is `<name>: <edge label>`. Two edges with the same pair each get a line.

Sequences: a numbered Markdown list, one line per step: `1. <from> → <to>: <label>`.

State lifecycles: the key (see "The key" below) as a Markdown list. A bold heading line for each source state is followed by its outgoing arrows, `<n>. → <to>: <label>`. The start state is marked `(start)`.

Architecture: a tree in a `text` code block of at most 40 columns. The outermost layer is the root. Each layer lists its components, then the next inner layer as its last child. A sibling layer is its own tree under the nested one, with the note `(beside the nested layers)`. A label longer than the room at its depth is cut with `…[n]` and a footnote. Under the tree, a list gives each implements pair: `<adapter> ─▶ <port>`.

The `labels:` footnote block of 0.11.0 stays for every cut text in a code block.

### The HTML page (laptop)

A `.diagram` figure can grow past the 760 px text column, up to `min(1200px, 100vw - 32px)`, centered on the page. Every picture for the media-center-shaped fixture is at most 1100 px wide. A test checks the `width` attribute of each SVG.

Component flow: an overview SVG with the same content as the note overview, drawn top to bottom. Under it, one card per part with the same "called by" and "calls" lists as the note. The cards sit in a CSS grid that wraps (`repeat(auto-fill, minmax(320px, 1fr))`).

Sequences: the SVG keeps lifelines and arrows. Each arrow carries its step number in place of its label, so the space between two lifelines depends only on the participant names. The media-center sequence with 7 participants is about 850 px wide this way, and 1228 px today. The key is an `<ol>` under the picture.

State lifecycles: the ladder layout with numbered arrows. The key is an `<ol>` under the picture.

Architecture: nested layer boxes as in 0.11.0, plus two changes. If a layer row is wider than 1100 px, its pills wrap into more rows inside the layer. If the sibling layers beside the nested group make the picture wider than 1100 px, the siblings go under the nested group.

### The key

The key lists every transition of a lifecycle. It is grouped by source state, states in column order and then row order. A transition's number is its position in the key, starting at 1, and the picture uses the same number. A page key line is `<n>. <from> → <to>: <label>`. A transition with no label shows only `<from> → <to>`.

### The states ladder layout

- Columns stay as today: the breadth-first distance from the start state.
- An arrow to the next column runs in the gap between the two columns, as today.
- An arrow back to the previous column also runs in that gap. It leaves the left side of its source and enters the right side of its target.
- An arrow between two neighbor rows of one column runs straight up or down, in the gap between the two boxes. Down arrows sit left of up arrows.
- An arrow back by two or more columns keeps a lane under the boxes, as today.
- An arrow between two rows of one column that are not neighbors runs as a leg beside the column, on its right side.
- The ends on each box side are ordered by the row of the far end, so arrows in one gap do not cross.
- Each number marker sits near one end of its arrow. A lane or leg marker sits at the middle of its long segment. Two markers must not overlap. The ends on a side are at least 18 px apart. If a side needs more room, its box grows taller.
- One self-loop sits on the top edge, as today. A second self-loop on the same state is drawn as a loop on the bottom edge.
- The start arrow keeps its own slot on the left side of the start state. No arrow end on that side uses its height. This fixes 0.11.0 limit 4.
- A side space is only as wide as the lines in it, with at least 16 px. The left side of the first column keeps room for the start dot. This fixes 0.11.0 limit 1. A forward-only lifecycle is no wider than in 0.10.0.

### Fixes

- 0.11.0 limit 2, crossing arrows: the ladder layout. A test checks that no two arrow paths cross for the media-center-shaped lifecycle and for this sample: `queued` goes to `fetching`, `parsing`, and `failed`, and `fetching` and `parsing` go back to `queued`. Each path is checked as a polyline.
- 0.11.0 limit 3: if `sibling` is `false`, `shape_hash` leaves it out. A test checks that a layer with `sibling: false` and the same layer without the key give the same hash.
- 0.11.0 limit 5: in the architecture picture, implements lanes are 8 px apart, not 3 px. Two lanes that leave one pill leave from two points 8 px apart. Rows and the gap grow to keep the last lane 4 px above the next row of pills, as today.
- 0.11.0 limit 6: the new flow functions replace `svg_flow` and stay under 50 lines each.
- Plurals: the page counts use explicit plural forms. `CARD_ORDER` holds singular and plural for each card: `ability`/`abilities`, `dependency`/`dependencies`, `planned`/`planned`, `open question`/`open questions`, and the rest with a plain `s`. A test checks "1 ability" and "67 abilities".

### Contract-task tooling

- The draw-contract skill gets a note. `playwright-cli` blocks `file://` URLs. To look at an HTML file, serve its folder with `python3 -m http.server --bind 127.0.0.1`, as `scripts/check-page-width.sh` does. A node in a page SVG has a `data-id` attribute, not a DOM id, so use `querySelector('[data-id="<id>"]')`. In `playwright-cli eval`, use the `() => { ...; return x }` form.
- A new script `scripts/contract-ref-shift.sh <repo_dir> <contract.yaml> <old_commit> <new_commit>` prints `changed: <ref>` for each local ref whose file changed between the two commits, then a `refs:` count line. It reads the file list with `git diff --name-only`. It skips cross-repo refs, and prints `unchecked: <ref>: cross-repo` for each. Exit 0 on success, 2 on bad input.
- A rebuild can reuse a reviewed draft (the user's decision of 2026-11-26). The contract work of `skills/start-task/references/execute.md` gets a rule before step 6. A rebuild of a contract can start from the current contract in the contract folder. If the user undid the last contract task, it can start from that task's `contract.draft.yaml`. The agent copies it, runs `contract-ref-shift.sh` between its `verified_commit` and the new one, and reads each changed ref again. The run log names the draft it started from. The reviewer still judges the whole draft.
- The reviewer's diagram checks (`agents/reviewer.md`) get one more check. Every service, database, queue, or other network peer in `depends_on` must appear in `diagrams.flow.dependencies`. A `depends_on` item has no type field, so a validator cannot tell a network peer from a library. That is why this is a reviewer check.

## Acceptance

- `bash tests/run-all.sh` passes under the bash 3.2 shim.
- For the media-center-shaped fixture, no line in a note code block is wider than 40 columns (display width).
- For the same fixture, no SVG is wider than 1100 px.
- The two crossing tests and the forward-only width test pass.
- A contract with no `diagrams` block renders as in 0.11.0.
- The README, `docs/spec.md` section 9, and the CHANGELOG describe the new views.

## Left to the builder

- Glyphs and spacing inside the 40-column drawings.
- The exact look of the flow overview SVG and of the cards, within the content rules above.
- Marker size and the exact end position of each marker.
- How the tests check for crossing paths.

## After the release

The user asked for the same steps as after 0.11.0. The user updates the plugin after the notification. So:

1. Release 0.12.0 with `release-push.sh`. The user's words approve the push. The script is in the session scratchpad. The plan's implementers do not run it.
2. Send the user a push notification.
3. Tell MC-contractor to rerun the whole media-center contract, as in the 0.11.0 rerun.

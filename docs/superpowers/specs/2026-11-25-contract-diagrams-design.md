# Contract diagrams

Status: draft of 2026-11-25. The builder check ran. It ships as wStack 0.10.0.

## Intent

The user reads service contracts to understand a service. Since 0.8.0 the contract is a YAML file with two generated views, a vault note and an HTML page. Both views are still mostly text. The user wants to see the service as pictures, "as much as possible": a UML-style component flow first, then other views of the same facts.

## Goals

- The vault note shows ASCII diagrams in `text` code blocks.
- The HTML page shows the same diagrams as inline SVG.
- Four generated diagram kinds:
  - Component flow: the callers, the parts of the service, and the dependencies, with labeled edges.
  - Sequences: key flows, step by step.
  - State lifecycles: the status changes of a record.
  - Architecture layers: if the code follows clean, hexagonal, or layered architecture, this view shows entities, use cases, ports, adapters, and the ports that each adapter implements.
- The generated diagrams come from a new structured `diagrams` block in the contract YAML. A plain script draws them, so every contract edit redraws them, and they always match the YAML.
- Deep dives: polished diagrams that the agent draws with the third-party diagram-design skill. Each deep dive draws one part of the `diagrams` block. A deep dive is drawn on request with the new command `/wstack:draw-contract`. A contract task also draws one at build time. A later contract update redraws each deep dive whose drawn shape it changed.
- The page links each deep dive. If its part of the block changed after the drawing, the page marks it stale.

## Non-goals

- No diagram of data tables (ER). The user did not pick it.
- No shortcut that fills `diagrams` into an existing contract without a task. Old contracts get diagrams through a rerun of the contract task (the user's choice).
- wStack does not manage diagram-design profiles. If the user saves one with `/diagram-design:profile`, diagram-design uses it.
- No Mermaid. The user asked for ASCII in the note.

## Anti-goals

- A diagram that states a fact the contract does not state. The YAML stays the only source of facts. Every edge, step, transition, part, and layer component cites refs, and `contract-refs.sh` proves them like any other ref.
- A wStack that fails to load because diagram-design is missing. diagram-design is a soft dependency. It is not in the `dependencies` of `plugin.json`.
- A breaking change. A contract with no `diagrams` block stays valid and renders as in 0.9.0.

## Approaches

1. Generated from data. The renderer draws ASCII and SVG from a structured block. Always fresh, no new plugin, but fixed layouts only.
2. Drawn by the agent with diagram-design. This gives the richest look and any diagram type. The costs: the diagram is stale after each contract edit, wStack needs a new plugin, each run uses more tokens, and each run gives a different result.
3. Both. Generated diagrams are always there. Deep dives drawn with diagram-design come on top. If the data of a deep dive changes, the page marks it stale.

The user picked 3.

## The `diagrams` block

The block is a top-level key of the contract, next to `sections` and `planned`. It is optional. Every sub-key is optional.

```yaml
diagrams:
  flow:
    parts:                       # the service's own components
      - id: api
        label: API (FastAPI)
        refs: [app/main.py:1-40]
    callers:                     # who calls the service; refs optional
      - id: media-center-ui
        label: media-center-ui
    dependencies:                # what the service calls; refs optional
      - id: image-center-2
        label: image-center-2
    edges:
      - from: media-center-ui
        to: api
        label: GET /folders
        refs: [app/routers/folders.py:20-60]
  sequences:
    - id: upload
      title: Upload a folder
      steps:
        - from: client
          to: api
          label: POST /folders
          refs: [app/routers/folders.py:80-120]
  states:
    - id: task-status
      title: Optimize task status
      initial: pending
      transitions:
        - from: pending
          to: processing
          label: a worker takes the message
          refs: [app/workers/image.py:30-44]
  architecture:
    style: clean                 # clean | hexagonal | layered
    layers:                      # outer to inner
      - name: adapters
        components:
          - id: gcs-store
            label: GCS store
            kind: adapter        # entity | use_case | port | adapter | controller | other
            refs: [app/adapters/gcs.py:1-30]
    implements:
      - adapter: gcs-store
        port: storage-port
```

The validation rules of `contract-validate.sh`:

- Every `id` is kebab case. The ids of `parts`, `callers`, and `dependencies` are unique together. Sequence ids are unique. State ids are unique. Architecture component ids are unique.
- Every edge names a known flow id at both ends, and at least one end is a part.
- `refs` is required, with at least one ref in the usual form, on every part, edge, step, transition, and architecture component. Callers and dependencies can leave out `refs`, because their edges carry the evidence.
- A sequence step names any participant. A participant is a flow id or a free name, such as `client`.
- `initial` of a state lifecycle names a state used in its transitions.
- Each `implements` pair names an architecture component of kind `adapter` and one of kind `port`.
- Warnings only: a diagram with more than 30 nodes, a label with more than 40 characters.

A new project (`project: new`) has no code, so its contract has no `diagrams` block.

## Generated views

A new module, `scripts/contract_diagrams.py`, draws both forms. `contract_render.py` calls it. Python 3.9 standard library only.

The note gets a `## Diagrams` section after the summary line and before `## Gotchas`. It holds one `###` heading and one `text` code block for each diagram. The page gets the same section as inline SVG, using the page's color variables, so it works in light and dark mode. The SVG copies the plain look of diagram-design: flat shapes, no shadows, thin lines, one accent color.

The layouts:

- Component flow: three columns. The callers are on the left, one box of the service with its parts is in the middle, and the dependencies are on the right. Each edge is an arrow with its label. An edge between two parts is drawn inside the service box. In ASCII, it is listed under the box.

  ```
   media-center-ui ──GET /folders──▶ ┌──────────────────┐ ──optimize.requested──▶ image-center-2
   mimic ──────────POST /captures──▶ │ API (FastAPI)    │ ──SQL─────────────────▶ PostgreSQL
                                     │ image worker     │
                                     └──────────────────┘
  ```

- Sequence: one column for each participant, in the order of first use, and one row for each step. The arrows point right or left. A step to the same participant draws a loop.

  ```
   client          api            gcs        image-center-2
     │──POST /folders──▶│              │              │
     │                  │──write──────▶│              │
     │                  │──optimize.requested────────▶│
  ```

- State lifecycle: the SVG puts the states in columns by their distance from `initial` and draws curved arrows. A transition back to an earlier state bends below the row. The ASCII lists one line for each transition, aligned in columns: `pending ──a worker takes the message──▶ processing`.
- Architecture layers: nested boxes, outer layer outside, each box listing its components. A `ports:` line under the boxes lists each `implements` pair.

ASCII labels longer than 32 characters end in `…`. The SVG shows the full label.

## Deep dives

A deep dive is one HTML file drawn by the diagram-design skill, for one subject of the `diagrams` block. The subjects are `flow`, `sequence:<id>`, `states:<id>`, and `architecture`.

- Location: `<contract folder>/diagrams/<subject slug>.html`, in the vault, next to the contract. The slug of `sequence:upload` is `sequence-upload`.
- Stamp: a script writes three `meta` tags into the file head: `wstack-subject`, `wstack-subject-hash`, and `wstack-drawn-at` (the `verified_commit` at drawing time). The hash is the SHA-256 of the drawn shape of the subject: the subject's JSON with every `refs` key removed, from `yq -o=json -I=0 'del(.. | .refs?)'` of that sub-block. A code change that only moves cited lines does not make a deep dive stale. (Builder check, my call.)
- Only the subject: the agent gives diagram-design the subject's JSON and the diagram type for the subject: `flow` is an architecture diagram, `sequence:` a sequence, `states:` a state machine, `architecture` a layers diagram. The agent tells it to draw only the nodes and the edges in the JSON, at its `faithful` density. For a readable picture, diagram-design can merge, drop, or shorten nodes and labels. It adds no node, edge, or label that the JSON does not hold. One subject gives one file. The generated diagrams stay the complete view. (Builder check, my call.)
- Style: if diagram-design asks about its style guide (its pristine-guide question), the agent keeps the default style. The agent skips diagram-design's step that asks the user to approve its plan. wStack never writes a `.diagram-design` marker into a repository. To brand the deep dives, the user runs diagram-design's onboarding or `/diagram-design:profile` once. (Builder check, my call.)
- Staleness: the renderer reads the `meta` tags of each file in `diagrams/` and compares the hash with the current subject. The note and the page list each deep dive with a link. A deep dive whose hash differs is marked `stale`. A deep dive whose subject no longer exists is marked `subject removed`.

A new script, `scripts/contract-diagram.sh`, does the mechanical parts:

- `subject <contract> <subject>` prints the subject's JSON and its hash.
- `install <contract> <subject> <drawn html> <backup path>` stamps the file and moves it into `diagrams/`. If a deep dive of that subject exists, the script first copies the old file to `<backup path>`. An undo restores it from there.
- `stale <contract>` prints one line for each deep dive whose hash differs: `stale: <subject> <file>`.

### `/wstack:draw-contract [<service>] [<what to draw>]`

A new skill. Model invocation stays on. A session can then run the skill on the user's request.

1. Find the contract the same way `contract-open.sh` does: by service name, or by the current repository.
2. Map `<what to draw>` to one subject. With no `<what to draw>`, the subject is `flow`. If the subject does not exist in the YAML, list the subjects that exist and ask.
3. If the diagram-design skill is not available, stop and tell the user to install it.
4. Get the subject's JSON, have diagram-design draw it to a temp file, and run `contract-diagram.sh install`.
5. Run `contract-render.sh`, so the page links the new deep dive. Print the deep dive path.

The user's request to draw is the approval to write that deep dive.

## Changes to the task flow

- `templates/contract.yaml` gets `diagrams: {}`.
- Execute (`execute.md`, Contract work): for an existing project, fill `diagrams.flow` from the code at `verified_commit`. Add up to five sequences for the key flows. Add a state lifecycle for each record with a status field. If the code has clean, hexagonal, or layered layers, add `architecture`.
- `verify.md`: `contract-refs.sh` also proves the diagram refs. The reviewer judges whether each diagram ref shows its claim. It also makes sure that the flow names every caller in `consumers` and every service in `depends_on` that the code calls over the network.
- Deliver (contract task): after `contract-deliver.sh write`, redraw each deep dive that `contract-diagram.sh stale` lists. If the contract has a `flow` and no deep dive of `flow` exists, draw `flow` next. Follow the steps of `/wstack:draw-contract` for each. Keep the backups in `$task_dir/diagrams.backup/`. Record each drawn file and each backup in `$task_dir/diagrams.drawn.txt`. `contract-deliver.sh undo` removes the drawn files and restores the backups. The archive step skips the `diagrams/` folder.
- A contract update: a code task's write-back only queues a patch. The patch is applied after the PR merges, in "Pending items" of the `deliver-task` skill. That section runs in gate step G4 of a later task and in `run-retro`. After each `apply` there, and after the `apply` of gate step 9, run `contract-diagram.sh stale` and redraw each stale deep dive (the user's choice: redraw where the update is applied). The task or the retro that runs the `apply` records the backups and the undo, next to the undo of the update itself. A deep dive of a removed subject stays in place, shown as `subject removed`.
- Deliver's Finish names `/wstack:draw-contract` next to `/wstack:open-contract`.
- `contract-edit.sh apply`: a patch can hold a `diagrams:` block. The flag `--diagrams` applies it, and the block replaces the contract's `diagrams` block. The snapshot and undo rules cover it like a section.
- `contract-check.sh`: if any of the sections `abilities`, `interfaces`, `depends_on`, or `consumers` is stale, it also reports `diagrams` as stale. The reader's patch then carries a new `diagrams` block.
- If diagram-design is not available during a task, the task skips the deep dive, writes one line in `run-log.md`, and goes on. The generated diagrams do not need it.

## What is left to the builder

- The exact SVG geometry: spacing, curve shapes, font sizes, label placement.
- How `contract_diagrams.py` splits into functions, and how to keep `contract_render.py` under 400 lines.
- The test fixtures, as long as each diagram kind has an ASCII and an SVG test and each validation rule has a failing case.
- The wording of the new skill, within the steps above.

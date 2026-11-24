# Contract as YAML with generated views

Status: approved by the user, 2026-11-24. Branch `feat/contract-yaml`. Target release: wStack 0.8.0.

## Intent

The first real contract task (media-center, 2026-11-23) built a contract that was too long for the user to read. The user felt context burnout on the first read, before any task used the contract. The contract files held about 5,200 words: `media-center.md` alone had 363 lines and 3,776 words.

The contract has two readers:

- The agent loads the contract at the start of every task. It needs correct facts in a clean form that a script can check.
- The human reads the contract to decide whether to trust it, and later to learn a service. The human needs what the service does, what can bite, and what is planned, in about a minute.

The user picked the model of FastAPI and Swagger. One structured source file is the truth. A renderer builds the views that people read.

## What made the old contract hard to read

- Almost every bullet carries an inline reference block, for example `(app/core/domain/entities/storage.py:207-213, 318-331)`. The block is often longer than the claim.
- `## Team docs` is 50 `- @path` lines. Only `contract-check.sh` uses them, to claim files.
- The same fact appears twice. The four video and rollback problems are Gotchas in `media-center.md` and items in `plan.md`.
- `## Interfaces` retypes 15 routes that the app's own OpenAPI document already describes.
- Decisions 0001 to 0004 copy the repository's `docs/adr/` files. Decisions 0005 to 0007 record wStack settings (base branch, ignore list, line format), not service choices.
- `## Open questions` holds 26 doc-versus-code disagreements. They ride along into every task.

## Goals

1. One source file per service, `<app_name>.contract.yaml`, in the contract folder. Agents and scripts read and write only this file.
2. Two generated views from that file: a vault note `<app_name>.md` for Obsidian, and an HTML page `~/.wstack/pages/contracts/<app_name>.html` for the browser.
3. References stay complete for the agent and the scripts, but the views hide them behind a fold or a click.
4. A script proves that every reference exists at `verified_commit`. The reviewer then judges meaning only.
5. Each fact lives in one place.

## Non-goals

- No change to the facts file `<app_name>.facts.md`. It stays Markdown.
- No change to decision files as a format. They stay Markdown, because they are prose records.
- No automatic import of OpenAPI content into the contract. The contract links the OpenAPI document.
- No size limit enforced by a script.

## Anti-goals

- A view that a person edits by hand. Every view is generated, and the next render overwrites it.
- A second source of truth. If the YAML and a view disagree, the YAML wins.
- A format that the plugin's own scripts cannot parse with the required tools.

## Constraints

- Scripts run on `/bin/bash` 3.2 and Python 3.9 with the standard library only. The standard library has no YAML parser.
- `yq` becomes a required tool, by the user's choice. It is the Go version by mikefarah, major version 4 (`yq --version` prints `mikefarah` and `v4`). A Python tool with the same name takes other syntax, so preflight must reject it. `jq` stays required.
- `contract-check.sh` keeps its output lines and its exit codes. The lines are `status`, `base`, `behind`, `stale_sections`, `stale_dependencies`, `unclaimed_files`, `unclaimed_count`, and `pending`. Then the hook, the gate, and the retro keep their parsing.
- `contract-edit.sh` stays the only writer of contract files, under the lock folder `<contract file>.lock`.
- The repository is public. Examples use placeholder service names.

## Approaches

Every approach starts with the same cuts: drop the `@path` lists, link the OpenAPI document, write each fact once, link repo ADRs, and move the disagreements out of the contract.

- A. Slim Markdown. Apply the cuts and move references to the end of each section. This is the least work, but references stay visible text and no script checks them.
- B. YAML source plus generated views. Claims become structured items with `refs`. A script checks the refs, and a renderer builds the views. It reads best, but it rewrites the contract tooling.
- C. Markdown with a fixed reference tail, `%%refs: ...%%`, that Obsidian hides in reading view. The existing section scripts keep working.

The user picked B. The user then picked both views (vault note and HTML page), and YAML over JSON with `yq` as a new required tool.

## The source file

Path: `<vault>/01Project/<ORG>/<lifeos_subpath>/<app_name>.contract.yaml`. `contract-path.sh` prints this path in place of the `.md` path.

Example, with placeholder values:

```yaml
app_name: example-service
repo: example-org/example-service
base_branch: staging
verified_commit: e2117a9
verified_at: 2026-11-23T11:16:45Z
pending: []
ignore: []
tags: [type/contract, project/example-org/example-service]
summary: Stores uploaded media folders in cloud storage and runs image and video optimize jobs.
openapi: docs/api/openapi.json
sections:
  team_docs:
    sources: [README.md, docs/**]
  abilities:
    sources: [app/core/**, app/adapters/**, config/**, tests/**]
    items:
      - text: A folder with storage_bucket set is read-only. PATCH, retry, and result writes refuse it.
        refs: [app/config.py:147-152, app/core/domain/use_cases/storage.py:141-145]
  interfaces:
    sources: [app/ports/restful/**, app/ports/pubsub/**, app/workers/**]
    items:
      - text: Each error body is {"errors": [...]}. Validation errors return 422.
        refs: [app/ports/restful/data_models.py:23-60]
  depends_on:
    sources: [app/ports/clients/**, pyproject.toml]
    items:
      - text: Calls video-center-2 mission_create with no timeout and no retry.
        refs: [app/ports/clients/video_center.py:10-14]
        app: video-center-2
        mapped_commit: 4f3c2a1
  consumers:
    items:
      - text: video-generator sends the tag enum on upload.
        refs: [example-org/video-generator@ca3a273:src/media_center.ts:22]
  gotchas:
    items:
      - text: Video workers ack before they commit, so a failed commit loses the message.
        refs: [app/workers/video_worker.py:40-42]
        planned: video-ack-after-commit
  open_questions:
    items: []
planned:
  - id: video-ack-after-commit
    title: Video workers ack after the commit and nack on errors
    why: A failed commit loses the message today.
    refs: [app/workers/video_worker.py:52-56]
```

Rules:

- The section keys are fixed: `team_docs`, `abilities`, `interfaces`, `depends_on`, `consumers`, `gotchas`, `open_questions`. The check and the patches use these keys as section names.
- `sources` is a list of repo-relative globs. It is required for `team_docs`, `abilities`, `interfaces`, and `depends_on`. It replaces the `<!-- sources: -->` comments and the `- @path` lines. `consumers`, `gotchas`, and `open_questions` have no `sources`.
- `team_docs` has `sources` and no items. The reader reads the files that its globs match.
- An item has `text` (one claim, at most 25 words) and `refs` (at least one ref).
- A ref is `path:lines` at `verified_commit`, where `lines` is `N`, `N-M`, or a comma list of both. A ref into another repository is `<owner>/<repo>@<commit>:path:lines`.
- A `depends_on` item that names a mapped service has `app` and `mapped_commit`. This replaces the `<app> (mapped): ... commit <sha>` line form.
- A gotcha that a plan item fixes has `planned: <id>`. The plan item does not repeat the gotcha text.
- `planned` replaces `plan.md`. Each item has `id` (kebab case), `title`, `why`, and optional `refs`.
- `open_questions` holds only what a later task finds: an unclaimed file that no section fits, or a doc-versus-code disagreement. The disagreements that a `contract` task finds go into its `report.md`, not into the contract.
- `pending` and `ignore` keep their meaning. They are YAML lists now, so the one-line JSON rule of the old frontmatter goes away for this file.
- `summary` is one or two sentences. It is required.
- `openapi` is optional. When the repository serves or holds an OpenAPI document, the contract links it and lists in `interfaces` only what the document does not show.

## Generated views

A new script `scripts/contract-render.sh <contract.yaml>` writes both views. `contract-edit.sh` runs it at the end of every write, so the views follow every change. Deliver of a `contract` task runs it once after the copy.

The vault note `<app_name>.md`:

- First line after the frontmatter: a notice that the note is generated from `<app_name>.contract.yaml` and that edits are lost.
- The frontmatter keeps `tags`, so vault search and tag views keep working.
- Order: summary, freshness line (`verified_commit`, `verified_at`), Gotchas, Abilities, Interfaces, Depends on, Consumers, Planned, Open questions, Team docs.
- Each item is one bullet with its text. Its refs sit in a folded Obsidian callout under the bullet, `> [!quote]- refs (N)`, and each ref is a GitHub link at `verified_commit` (`https://github.com/<repo>/blob/<commit>/<path>#L<N>-L<M>`).
- A gotcha with `planned` shows a link to its plan item.
- Team docs and the sources globs sit at the end, folded.

The HTML page `~/.wstack/pages/contracts/<app_name>.html`:

- The same content and order, with a summary card at the top (counts of items per section, freshness, base branch).
- Refs sit behind a click (`<details>`), with the same GitHub links.
- It must fit at 375 px, like the other wStack pages (`check-page-width.sh`).

## Scripts

- `contract-path.sh`: prints `<app_name>.contract.yaml`.
- `contract-check.sh`: reads the YAML with `yq`. The logic stays. The claimed files come from every `sources` glob. A changed file marks its sections stale. A changed file that no glob claims counts as unclaimed. A `depends_on` item with `mapped_commit` compares with the `verified_commit` of that service's contract. The stale section names are the section keys.
- `contract-edit.sh`:
  - `apply <contract.yaml> <patch.yaml> [--sections "a,b"]`: the patch is a YAML file with a `sections:` map and an optional `remove_planned: [<id>, ...]` list. Each named section replaces the whole section. A key that the contract does not have is an error, not an append, because the key set is fixed.
  - `remove-planned <contract.yaml> <id>` replaces `delete-section`. If the id is gone, it exits 1.
  - `pending-add`, `pending-remove`, `set-verified`, `lock`, `unlock`, and `next-decision-id` keep their behavior on the YAML file.
  - Every write subcommand runs `contract-render.sh` after the write.
- New `scripts/contract-refs.sh <repo_dir> <contract.yaml>`: for each ref, it checks that the file exists at the ref's commit and that every line number is inside the file. It prints one line per bad ref. Exit 0 means all refs hold, 1 means a ref is bad, and 2 means an error. A ref into another repository uses the local clone found through the Service Mapping. If the commit is not in that clone, the ref prints as `unchecked` and does not fail.
- `contract-hook.sh`: names the app from the YAML file name.
- `preflight.sh`: checks `yq`, the mikefarah version 4.

## Skills and agents

- `templates/contract.md` becomes `templates/contract.yaml`. `templates/plan.md` goes away.
- `execute.md`, Contract work: Execute writes `contract.draft.yaml` and `decisions.draft/`. It writes the doc-versus-code disagreements to `disagreements.md` in the task folder, and Deliver copies them into `report.md`. A repository ADR becomes a `team_docs` glob (`docs/adr/**`), not a decision file. The spec choices about wStack settings (base branch, ignore list) become YAML fields, not decision files. A decision file holds only a choice about the service that the task made.
- `verify.md`: a `contract` task runs `contract-refs.sh` on the draft as a standard check. The reviewer reads the claims with their refs and judges whether each ref shows the claim.
- `deliver-task`, Contract files: copies `contract.draft.yaml` to the contract path, runs `contract-render.sh`, and archives the old files as today. The old `<app_name>.md` and `plan.md` move to `_archive/<task_id>/`, so a migrated service keeps its old text.
- `contract-reader`: reads the YAML. Its patch is a YAML file with the `sections:` map. It reads the `team_docs` globs in place of the `@path` lines.
- `confirmation.md` gate and `run-retro`: the patch files become YAML. The undo commands name the YAML file.
- `docs/spec.md`: describe the new file, views, and scripts.

## Migration

Two contracts exist today: `wstack.md` (BreakinCode) and `media-center.md` (Appier). The builder's call, proposed here: no migration script. `contract-path.sh` finds no `.contract.yaml`, so the gate reports the contract as missing, and the user rebuilds each one with a `contract` task. Deliver archives the old Markdown files. The user already planned to rerun the media-center contract task.

## Items from the media-center fix list

The fix list is in memory as `wstack-media-center-feedback`. On 2026-11-24 the user approved items 1, 2, 4, and 5 for this release. The design settles items 3 and 6.

- Item 3, the reviewer sampled refs: `contract-refs.sh` checks the existence of every ref, and the reviewer judges meaning.
- Item 6, a rerun copies decisions again: repository ADRs and wStack settings no longer become decision files.
- Item 1, the result is hard to find. Finish step 8 of `deliver-task` and `## Where` of `report.md` give, for every work type:
  - a file tree of what the targets wrote, each file labeled NEW, REPLACED, MOVED, or UNCHANGED;
  - one line for each repository that did not change (the vault is not a git repository, so `git diff` shows nothing);
  - the commands that open the result: `open '<review.html>'`, and for a contract, `open '<contract page>'` and the vault note name for Obsidian (Cmd+O);
  - the reading order from `## Guided diff` in `review.md`.
- Item 2, the contract checks ran by hand three times. The Deliver "Contract files" block moves out of the skill text into `scripts/contract-deliver.sh`:
  - `write <task_dir> <contract_file> <task_id>`: the block as it is today, adapted to the YAML file. It prints one labeled line per file (`new:`, `replaced:`, `moved:`), which feeds the file tree of item 1.
  - `undo <task_dir> <contract_file> <task_id>`: the undo steps that `report.md` lists today as prose. The `undo` value in `report.md` becomes this one command.
  - `rehearse <task_dir> <contract_file> <task_id>`: copies the contract folder and the task folder to a temporary folder, runs `write` and then `undo` on the copies, and runs `diff -r` against a clean copy. Exit 0 means the undo restores the folder.
  - Verify of a `contract` task runs four scripted checks on the draft: `contract-check.sh` (with a claim coverage run from the root commit), `contract-validate.sh`, `contract-refs.sh`, and `contract-deliver.sh rehearse`. Confirmation names them in every contract spec. Each one saves its output as an evidence file.
  - `tests/test_contract_blocks.sh` runs the Deliver block from the skill text today. Those tests move to the script.
- Item 4, an edit after the last review. Any edit to the work after the last review, a non-blocking fix included, reruns the scripted checks. Then the reviewer reads only the diff of that edit. For a contract draft, Verify saves a copy of the draft before the fix, so the diff exists.
- Item 5, refs into other repositories. Before Execute cites another repository, it runs `git -C <clone> fetch origin <default branch>`. It cites `<owner>/<repo>@<commit>`, where the commit is `origin/<default branch>` of that clone. If the fetch fails, it cites the local commit, and `contract-refs.sh` reports a ref that it cannot check as `unchecked`.

## Calls made after the builder check

A fresh reviewer read this design as a builder. These are the answers, each one my call.

1. A render failure is a warning. `contract-edit.sh` prints the error on stderr and keeps its exit code, because the YAML is already written and is the truth. The next write renders again, and `contract-render.sh` can run by hand.
2. Undo uses snapshots, as today. The snapshot is a copy of the whole YAML file. `apply` takes a full contract file as a patch. `--sections` limits it to the named sections, and a new `--planned "<id>,<id>"` flag restores those plan items from the snapshot. `remove_planned` does not clear the `planned:` links of gotchas. The views show a link to a removed item as "plan item removed".
3. A new `scripts/contract-validate.sh <contract.yaml>` checks the schema: the fixed keys, the required `summary` and `sources`, at least one ref per item, kebab-case plan ids, and `planned:` links. It exits 1 on a broken rule. `apply` runs it on the result before the write and refuses a broken result. Verify runs it on the draft. The 25-word limit only prints a warning.
4. A patch section carries the whole section, `sources` included, as the old patch carried its sources comment. The validation refuses a section that lost its required `sources`. A stale `team_docs` section gets patched like any other section.
5. A dependency whose contract is still the old `<app_name>.md` falls back to the `verified_commit` in that file's frontmatter. A missing contract counts as unknown, not stale.
6. `facts-add.sh` and the `init-service` skill change to the YAML name, so every lock is `<app_name>.contract.yaml.lock`.
7. A ref is cross-repository when it matches `^[^/@:]+/[^/@:]+@[0-9a-f]+:`. A missing local clone or a missing commit makes the ref `unchecked`, not bad.
8. `contract-refs.sh` checks every ref, the refs in `planned` and `consumers` included, at the commit that the ref names or at `verified_commit`. Execute sets the draft's `verified_commit` from `origin/<base_branch>`, so it is a real commit.
9. `contract-hook.sh` stays silent on any failure. `preflight.sh` is the one place that checks the `yq` version. No CI runs the tests.

## Left to the builder

- The renderer's language: bash with `yq`, or Python that reads `yq -o=json` output. Python is likely simpler for HTML.
- The exact callout and HTML markup.
- How `contract-refs.sh` maps a cross-repository ref to a local clone.
- Test fixtures: rewrite the contract fixtures in YAML. `tests/test_contract_blocks.sh` runs the skill blocks, so it changes with the blocks.

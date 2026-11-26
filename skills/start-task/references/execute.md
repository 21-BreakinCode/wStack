# Execute

Goal: do the work in the spec without the user. Done when you believe the spec is met and `run-log.md` lists every step.

Set `$task_dir`, `$vault`, and `$scripts` as in `SKILL.md`. Change every frontmatter field with `frontmatter-set.sh`. Read the spec first. Its answers settle your questions, so do not ask the user about anything the spec already answers.

## Start

0. If `approved_at` in `spec.md` is empty, nobody approved the spec. Set `status` to `drafting`. Then read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/confirmation.md` and follow it.
1. If `status` is `waiting-user`, read the last item of `stopped_for_user` in `run-log.md`. Go on as "Stop items" in `SKILL.md` says for its `stage`.
2. If `started_at` in `run-log.md` is empty, set it once to `date -u +%Y-%m-%dT%H:%M:%SZ`: `bash "$scripts/frontmatter-set.sh" "$task_dir/run-log.md" started_at <time>`. Never set it again.
3. For a code task, work in `workspace_cwd`. Run `git switch -c wstack/<slug>`, or `git switch wstack/<slug>` if the branch exists. `<slug>` is the task id without its date prefix. Outside herdr, `launch-task.sh` made `workspace_cwd` a worktree already on that branch, so the switch changes nothing. Commit only on that branch. Never commit to the default branch.

## Log

Write one line to `run-log.md` under `## Steps` for each step, each retry, and each stop:

`- <ISO time> <step|retry|stop|pause> <text>`

Use `date -u +%Y-%m-%dT%H:%M:%SZ` for the time. Append the line after the step succeeds.

## Work

Iterate on your own. Test your work as you go.

## Stop before a non-undoable step

A non-undoable step is one the spec lists under `## Non-undoable steps`. A merge, a push to the default branch, a force push, a delete, and a deploy are always non-undoable.

Execute never pushes `wstack/<slug>` and never opens the pull request. The Deliver stage does both. When the spec lists `open a pull request` under `## Deliver targets`, the user's approval of the spec removes the stop of Deliver for those two actions. A merge always asks.

Before a non-undoable step, stop:

1. Write a `stop` line in `run-log.md` with the reason.
2. Append a stop item with `"stage":"execute"` and the reason, as "Stop items" in `SKILL.md` says.
3. Set `status` to `waiting-user` in `spec.md`.
4. Tell the user the step and the reason. Ask for a yes or no. End the reply. Wait.

If the guard hook asks or denies a command, treat it as a non-undoable step and stop the same way.

Stop also when the spec is wrong or unclear. Stop the same way with the reason `spec unclear: <question>`. In step 4, ask the question instead of a yes or no.

## After the user answers a stop

This rule runs the same way when the user answers in the same session and when a resumed task reaches Start step 1.

If the reason starts with `retry_limit`, follow "Retry-limit stop" in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/verify.md` instead.

If the reason starts with `spec unclear`:

- The answer changes the spec: set `status` to `drafting`. Then read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/confirmation.md` and follow it. The changed spec needs a new approval.
- The answer changes nothing in the spec: set `status` to `executing`, write a `step` line with the answer, and go on with the work.

For a stop before a non-undoable step:

- Yes: set `status` to `executing`, write a `step` line, and run the stopped step.
- No: keep `status` as `waiting-user` and ask what to change.

## Retry

When a try fails, write a `retry` line, read `retries` from `run-log.md`, add 1, and set it with `frontmatter-set.sh`. Then try again. Execute and Verify share this one counter, as `verify.md` says. Take the retry limit from the Config list in `SKILL.md`. When `retries` reaches the limit, stop as above with the reason `retry_limit reached`.

## Thinking and ops work

Write the result as a new note in `$vault`. Never overwrite an existing note. If the name is taken, add `-2`, `-3`, and so on. Undo means: delete that note.

## Contract work

Use this for a `contract` task. Execute writes drafts only, in the task folder. No file in the contract folder changes before Deliver.

1. Read `repo`, `workspace_cwd`, and `base_branch` from the spec. The user approved `base_branch` with the spec. `<repository folder>` is `workspace_cwd`.
2. Find the contract folder: `bash "$scripts/contract-path.sh" --vault "$vault" "<repository folder>"`. It prints the contract path. The contract folder is the folder of that path. The file can be missing. If it exits 1, write a `stop` line and append a stop item with the reason `repository not mapped: run /wstack:init-service`, as "Stop items" in `SKILL.md` says. Set `status` to `waiting-user` and stop. If it exits 2, stop the same way with the stderr text as the reason.
3. Run `git -C "<repository folder>" fetch origin "<base_branch>"`. Run `git -C "<repository folder>" rev-parse "origin/<base_branch>"`. Keep the output for step 6. It is `verified_commit`, the code that this task absorbs from. Read the code with `git -C "<repository folder>" ls-tree -r --name-only "origin/<base_branch>"` and `git -C "<repository folder>" show "origin/<base_branch>:<path>"`. Never read the local `HEAD`.
4. If the spec says `project: new`, no code exists yet, so no claim has a ref to cite. The user's answers under `## Contract changes` hold the plan. Write each answer as an item under `planned`: an `id` in kebab case, a `title` that states the answer in one line, and a `why` from the answer. A plan item needs no `refs`. Give each section that needs `sources` the planned globs of its answer line, and leave the `items` of every section empty. Do not read other sources. Go to step 6.
5. If the project exists, read the team docs and the code areas that the spec lists under `## Contract changes`. Read every vault doc in the contract folder too, `docs/` included, on every contract task. Examples are `PRD.md`, `DECISIONS.md`, and the files in `docs/`. Check each claim against the code. Sort each fact:
   - The code shows it is true: it becomes an item in a section of the contract.
   - It is a planned item that the code does not show yet: it becomes an item under `planned`, with an `id` in kebab case, a `title`, and a `why`. If a gotcha is the reason for the plan item, give the gotcha `planned: <id>`. The plan item does not repeat the gotcha text.
   - It is a repository ADR, a file in `docs/adr/` of the repository: add the glob `docs/adr/**` to the `sources` of `team_docs`. Make no decision file for it.
   - It is a choice about the service in a vault decisions file: it becomes one file in `decisions.draft/`.
   - The code contradicts a doc: it goes into `disagreements.md` in step 7, not into the contract.

   The spec choices that set how wStack works, such as `base_branch` and the `ignore` list, are YAML fields, not decision files.
   Before you cite another repository, fetch it. `<clone>` is the local clone of that repository: the `repo_path` in the Service Mapping whose `origin` remote names it, or `<workspace_root>/<repo>`. `<default branch>` is the output of `git -C "<clone>" symbolic-ref --short refs/remotes/origin/HEAD`, without the `origin/` prefix. Run `git -C "<clone>" fetch origin "<default branch>"`. Then cite `<owner>/<repo>@<commit>:path:lines`, where `<commit>` is the output of `git -C "<clone>" rev-parse "origin/<default branch>"`. If the fetch fails, cite the local commit that the same `rev-parse` prints.
6. Write `contract.draft.yaml` from `${CLAUDE_PLUGIN_ROOT}/templates/contract.yaml`. Fill `app_name`, `repo`, `base_branch`, and `tags`. In `tags`, `{{org_kebab}}` is the `<ORG>` folder of the contract path, `01Project/<ORG>/`, in kebab case by the rule of `PREFIX` in Phase 2 of the `create-handover` skill: insert `-` before each uppercase letter except the first, lowercase the result, and collapse repeated `-`. The folder `BreakinCode` gives `breakin-code`, so the tag is `project/breakin-code/<app_name>`. Set `verified_commit` to the SHA from step 3, as a quoted string. Write `summary` in one or two sentences. Keep all seven keys under `sections:`. Give `team_docs`, `abilities`, `interfaces`, and `depends_on` a `sources` list of repo-relative globs. `consumers`, `gotchas`, and `open_questions` have no `sources`. Leave `open_questions` empty, because it holds only what a later task finds. Each item has `text`, one claim in at most 25 words, and `refs`, at least one `path:lines` ref at `verified_commit`. In a flow list, put a ref that holds a comma in double quotes, for example `refs: ["app/main.py:10,40-42"]`, or write `refs` as a block list. A `depends_on` item that names a mapped service has `app` and `mapped_commit`, the `verified_commit` of that service's contract. If the repository holds an OpenAPI document, set `openapi` to its path, and list in `interfaces` only what the document does not show. State only what is true now, in the present tense.
   For an existing project, also fill `diagrams` from the code at `origin/<base_branch>`:
   - `diagrams.flow`: the `parts` are the processes and modules of the service. The `callers` come from `consumers`. The `dependencies` are network services, databases, queues, and storage. Each call is one edge, labeled with its route, topic, or protocol.
   - `diagrams.sequences`: add up to five, one for each key flow.
   - `diagrams.states`: add one state lifecycle for each record with a status field.
   - `diagrams.architecture`: add it only for code with clean, hexagonal, or layered layers. List the layers from outer to inner. Set `sibling: true` on a layer that sits beside the others instead of around them, for example workers that import every layer.
   - Every entry that needs `refs` cites them at `verified_commit`.

   For a new project, keep `diagrams: {}`.
   A rebuild can start from the current contract. If the user undid the last contract task, it can start from the `contract.draft.yaml` of that task. Copy it. Fetch the clone of each repository that a cross-repo ref names, as step 5 says. The script does not fetch. It compares each cross-repo ref with `origin/HEAD` of the clone, which the fetch moves. Then run `bash "$scripts/contract-ref-shift.sh" "<repo>" "<draft>" "<verified_commit of the draft>" "<new verified_commit>" --mapping-from "<contract path>"`. Read again each ref it lists as `changed:`. For each `shift: <ref> -> <new ref>` line, write `<new ref>` in the draft in place of `<ref>`. Write the draft you started from in the run log. The reviewer still judges the whole draft.
7. Write `$task_dir/disagreements.md` with each disagreement from step 5, one line each: `- <doc path>: <what the doc says>. The code: <what the code does> (<ref>)`. If there is no disagreement, do not make the file. Deliver copies it into `report.md`.
8. Write each decision to `decisions.draft/<id>-<slug>.md` from `${CLAUDE_PLUGIN_ROOT}/templates/decision.md`. Fill `{{tasks_dir}}` from `$tasks_dir`. Get the first `<id>` from `bash "$scripts/contract-edit.sh" next-decision-id "<contract folder>/decisions"`. Number the other files after it, so a copy into `decisions/` never overwrites a decision. A decision file holds only a choice about the service that the task made. If there is no decision file, do not make `decisions.draft/`. For a new project, write one file, `<id>-baseline.md`, that records the baseline choices from the answers.
9. A vault doc marked `keep` in `## Vault docs` of the spec stays where it is. Deliver archives each doc marked `archive`.

## Learning tasks

- Input: find and prepare material for the user to read, watch, or study.
- Output: help the user make notes, a blog post, or a talk. Test what the user learned with quizzes, flashcards, or an "explain it back" exercise.

## Panes

If you open a herdr pane for this task, open it in your own workspace with `herdr pane split --current --direction right --no-focus`, and close it before Deliver.

## Finish

When the spec is met, write a `step` line that says so. Set `status` to `verifying`. Then read `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/verify.md` and follow it.

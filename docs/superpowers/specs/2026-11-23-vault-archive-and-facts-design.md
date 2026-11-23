# Vault archive and project facts: design

Status: draft for the user's approval. Target release: wStack 0.6.0, one plan. Sections A to E come first, then F and G. (Claude's call.)

## Intent

The user asked for three changes to the vault layout of wStack.

1. The retro must read every finished task, also a long one. Today `scripts/collect-week.sh:37` selects a task by the start date in its folder name, within the last 7 days. If a task starts 8 or more days before a retro, no retro reads it. A finish in the retro week does not change this.
2. `Tasks/` must show current work. Finished tasks that a retro read move to `Tasks/_archive/<YYYY-Www>/<task_id>/`, where they stay as history.
3. Each project gets a knowledge base of facts. The retro finds a pattern of how the user usually works on a project, and asks the user whether it is a fact. Later RDs of the same project then keep this knowledge. An RD is a task session.

The user also picked a new place for the two HTML pages of a task: `~/.wstack/pages/<task_id>/`, outside the vault.

wStack acts as the tech lead and the user is the final quality gate. Every change here keeps the user in control: nothing moves and no fact is written without the user's answer.

## Goals

- G1. The retro reads each finished task exactly once, whatever its start date.
- G2. After the user agrees, the retro moves each read task to `Tasks/_archive/<week>/<task_id>/`. It uses the Obsidian CLI, so Obsidian updates every link to the moved notes.
- G3. Every lookup of a task folder still works after the move.
- G4. Each project with a contract gets `<app_name>.facts.md` next to its contract. The retro proposes fact candidates, the user answers each one, and the confirmed facts reach every later RD of that project at `Confirmation`.
- G5. `spec.html` and `review.html` live in `~/.wstack/pages/<task_id>/`.
- G7. A code task started outside herdr puts its worktree under the same root as herdr, at `<root>/<repo>/<branch-slug>`, and no longer at `~/.wstack/tasks/<task_id>`.
- G6. `/wstack:board` and its live monitor show the size of the changes of each task. Several tasks can work in the same project, each in its own worktree, and the user sees all their changes in one view.

## Non-goals

- No change to `Retros/` and `Board/`. Their pages stay in the vault. (Claude's call: the user asked only about the task pages.)
- No facts for a repository without a contract. `/wstack:init-service` maps a repository first.
- No Obsidian Base view. The user picked a real move.
- No copy of Claude memory into `<app_name>.facts.md`.
- No migration of the pages of the one existing task. The archive move carries them like any other file.

## Anti-goals

- A broken link in the vault after a move.
- A task split across two folders after a failed move.
- A task moved before the user saw the list.
- A fact that the user never answered reaches an RD.
- A finished task that the retro reads twice, or never.

## Constraints

- Scripts run on `/bin/bash` 3.2 with `set -euo pipefail`. Python scripts use only the standard library and run on Python 3.9.
- Tests never write into `$HOME/Projects/LifeOS/`. Tests that touch `~/.wstack` set `HOME` to a temp folder.
- The `obsidian` CLI talks to the running Obsidian app. It exits 0 even on failure, so its output text decides the result. `scripts/handover/obsidian_cli.py` already wraps it (`run_cli`, `ObsidianCliError`).
- `obsidian move` takes `path=<vault-relative file>` and `to=<destination folder or path>`. A `to=` value that holds a dot is read as a file path (`scripts/handover/archive.py:40`).
- If `alwaysUpdateLinks` is `true` in `<vault>/.obsidian/app.json`, Obsidian updates links on a move. The user's vault has it, and it also has `showUnsupportedFiles: true`.
- The tests cannot run Obsidian.
- Spike results (2026-11-23, user approved, on a scratch folder in LifeOS that the spike deleted):
  - `obsidian move` does not create a missing folder. It prints `Error: ENOENT: ...` and exits 0. After `mkdir -p` of the destination folder, the move works.
  - It moves files that are not notes. A `.html` file and a `.txt` file both moved.
  - It rewrites the links in other notes. A unique name becomes the short form, for example `[[inner]]` and `![[page.html]]`. A name that is not unique, such as `spec`, keeps the full new path.
  - A success prints `Moved: <from> -> <to>`. A failure prints a line that starts with `Error:`. The exit code is always 0.
  - `obsidian vault info=path` prints the path of the vault that the running app has open.
- Text follows `rules/communication.md` (simple English).

## Approaches

### How to move a task folder

| Approach | Trade-off |
|---|---|
| Obsidian CLI move (picked by the user) | Obsidian rewrites every link form. The app must run during the retro. The tests need a fake CLI. |
| Shell move and a link rewrite script | Works with Obsidian closed and in tests. Rewrites only the `[[<tasks_dir>/<id>/` form that wStack writes. A hand-written link in another form breaks. |
| No move, an Obsidian Base view over `Tasks/` | Nothing breaks. The file tree still lists every task. The user wants the folder itself to stay short. |

### Where the task pages live

| Approach | Trade-off |
|---|---|
| `~/.wstack/pages/<task_id>/` (picked by the user) | Off the 1 GB Obsidian Sync quota. The task folder holds text only. The pages exist on one machine. A mobile task still publishes both pages as Claude artifacts. |
| Keep in the task folder | No change. About 380 KB of Sync quota per task. |
| `/tmp/wstack-evidence/<task_id>/page/` | Temporary. macOS clears `/tmp` at reboot. |

### Where the facts live

| Approach | Trade-off |
|---|---|
| `<contract folder>/<app_name>.facts.md` (Claude's proposal, the user did not object) | One folder per project. `contract-path.sh` already maps a repository to it, and `contract-reader` already reads that folder at `Confirmation`. A repository without a contract has no facts. |
| `wStack/FACT/<owner>-<repo>.md` | Works without a contract. A second map from repository to file. |
| Claude memory | Written without the user's answer, not visible in the vault, on one machine only. |

## Design

### A. What the retro reads

`collect-week.sh` drops the date window. It reads each date-prefixed folder at the top level of `Tasks/` and never reads `Tasks/_archive/`.

- A task with `status` `delivered` or `cancelled` and an empty `retro_read` is `finished`. The analyst reads it in full.
- A task with any other `status` is `open`. Its row adds `age_days` from the date in its folder name to `--today`. The analyst uses open tasks for context only, for example to name a task that is stuck.
- A task with a `retro_read` value is not read again.

Each row adds `state` (`finished` or `open`). `templates/spec.md` adds an empty `retro_read:` field.

After the user answers step 8 of the retro, the retro writes `retro_read: <week>` into the `spec.md` of each finished task it read. If the user moves no task, it still writes the mark. A retro that ends before step 8 writes no mark, so the next retro reads those tasks again.

### B. The archive move

Archive candidates are the tasks at the top level of `Tasks/` that have a `retro_read` value. These are the tasks of this retro plus any task that an earlier retro read but did not move.

The step 8 question of the retro adds one part: the candidate task ids, with the answer `all`, `none`, or a list of ids.

A new script moves the tasks that the user named. `<week>` is the retro week, for example `2026-W49`, without a `-2` suffix.

1. Before the first move, the script reads `alwaysUpdateLinks` from `<vault>/.obsidian/app.json`. If it is not `true`, the script moves nothing and prints the reason. Then it runs `obsidian vault info=path`. If that call fails, Obsidian is not running. If it prints a path other than `--vault`, the app has another vault open. In both cases the script moves nothing and prints the reason.
2. For each task, it lists every file in the task folder, subfolders included. It runs `mkdir -p` for each destination folder first, because the CLI does not create folders. For each file it runs `obsidian move path=<vault-relative file> to=<vault-relative destination path>`. Only an output that starts with `Moved:` counts as a success. The destination is `<tasks_dir>/_archive/<week>/<task_id>/` plus the path of the file inside the task folder.
3. If a move fails, the script moves the files of that task that it already moved back to their old paths with the CLI. It reports the task as not moved and goes on with the next task. A task is never left in two folders. If a move back fails, the script stops the whole run. It prints each file path in the old folder and in the archive folder, and exits 1. The retro shows this list to the user. (Claude's call.)
4. When every file of a task is moved, it deletes the empty source folders.
5. It prints one line per task: moved, or not moved with the reason.

The retro writes these lines under a new `## Archived` heading in the retro file. A skipped move is not an error: the tasks stay candidates for the next retro.

The script reads the CLI command from `WSTACK_OBSIDIAN_BIN` and falls back to `obsidian`, so that the tests can use a fake CLI.

### C. Lookups after a move

A new helper `task_dir_of <vault> <tasks_dir> <task_id>` finds a task folder. If `<tasks_dir>/<task_id>` exists, it prints that path. Otherwise it prints the one match of `<tasks_dir>/_archive/*/<task_id>`. If nothing matches, it exits 1.

- `skills/deliver-task/SKILL.md` "Pending items" uses it for the task folder of a merged item (today `$vault/$tasks_dir/<task>`). A delivered task with an open PR can be archived before its PR merges. The pending item stores the task id, not a path, so the helper is enough. (Claude's call: an open PR does not block the archive.)
- `scripts/board.sh` uses it for the finished rows of open workspaces (today `"$vault/$tasks_dir"/????-??-??-"$label"`).
- `scripts/list-open-tasks.sh` loops over `"$vault/$tasks_dir"/*/`, which also matches `_archive/`. It skips `_archive`.
- `/wstack:start-task --task <id>` on an archived task tells the user that the task is archived and gives its path.
- `contract-historian` follows the links in the decision files. Obsidian updates those links on the move, so it needs no change.
- `pause-work`, `resume-work`, and `start-task/references/execute.md` build the task path by hand. They act only on open tasks, which never move, so they need no change.
- If the folder exists, `scripts/new-task-folder.sh` adds a `-2` style suffix. It also treats a task id under `_archive/` as taken, so no two folders share an id. (Claude's call.)

### D. Project facts

File: `<contract folder>/<app_name>.facts.md`, made from a new `templates/facts.md` on the first confirmed fact.

```
---
service: <app_name>
---

## Facts

- F1 Run the full test suite before each commit, never a subset.
  Confirmed 2026-11-30. Evidence: 2026-11-24-board-fix, 2026-11-27-retro-tweak

## Not facts

- Always open a PR for docs-only changes.
  Rejected 2026-11-30.
```

Sources of candidates:

1. `templates/retro-note.md` adds the heading `## Fact candidates`. The RD writes each habit or rule of the user on this project that it learned in this task, with the reason. An example is a correction that the user gave twice.
2. `agents/retro-analyst.md` adds an output block `## Fact candidates`, numbered `C1`, `C2`, and so on. Each candidate names the service, the statement, and the evidence task ids. The analyst takes candidates from the exit notes, from corrections that repeat across tasks, and from the RD answers. It never proposes a statement that is already under `## Facts` or `## Not facts` of that service.

`collect-week.sh` adds `facts_file` to each row. It reads `contract_file` from the frontmatter of the task's `contract-brief.md`. `Confirmation` writes that file for a code or ops task with a contract. `facts_file` is `<app_name>.facts.md` in the folder of `contract_file`. If the task has no `contract-brief.md`, it is `null`. The file need not exist yet.

The step 8 question of the retro adds one part per candidate: `fact`, `not`, or new text. New text counts as `fact` with that text. The retro writes each answer into `<app_name>.facts.md` of that service: a fact gets the next `F` number and the date, and a rejected candidate goes under `## Not facts`. It lists the written lines under a new `## Facts` heading in the retro file.

The retro writes the facts file under the contract lock (`contract-edit.sh lock` and `unlock`). No script globs `*.md` in the contract folder, only `decisions/[0-9][0-9][0-9][0-9]-*.md`, so the facts file does not change the freshness result of the contract. The name `<app_name>.facts.md` keeps two contracts in one folder apart. (Claude's calls.)

Reader: if `<app_name>.facts.md` exists next to the contract, `agents/contract-reader.md` reads it. It copies every line under `## Facts` into the brief, under a new heading `## Project facts`. It uses no filter, because the list is short and each fact applies to every task of the project. `Confirmation` step 1 already reads `contract-brief.md`, so the spec follows the facts. This applies to `code` and `ops` tasks, the same scope as the contract gate.

### E. Task pages

- `Confirmation` step 6 renders the spec page to `~/.wstack/pages/<task_id>/spec.html`. Step 8 gives the user that path.
- `scripts/build-review-page.sh` and the `build-review-page` skill write `~/.wstack/pages/<task_id>/review.html`.
- The mobile publish reads the new paths. Nothing else changes.
- `docs/spec.md` section 6 lists the pages under `~/.wstack/pages/` and no longer in the task folder.

### F. Changes column on the board

The user's herdr configuration now sets `[worktrees] directory = "~/Projects/worktrees"`, so herdr puts each task worktree at `~/Projects/worktrees/<repo>/<branch-slug>`. The tasks of one project then sit in one folder, and herdr groups them under the project workspace. Herdr shows no diff, so the board adds one.

- `scripts/board.sh` adds `changes` to each row. If `workspace_cwd` is a git folder, `changes` is the output of `git -C <workspace_cwd> diff --shortstat <merge base>`, in the short form `4 files +120 -30`. The merge base is `git merge-base HEAD <default branch>`. The default branch is `origin/HEAD`. If that ref is not set, it is `origin/main`.
- The diff compares the merge base with the working tree, so it counts commits and uncommitted changes to tracked files. It does not count untracked files.
- If `workspace_cwd` is empty, is not a git folder, or has no merge base, `changes` is `-`. A git error never stops the board.
- `skills/board/SKILL.md` adds the column `changes` after `last step`. `scripts/board-watch.sh` shows it in each RD line.
- The live monitor refreshes every 3 seconds. The frame time with `changes` stays under the 2000 ms limit of the existing timing test.

### G. One worktree root

Inside herdr, `scripts/launch-task.sh:59` runs `herdr worktree create` without `--path`, so herdr picks the folder. Outside herdr, `launch-task.sh:46` runs `git worktree add` at `~/.wstack/tasks/<task_id>`. This design moves the second case to the herdr root.

- The root comes from the herdr configuration, so the setting lives in one place. The file is `$HERDR_CONFIG_PATH`, or else `~/.config/herdr/config.toml`. The script reads `directory` under `[worktrees]` and expands a leading `~`.
- If the file, the section, or the key is missing, the root is the herdr default `~/.herdr/worktrees`. The same fallback applies to a value that is not an absolute path after the `~` expansion.
- The path is `<root>/<repo>/<branch-slug>`. `<repo>` is the base name of the repository root. `<branch-slug>` follows the herdr rule for the branch `wstack/<slug>`, so a later `herdr worktree open` finds the worktree.
- Claude Code's own worktrees in `<repo>/.claude/worktrees/` do not change, because herdr does not create them.
- Existing worktrees stay where they are. `resume-task.sh` and `board.sh` read `workspace_cwd` from `spec.md`. Only `launch-task.sh` builds the old path. (Claude's call.)
- `docs/spec.md` and the comment at `launch-task.sh:7` name the new path.

## Tests

- `collect-week.sh`:
  - It reads a finished task older than 7 days.
  - It skips a task with `retro_read`.
  - An open task carries `state` and `age_days`.
  - It never reads `_archive/`.
- `list-open-tasks.sh` skips `_archive/`.
- `task_dir_of`: the top-level folder wins, an archived folder is found, and no match exits 1.
- `board.sh`:
  - A finished row finds an archived task.
  - `changes` counts a commit and an uncommitted edit in a temp repository.
  - `changes` is `-` for an empty `workspace_cwd` and for a folder that is not a git folder.
- The archive script with a fake CLI:
  - A full move.
  - A failure in the middle moves the files back.
  - With `alwaysUpdateLinks` false, it moves nothing.
  - With a CLI that does not answer, it moves nothing.
- Text pins in `tests/test_skills.sh` and `tests/test_agents.sh` for the new headings and steps.
- The page paths with `HOME` set to a temp folder.
- `launch-task.sh` outside herdr, with `HERDR_CONFIG_PATH` set to a temp file:
  - A `[worktrees]` directory puts the worktree under that root.
  - A missing key or a relative value falls back to `~/.herdr/worktrees`.

## Open for the builder

- The language of the archive script. `scripts/handover/obsidian_cli.py` is Python, so Python is the likely pick.
- The exact wording of the step 8 question.
- The wait between `mkdir -p` and the first move. The app can need time to see the new folder. The spike waited 2 seconds.
- The herdr rule that turns the branch `wstack/<slug>` into `<branch-slug>`. A spike in the test session `wstack-test` with one `herdr worktree create` shows it.

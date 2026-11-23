# Vault Archive and Project Facts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The retro reads every finished task once, archives read tasks with `obsidian move`, and keeps a per-project facts file that the user approves. Task pages leave the vault, the board shows the size of each task's changes, and worktrees share one root.

**Architecture:** Bash scripts under `scripts/` do the work, and the skills and agents call them. One Python script does the archive move through the existing `scripts/handover/obsidian_cli.py` wrapper. Every task folder lookup that can meet an archived task goes through one helper.

**Tech Stack:** bash 3.2, jq, git, Python 3.9 standard library, the `obsidian` CLI, herdr.

**Spec:** `docs/superpowers/specs/2026-11-23-vault-archive-and-facts-design.md`

## Global Constraints

- Start every script with `#!/usr/bin/env bash` and `set -euo pipefail`. Scripts run on `/bin/bash` 3.2. Quote every path variable.
- Python scripts use only the standard library and run on Python 3.9.
- Tests never write into `$HOME/Projects/LifeOS/`. Tests that touch `~/.wstack` set `HOME` to a temp folder.
- Herdr commands in tests target the test session: `WSTACK_HERDR_SESSION=wstack-test`. Run every `claude -p` with `env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID`.
- Run `bash tests/run-all.sh` before every commit.
- Text follows `rules/communication.md` (simple English).
- No task moves and no fact is written without the user's answer.
- The `obsidian` CLI exits 0 even on failure. Only an output that starts with `Moved:` is a successful move. An output that starts with `Error:` is a failure.
- `obsidian move` does not create folders. Run `mkdir -p` on the destination folder first.
- The archive destination is `<tasks_dir>/_archive/<week>/<task_id>/`. `<week>` is `date -j -f %Y-%m-%d "$today" +%G-W%V`, with no `-2` suffix.
- The facts file of a contract `<dir>/<app_name>.md` is `<dir>/<app_name>.facts.md`.
- Task pages live at `$HOME/.wstack/pages/<task_id>/spec.html` and `$HOME/.wstack/pages/<task_id>/review.html`.

## Review Focus

1. A retro that marks tasks and then fails to move them (Obsidian quits, or the user answers `none`). The marked tasks stay archive candidates for the next retro. Test in Task 3.
2. A task id that exists both at the top level and under `_archive/`. `task_dir_of` prints the top-level folder. Test in Task 1.
3. A fact text with Markdown characters, such as backticks, `#`, or a leading `- `. `facts-add.sh` writes it as given, on one line. A text with a newline exits 1. Test in Task 4.
4. A `workspace_cwd` that no longer exists, because its worktree was removed. The board shows `-` for `changes` and still prints every row. Test in Task 7.
5. A herdr configuration whose `directory` value has single quotes or a trailing `# comment`. The root still resolves. Test in Task 8.

---

### Task 1: Task folder lookup across the archive

**Files:**
- Create: `scripts/lib/task-dir.sh`, `tests/test_task_dir.sh`
- Modify:
  - `docs/spec.md` section 4 layout (list `scripts/lib/task-dir.sh`)
  - `scripts/new-task-folder.sh:44-46` and `scripts/board.sh:130-139`
  - `skills/deliver-task/SKILL.md` ("Pending items", the sentence "The task folder of the item is `$vault/$tasks_dir/<task>`.")
  - `skills/start-task/SKILL.md:73` (task mode)
- Test: `tests/test_task_dir.sh`, `tests/test_list_open_tasks.sh`, `tests/test_new_task_folder.sh`, `tests/test_board.sh`, `tests/test_skills.sh`

**Interfaces:**
- Produces: `task_dir_of <vault> <tasks_dir> <task_id>` in `scripts/lib/task-dir.sh` (sourced, not run). It prints one absolute folder path and returns 0, or prints nothing and returns 1.

- [ ] **Step 1: Write the failing tests**

`tests/test_task_dir.sh` (new) builds `$work/vault/Tasks/` in a temp folder:
```bash
assert "top-level task is found" '[ "$(task_dir_of "$vault" Tasks 2026-11-20-top)" = "$vault/Tasks/2026-11-20-top" ]'
assert "archived task is found" '[ "$(task_dir_of "$vault" Tasks 2026-11-01-old)" = "$vault/Tasks/_archive/2026-W45/2026-11-01-old" ]'
assert "top level wins over the archive" '[ "$(task_dir_of "$vault" Tasks 2026-11-02-both)" = "$vault/Tasks/2026-11-02-both" ]'
assert "a missing task returns 1 and prints nothing" '! task_dir_of "$vault" Tasks 2026-11-03-none && [ -z "$(task_dir_of "$vault" Tasks 2026-11-03-none || true)" ]'
```
`tests/test_list_open_tasks.sh`: an archived folder `Tasks/_archive/2026-W45/2026-11-01-old/spec.md` with `status: executing` is not listed (`! grep -q 2026-11-01-old <<<"$out"`).
`tests/test_new_task_folder.sh`: with `Tasks/_archive/2026-W45/2026-11-01-dup/` present, `--slug dup` makes a folder ending in `-dup-2`.
`tests/test_board.sh`: in the fake herdr setup that already gives a workspace label, the finished row also comes from `Tasks/_archive/<week>/????-??-??-<label>`.
`tests/test_skills.sh`: deliver-task holds `task_dir_of "$vault" "$tasks_dir"`, and start-task task mode holds `is archived`.

- [ ] **Step 2: Run the tests and see them fail**

Run: `bash tests/test_task_dir.sh; bash tests/test_new_task_folder.sh; bash tests/test_board.sh; bash tests/test_skills.sh`
Expected: FAIL on the new rows. The list-open-tasks row already passes: the `[ -f "$folder/spec.md" ]` guard skips `_archive/`. Keep it as a pin.

- [ ] **Step 3: Implement**

- `task_dir_of`: try `<vault>/<tasks_dir>/<task_id>`, then the glob `<vault>/<tasks_dir>/_archive/*/<task_id>`, first existing folder wins.
- `new-task-folder.sh`: a slug is also taken by `$tasks_root/_archive/*/????-??-??-$candidate_slug`, because the branch `wstack/<slug>` can still exist.
- `board.sh` finished rows: loop over both globs, top level first.
- deliver-task "Pending items": source `$scripts/lib/task-dir.sh`, and the task folder of an item is the output of `task_dir_of "$vault" "$tasks_dir" <task>`. No output keeps today's "folder missing" branch.
- start-task task mode: if `$vault/$tasks_dir/<task_id>` does not exist and `task_dir_of` finds it, tell the user that the task is archived, give the path, and stop.

- [ ] **Step 4: Run the tests and see them pass**

Run: `bash tests/run-all.sh`
Expected: `Failed: 0` in every file.

- [ ] **Step 5: Commit** `feat: find task folders in the archive`

### Task 2: The retro reads every finished task once

**Files:**
- Modify: `templates/spec.md`, `scripts/collect-week.sh`, `agents/retro-analyst.md` ("Inputs"), `skills/run-retro/SKILL.md` (steps 2, 3, and the `Tasks read:` line of step 5), `docs/spec.md` (the retro section)
- Test: `tests/test_collect_week.sh`, `tests/test_new_task_folder.sh`, `tests/test_agents.sh`, `tests/test_skills.sh`

**Interfaces:**
- Produces: `collect-week.sh --vault <abs> --tasks-dir <rel> [--today YYYY-MM-DD]`. `--days` is gone. Each row adds `state` (`"finished"` or `"open"`), `age_days` (number, from the folder date to `--today`), and `facts_file` (string or `null`).
- Produces: the empty spec field `retro_read:`.

- [ ] **Step 1: Write the failing tests** in `tests/test_collect_week.sh`, with `--today 2026-11-30`:
```bash
assert "finished task 20 days old is read" 'jq -e ".[] | select(.task_id==\"2026-11-10-long\") | .state==\"finished\"" <<<"$out"'
assert "task with retro_read is skipped" '! jq -e ".[] | select(.task_id==\"2026-11-28-read\")" <<<"$out"'
assert "open task carries state and age_days" 'jq -e ".[] | select(.task_id==\"2026-11-25-open\") | .state==\"open\" and .age_days==5" <<<"$out"'
assert "archive is never read" '! jq -e ".[] | select(.task_id==\"2026-11-01-old\")" <<<"$out"'
assert "facts_file comes from contract-brief.md" 'jq -e ".[] | select(.task_id==\"2026-11-10-long\") | .facts_file==\"$vault/Services/app/app.facts.md\"" <<<"$out"'
assert "no contract-brief.md gives null" 'jq -e ".[] | select(.task_id==\"2026-11-25-open\") | .facts_file==null" <<<"$out"'
```
The `2026-11-10-long` fixture has `contract-brief.md` with `contract_file: <vault>/Services/app/app.md` in its frontmatter. Replace the old date-window rows. `tests/test_new_task_folder.sh` asserts that the new `spec.md` has the key `retro_read`.

- [ ] **Step 2: Run** `bash tests/test_collect_week.sh`. Expected: FAIL on the new rows.

- [ ] **Step 3: Implement**

- `templates/spec.md`: add `retro_read:` after `approved_at:`.
- `collect-week.sh`: keep the date-prefixed glob at the top level. Skip a folder whose spec has a non-empty `retro_read`. `state` is `finished` for `delivered` or `cancelled`, else `open`. If `contract-brief.md` has `contract_file`, `facts_file` is `"${contract_file%.md}.facts.md"`. Update the usage comment.
- `retro-analyst.md` "Inputs": name `state`, `age_days`, and `facts_file`. Open tasks are context only, for example to name a stuck task. A proposal needs at least one finished task as evidence.
- `run-retro`: step 2 passes no `--days`. Step 3 says "no task to read". The step 5 line becomes `Tasks read: <finished count> finished, <open count> open, on <today>.`

- [ ] **Step 4: Run** `bash tests/run-all.sh`. Expected: `Failed: 0`.

- [ ] **Step 5: Commit** `feat: the retro reads every finished task once`

### Task 3: Archive script and archive candidates

**Files:**
- Create: `scripts/archive-tasks.py`, `scripts/archive-candidates.sh`, `tests/fixtures/fake-obsidian.sh`, `tests/test_archive_tasks.sh`
- Modify: `scripts/handover/obsidian_cli.py` (`run_cli`), `docs/spec.md` section 4 layout (list both new scripts)
- Test: `tests/test_archive_tasks.sh`, `tests/test_handover_python.sh`

**Interfaces:**
- Consumes: `run_cli(*args) -> str` and `ObsidianCliError` from `scripts/handover/obsidian_cli.py`.
- Produces: `python3 scripts/archive-tasks.py --vault <abs> --tasks-dir <rel> --week <YYYY-Www> <task_id>...`
  - stdout, one line per task: `moved <task_id> -> <vault-relative destination>` or `not moved <task_id>: <reason>`.
  - Exit 0: every named task was handled. Exit 1: bad input. Exit 3: the pre-check failed and nothing moved (stderr names the reason). Exit 4: a move back failed. The run stops and stdout lists every file path of that task, under `left in old folder:` and `left in archive:`.
- Produces: `bash scripts/archive-candidates.sh --vault <abs> --tasks-dir <rel>` prints the task ids at the top level of `Tasks/` with `status` `delivered` or `cancelled` and a non-empty `retro_read`, one per line, sorted.
- Produces: `run_cli` runs `os.environ.get("WSTACK_OBSIDIAN_BIN", "obsidian")`.

- [ ] **Step 1: Write the fake CLI** `tests/fixtures/fake-obsidian.sh`. It acts on `$FAKE_VAULT`.
  - `vault info=path` prints `$FAKE_VAULT`.
  - `move path=<p> to=<t>`: if `<p>` contains `$FAKE_FAIL_MATCH`, it prints `Error: fake failure`. Otherwise it runs `mv "$FAKE_VAULT/<p>" "$FAKE_VAULT/<t>"`. A failed `mv` prints `Error: ENOENT`, and a good one prints `Moved: <p> -> <t>`.
  - It always exits 0.

- [ ] **Step 2: Write the failing tests** in `tests/test_archive_tasks.sh`. The temp vault has `.obsidian/app.json` with `{"alwaysUpdateLinks": true}`. Set `WSTACK_OBSIDIAN_BIN` to the fake and `WSTACK_ARCHIVE_WAIT=0`.
```bash
assert "full move: spec, html, and subfolder file arrive" '[ -f "$vault/Tasks/_archive/2026-W48/2026-11-20-a/spec.md" ] && [ -f "$vault/Tasks/_archive/2026-W48/2026-11-20-a/review.html" ] && [ -f "$vault/Tasks/_archive/2026-W48/2026-11-20-a/decisions.draft/0001-x.md" ]'
assert "full move: source folder is gone" '[ ! -e "$vault/Tasks/2026-11-20-a" ]'
assert "failure in the middle moves files back" '[ -f "$vault/Tasks/2026-11-20-b/spec.md" ] && [ ! -e "$vault/Tasks/_archive/2026-W48/2026-11-20-b" ] && grep -q "^not moved 2026-11-20-b: " <<<"$out"'
assert "the next task still moves after a failure" 'grep -q "^moved 2026-11-20-c -> " <<<"$out"'
assert "failed move back exits 4 and lists the files" '[ "$rc_back" = 4 ] && grep -q "left in old folder:" <<<"$out_back" && grep -q "left in archive:" <<<"$out_back"'
assert "alwaysUpdateLinks false exits 3 and moves nothing" '[ "$rc_links" = 3 ] && [ -d "$vault2/Tasks/2026-11-20-a" ]'
assert "another open vault exits 3 and moves nothing" '[ "$rc_vault" = 3 ] && [ -d "$vault3/Tasks/2026-11-20-a" ]'
assert "an open task is not moved" 'grep -q "^not moved 2026-11-20-open: status executing" <<<"$out"'
assert "candidates: marked delivered task, also when not moved" '[ "$(bash "$repo/scripts/archive-candidates.sh" --vault "$vault" --tasks-dir Tasks)" = "2026-11-20-b" ]'
```
  - For the failed move back, set `FAKE_FAIL_MATCH` to a file name that the task has in its second file. Also make the fake fail any move whose `path=` starts with `Tasks/_archive/`.
  - For another open vault, point `FAKE_VAULT` at another folder.

- [ ] **Step 3: Run** `bash tests/test_archive_tasks.sh`. Expected: FAIL, because the scripts do not exist.

- [ ] **Step 4: Implement**

- `archive-tasks.py`: put `scripts/handover` on `sys.path` and import `run_cli` and `ObsidianCliError`.
  - Pre-check, which exits 3 on failure: `alwaysUpdateLinks` is `true` in `<vault>/.obsidian/app.json`, and the stripped output of `run_cli("vault", "info=path")` equals `os.path.realpath(vault)`.
  - Each task: it must exist at the top level with status `delivered` or `cancelled`, and its destination must not exist. Otherwise report `not moved <id>: <reason>`.
  - List the files with `os.walk` in sorted order. `os.makedirs(..., exist_ok=True)` each destination folder, then sleep `float(os.environ.get("WSTACK_ARCHIVE_WAIT", "2"))` once per task.
  - Move with `run_cli("move", f"path={rel}", f"to={dest_rel}")`, and accept only output that starts with `Moved:`. On a failure, move the files already moved back in reverse order. If a move back fails, print the two lists and exit 4.
  - After a full move, delete the empty source folders, deepest first.
- `obsidian_cli.py`: the one-line `WSTACK_OBSIDIAN_BIN` change. `tests/test_handover_python.sh` keeps passing.
- `archive-candidates.sh`: source `scripts/lib/frontmatter.sh`, loop over the date-prefixed top-level folders, and use `fm_get`.

- [ ] **Step 5: Run** `bash tests/run-all.sh`. Expected: `Failed: 0`.

- [ ] **Step 6: Commit** `feat: archive read tasks with obsidian move`

### Task 4: Project facts file and its readers

**Files:**
- Create: `templates/facts.md`, `scripts/facts-add.sh`, `tests/test_facts_add.sh`
- Modify:
  - `templates/retro-note.md`, and each skill line that lists the note headings (`grep -rn "Surprises" skills`)
  - `agents/retro-analyst.md` and `agents/contract-reader.md` ("Reply")
  - `skills/start-task/references/confirmation.md` (G5, and step 1 of "Write the spec")
  - `docs/spec.md`, including the section 4 layout (list `scripts/facts-add.sh` and `templates/facts.md`)
- Test: `tests/test_facts_add.sh`, `tests/test_agents.sh`, `tests/test_skills.sh`

**Interfaces:**
- Consumes: `contract-edit.sh lock <contract_file>` and `contract-edit.sh unlock <contract_file>`.
- Produces: `bash scripts/facts-add.sh <facts_file> <fact|not> <YYYY-MM-DD> <evidence> <text>`.
  - It locks `${facts_file%.facts.md}.md`. If the file is missing, it makes it from `templates/facts.md`. `service:` is the base name without `.facts.md`.
  - `fact` appends `- F<n> <text>` and `  Confirmed <date>. Evidence: <evidence>` at the end of `## Facts`. `<n>` is the highest `F` number plus 1.
  - `not` appends `- <text>` and `  Rejected <date>.` at the end of `## Not facts`.
  - It prints the first written line. Exit 0: written. Exit 1: bad input (empty text, a newline in any value, a bad kind or date). Exit 2: the lock is busy or the folder is missing.
- Produces: the analyst reply block `## Fact candidates`, each entry in this form:
```
### C<n> <service>
- Statement: <one line>
- Evidence: <task ids>
- Facts file: <facts_file>
```
- Produces: the contract-reader reply section `### Project facts`, after `### Plan items` and before `=== PATCH ===`. It holds every line under `## Facts` of the facts file, or `None`.

- [ ] **Step 1: Write the failing tests** in `tests/test_facts_add.sh`, with a temp `Services/app/app.md`:
```bash
assert "first fact makes the file as F1" 'grep -qx -- "- F1 Run the full suite" "$dir/app.facts.md" && grep -qx "service: app" "$dir/app.facts.md"'
assert "second fact is F2 under Facts" 'awk "/^## Facts/{f=1} /^## Not facts/{f=0} f" "$dir/app.facts.md" | grep -q -- "- F2 "'
assert "not goes under Not facts with the date" 'awk "/^## Not facts/{f=1} f" "$dir/app.facts.md" | grep -qx "  Rejected 2026-11-30."'
assert "markdown text is kept as given" 'grep -qF -- "- F3 Use \`jq\` # not sed" "$dir/app.facts.md"'
assert "a newline in the text exits 1" '! bash "$script" "$dir/app.facts.md" fact 2026-11-30 t1 "$(printf "a\nb")"'
assert "a busy lock exits 2" '[ "$rc_lock" = 2 ]'
```
`tests/test_agents.sh`: contract-reader holds `.facts.md` and `### Project facts`, and retro-analyst holds `## Fact candidates` and `Facts file:`. `tests/test_skills.sh`: G5 in `confirmation.md` holds `### Project facts`. The note template has `## Fact candidates`.

- [ ] **Step 2: Run** `bash tests/test_facts_add.sh`. Expected: FAIL.

- [ ] **Step 3: Implement** the script and the text changes.
  - The RD note heading `## Fact candidates`: a habit or rule of the user on this project that the RD learned in this task, with the reason.
  - The analyst reads `## Fact candidates` of each note. If `facts_file` exists, it reads that file too. It proposes a candidate only for a task with a non-null `facts_file`, and never repeats a line under `## Facts` or `## Not facts`.
  - G5 in `confirmation.md` copies `### Project facts` into `contract-brief.md`. Step 1 of "Write the spec" says that the spec follows the project facts.

- [ ] **Step 4: Run** `bash tests/run-all.sh`. Expected: `Failed: 0`.

- [ ] **Step 5: Commit** `feat: keep confirmed project facts next to the contract`

### Task 5: Retro marks, facts answers, and the archive step

**Files:**
- Modify: `skills/run-retro/SKILL.md` (steps 4, 5, 7, 8, and "After the user picks"), `docs/spec.md`, `README.md` (the retro lines)
- Test: `tests/test_skills.sh`

**Interfaces:**
- Consumes: `collect-week.sh` rows (Task 2), `archive-candidates.sh` and `archive-tasks.py` (Task 3), and `facts-add.sh` with the `## Fact candidates` block (Task 4).

- [ ] **Step 1: Write the failing pins** in `tests/test_skills.sh` for run-retro. They hold:
  - `fm_set` with `retro_read`
  - `archive-candidates.sh` and `archive-tasks.py` with `--week "$week"`
  - `facts-add.sh`
  - the headings `## Archived` and `## Facts`
  - the answer words `fact`, `not`, `all`, and `none`

- [ ] **Step 2: Run** `bash tests/test_skills.sh`. Expected: FAIL on the new pins.

- [ ] **Step 3: Write the skill text**
  - Step 4 keeps the analyst's `## Fact candidates` block as `$candidates`.
  - Step 7 lists each candidate.
  - Step 8 adds two parts to the one question. The first is the archive candidates: the finished tasks of `$data` plus the output of `archive-candidates.sh`, with the answer `all`, `none`, or ids. The second is one answer per candidate: `fact`, `not`, or new text. No answer for a candidate leaves it unwritten.
  - "After the user picks" starts with three steps, before the proposals apply:
    1. `fm_set "<folder>/spec.md" retro_read "$week"` for each finished task in `$data`.
    2. `facts-add.sh` for each answered candidate. The evidence is the candidate's task ids, and the date is `$today`. Write each printed line under `## Facts` in the retro file.
    3. `python3 "$scripts/archive-tasks.py" --vault "$vault" --tasks-dir "$tasks_dir" --week "$week" <ids>` for the named tasks. Write its stdout under `## Archived`. Exit 3 writes `Archive: skipped, <stderr>`. Exit 4 shows the file lists to the user and writes them under `## Archived`.
  - Render the page again after these steps, as step 6 does.

- [ ] **Step 4: Run** `bash tests/run-all.sh`. Expected: `Failed: 0`.

- [ ] **Step 5: Commit** `feat: the retro marks, archives, and writes facts after the user answers`

### Task 6: Task pages outside the vault

**Files:**
- Modify: `skills/start-task/references/confirmation.md` (steps 6 to 8), `scripts/build-review-page.sh` (new required `--page <abs>`), `skills/build-review-page/SKILL.md` (steps 3 and 4), `skills/start-task/references/verify.md:21`, `docs/spec.md` (section 6 tree and line 493)
- Test: `tests/test_build_review_page.sh`, `tests/test_skills.sh`

**Interfaces:**
- Produces: `build-review-page.sh --task-dir <abs> --work-dir <abs> --page <abs>`. It writes the page to `--page` and makes its folder. It never writes `review.html` into the task folder.

- [ ] **Step 1: Write the failing tests.**
  - `tests/test_build_review_page.sh` passes `--page "$HOME/.wstack/pages/<id>/review.html"`, with `HOME` set to the test temp folder. It asserts that the page is there and that `$task/review.html` does not exist.
  - A missing `--page` exits 2.
  - `tests/test_skills.sh` pins `$HOME/.wstack/pages/` in `confirmation.md` and in the build-review-page skill.
- [ ] **Step 2: Run** `bash tests/test_build_review_page.sh`. Expected: FAIL. If only the known jsDelivr diagram checks fail, run it once more.
- [ ] **Step 3: Implement.** Step 6 of `confirmation.md` runs `mkdir -p "$HOME/.wstack/pages/<task_id>"` and renders to `$HOME/.wstack/pages/<task_id>/spec.html`. Steps 7 and 8 use that path. The review page skill passes `--page "$HOME/.wstack/pages/<task_id>/review.html"`, and its exit 0 text and mobile `$page` use it.
- [ ] **Step 4: Run** `bash tests/run-all.sh`. Expected: `Failed: 0`.
- [ ] **Step 5: Commit** `feat: keep task pages in ~/.wstack/pages`

### Task 7: Changes column on the board

**Files:**
- Modify: `scripts/board.sh` (`row_json`), `scripts/board-watch.sh` (`print_frame`), `skills/board/SKILL.md` (step 2 columns), `docs/spec.md`, `README.md` (the board lines)
- Test: `tests/test_board.sh`, `tests/test_board_watch.sh`

**Interfaces:**
- Produces: the row field `changes`, a string. It is `"<n> files +<ins> -<del>"`, or `"-"`.

- [ ] **Step 1: Write the failing tests** in `tests/test_board.sh`. The temp repo has a bare `origin`, `main` pushed, and a task branch with one commit (2 files: +3, -1) and one uncommitted edit (+1, -0) to a tracked file:
```bash
assert "changes counts commits and uncommitted edits" '[ "$(jq -r "select(.task_id==\"$id\") | .changes" <<<"$rows")" = "2 files +4 -1" ]'
assert "empty workspace_cwd gives -" '[ "$(jq -r "select(.task_id==\"$id_empty\") | .changes" <<<"$rows")" = "-" ]'
assert "missing folder gives - and the board goes on" '[ "$(jq -r "select(.task_id==\"$id_gone\") | .changes" <<<"$rows")" = "-" ]'
assert "a folder that is not git gives -" '[ "$(jq -r "select(.task_id==\"$id_plain\") | .changes" <<<"$rows")" = "-" ]'
```
`tests/test_board_watch.sh`: the RD line holds `changes:`. The existing timing test (2000 ms) stays.

- [ ] **Step 2: Run** `bash tests/test_board.sh`. Expected: FAIL.

- [ ] **Step 3: Implement** `changes_of <dir>` in `board.sh`, used by `row_json` with the spec's `workspace_cwd`.
  - The base ref is `git -C <dir> rev-parse --abbrev-ref origin/HEAD`, or else `origin/main`.
  - Run `git -C <dir> diff --shortstat "$(git -C <dir> merge-base HEAD <base ref>)"`. Turn ` 2 files changed, 4 insertions(+), 1 deletion(-)` into `2 files +4 -1`. A missing part is `0`, and an empty diff is `0 files +0 -0`.
  - Any git failure gives `-`.
  - The board skill lists `changes` after `last step`. `board-watch.sh` adds `changes:\(.changes)` to the first line of each RD.

- [ ] **Step 4: Run** `bash tests/run-all.sh`. Expected: `Failed: 0`.

- [ ] **Step 5: Commit** `feat: show the size of each task's changes on the board`

### Task 8: One worktree root outside herdr

**Files:**
- Modify: `scripts/launch-task.sh` (header lines 6-7 and lines 41-48), `docs/spec.md`
- Test: `tests/test_launch_task.sh`

**Interfaces:**
- Produces: outside herdr, the code task worktree is at `<root>/<repo>/<branch-slug>`. `<repo>` is the base name of `git -C "$repo_path" rev-parse --show-toplevel`. `<root>` comes from the herdr configuration.

- [ ] **Step 1: Spike the herdr branch slug.** In the test session, run `herdr --session wstack-test worktree create --cwd <temp repo> --branch wstack/demo-task --no-focus`. Read `.result.worktree.path`, then remove the worktree with `herdr --session wstack-test worktree remove --workspace <id>`. Write the rule into the task report (for example, `/` becomes `-`, which gives `wstack-demo-task`). If the test session cannot start, use `${branch//\//-}` and say so in the report.

- [ ] **Step 2: Write the failing tests** in `tests/test_launch_task.sh`, outside herdr, with `HOME` and `HERDR_CONFIG_PATH` set to temp paths:
```bash
assert "configured root holds the worktree" '[ "$(fm_get "$task/spec.md" workspace_cwd)" = "$tmp/wt/<repo>/<slug from step 1>" ] && [ -e "$tmp/wt/<repo>/<slug from step 1>/.git" ]'
assert "missing key falls back to ~/.herdr/worktrees" '[[ "$(fm_get "$task2/spec.md" workspace_cwd)" == "$HOME/.herdr/worktrees/"* ]]'
assert "relative value falls back" '[[ "$(fm_get "$task3/spec.md" workspace_cwd)" == "$HOME/.herdr/worktrees/"* ]]'
assert "single quotes and a trailing comment resolve" '[[ "$(fm_get "$task4/spec.md" workspace_cwd)" == "$tmp/wt2/"* ]]'
```
The configuration lines are `directory = "<tmp>/wt"`, no `[worktrees]` section, `directory = "rel/wt"`, and `directory = '<tmp>/wt2' # note`.

- [ ] **Step 3: Run** `bash tests/test_launch_task.sh`. Expected: FAIL.

- [ ] **Step 4: Implement** `herdr_worktree_root` in `launch-task.sh`.
  - Read `${HERDR_CONFIG_PATH:-$HOME/.config/herdr/config.toml}` with awk, and take the `directory` key inside `[worktrees]` only.
  - Strip one pair of `"` or `'` and any trailing `# ...`, and expand a leading `~` to `$HOME`.
  - A value that is not absolute gives `$HOME/.herdr/worktrees`.
  - Replace `session_cwd="$HOME/.wstack/tasks/$task_id"` for code tasks with the new path. The `mkdir -p` goes to `<root>/<repo>`. Leave the non-code `cwd="$HOME/.wstack/tasks/$task_id"` at line 64 as it is.

- [ ] **Step 5: Run** `bash tests/run-all.sh`. Expected: `Failed: 0`.

- [ ] **Step 6: Commit** `feat: put outside-herdr worktrees under the herdr root`

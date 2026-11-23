# Board and RD Retro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give wStack a board of open RDs and a list of session ids per task. Each RD writes an exit note. The retro audits transcripts, and where the evidence raises a question, it reopens a fork of that RD.

**Architecture:** Bash scripts do every count and lookup (`session-id-add.sh`, `session-tokens.sh`, `transcript-stats.sh`, `board.sh`). Skill text tells the RD and the retro at which step to call them. Transcripts are found by session id under `~/.claude/projects/*/`, so no path is stored.

**Tech Stack:** bash 3.2, jq, herdr CLI, Claude Code CLI (`claude -p --resume --fork-session --tools`), Markdown skills.

**Spec:** `docs/superpowers/specs/2026-11-23-board-and-rd-retro-design.md`

## Global Constraints

- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`, runs on `/bin/bash` 3.2, and quotes every path variable.
- Run every test and every `claude -p` with `env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID`. Herdr calls in tests use the fake `tests/fixtures/bin/herdr` or `WSTACK_HERDR_SESSION=wstack-test`.
- Tests never write into `$HOME/Projects/LifeOS/`. Tests that touch `~/.wstack` or `~/.claude` set `HOME` to a temp folder.
- Run `bash tests/run-all.sh` before every commit.
- Skills name bundled files only as `${CLAUDE_PLUGIN_ROOT}/...`.
- `${CLAUDE_SESSION_ID}` is replaced only in the text of an invoked skill. A file read by path keeps the literal text. So the session-id step lives in `skills/start-task/SKILL.md` itself.
- All text (skills, docs, comments, commits) follows the simple-english rules. The lint hook skips `.claude` paths. In a worktree, lint the files by hand.
- Frontmatter lists are inline JSON on one line (`session_ids: ["<uuid>", "<uuid>"]`), read with `fm_get` and written with `fm_set` from `scripts/lib/frontmatter.sh`.
- Old task folders have no `session_ids`, no `subagent_tokens`, and no `retro-note.md`. Every script and skill step falls back to today's behavior for them.
- New CHANGELOG bullets use `- **type:** text`. Agents do not touch `CHANGELOG.md` or any version number.

## Review Focus

1. A task folder made before this release: `collect-week.sh`, `board.sh`, `session-tokens.sh`, and `resume-task.sh` work on it with no error and no new field required. Pinned in Tasks 1, 2, 3, 6.
2. `${CLAUDE_SESSION_ID}` arrives unreplaced (the literal text): `session-id-add.sh` stores nothing and exits 3. Pinned in Task 1.
3. Two sessions in one project folder (a contract task runs in the repository root, next to the user's own session): counts for one id never include the other. Pinned in Tasks 2 and 3.
4. herdr is missing, or `herdr agent get <slug>` fails: the board shows `n/a` or `none` and still prints every task. Pinned in Task 6.
5. The board's close action meets a worktree with uncommitted changes: it skips that workspace and says why. Pinned in Task 6.

---

### Task 1: Session id list

**Files:**
- Create: `scripts/session-id-add.sh`
- Modify: `templates/spec.md`, `skills/start-task/SKILL.md` (Work mode), `scripts/resume-task.sh`, `docs/spec.md` (6.1)
- Test: `tests/test_session_id_add.sh`, `tests/test_resume_task.sh`, `tests/test_skills.sh`

**Interfaces:**
- Produces: `session-id-add.sh <spec.md> <session id>`. Exit 0 added or already present, 1 bad input (no file), 3 the id is not a UUID (for example the literal `${CLAUDE_SESSION_ID}`). It writes `session_ids` as an inline JSON list with the new id last. Later tasks read the list with `fm_get "$spec" session_ids | jq -r '.[]'`.
- Produces: frontmatter field `session_ids: []` in `templates/spec.md`, after `workspace_cwd:`.

- [ ] **Step 1: Write the failing tests** in `tests/test_session_id_add.sh` (use `tests/_assert.sh`, a temp folder, a spec copied from `templates/spec.md` with the placeholders filled):
  - `adds the first id`: after `session-id-add.sh "$spec" 0f8fad5b-d9cb-469f-a165-70867728950e`, `fm_get "$spec" session_ids` is `["0f8fad5b-d9cb-469f-a165-70867728950e"]`.
  - `appends a second id last` and `skips a duplicate`: adding the first id again leaves 2 items in the same order.
  - `literal placeholder exits 3`: `session-id-add.sh "$spec" '${CLAUDE_SESSION_ID}'` exits 3 and the list is unchanged.
  - `upper case or short ids exit 3`: `ABC`, and a 35-character string, exit 3.
  - `old spec with no field`: a spec without `session_ids:` gets the field with one id, and its other fields are unchanged.
  - `missing file exits 1`.
- [ ] **Step 2: Run** `env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID bash tests/test_session_id_add.sh`. Expected: FAIL, the script does not exist.
- [ ] **Step 3: Implement `scripts/session-id-add.sh`.** Accept only `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`. Build the new list with `jq -c --arg id "$id" '(. // []) + [$id] | unique_by(.) as $u | ...'` or any jq that keeps first-seen order and drops duplicates. An empty or missing value reads as `[]`.
- [ ] **Step 4: Add `session_ids: []`** to `templates/spec.md` after `workspace_cwd:`. Check that `tests/test_new_task_folder.sh` still passes.
- [ ] **Step 5: start-task Work mode.** Insert a new step 1 before the status read, and renumber:

```
1. Record this session on the task: `bash "$scripts/session-id-add.sh" "$task_dir/spec.md" "${CLAUDE_SESSION_ID}"`. If it exits 3, write a `step` line in `run-log.md`: `session id not available`. Go on in both cases.
```

  Add a `tests/test_skills.sh` assertion that the Work mode section holds the literal text `session-id-add.sh "$task_dir/spec.md" "${CLAUDE_SESSION_ID}"` and that this line comes before the `fm_get "$task_dir/spec.md" status` line.
- [ ] **Step 6: Restart by id in `resume-task.sh`.** For a task with at least one id in `session_ids`, the restart uses `--resume <last id>` instead of `--continue`. Add a test row to `tests/test_resume_task.sh`: with `session_ids: ["0f8fad5b-d9cb-469f-a165-70867728950e","1b4e28ba-2fa1-11d2-883f-0016d3cca427"]`, the fake herdr log has `agent start ... --resume 1b4e28ba-2fa1-11d2-883f-0016d3cca427`. Keep the existing `--continue` row for a spec with `session_ids: []` and for one with no field.
- [ ] **Step 7: `docs/spec.md` 6.1.** Add `session_ids:` to the `spec.md` block with the comment `# every Claude session that worked on the task, newest last`.
- [ ] **Step 8: Run** `bash tests/run-all.sh` with the HERDR variables unset. Expected: all pass.
- [ ] **Step 9: Commit** `feat: record every session id of a task`.

### Task 2: Token count by session id

**Files:**
- Modify: `scripts/session-tokens.sh`, `templates/run-log.md`, `skills/deliver-task/SKILL.md` (Finish step 5), `docs/spec.md` (6.1)
- Test: `tests/test_session_tokens.sh`

**Interfaces:**
- Consumes: `session_ids` from Task 1.
- Produces: `session-tokens.sh --session <id> [--session <id>]...` prints two lines: the main-transcript total of those ids, then the subagent total. If no subagent file exists, the subagent total is `0`. It finds `~/.claude/projects/*/<id>.jsonl` and `~/.claude/projects/*/<id>/subagents/*.jsonl`. If no main transcript is found for any id, it exits 2 with no output. `session-tokens.sh <cwd>` keeps its old one-line behavior.
- Produces: frontmatter field `subagent_tokens:` in `templates/run-log.md`, after `tokens_used:`.

- [ ] **Step 1: Write the failing tests** in `tests/test_session_tokens.sh` (same `HOME` temp pattern as the existing rows):
  - Two sessions in one project folder: `aaaaaaaa-...` (100 tokens) and `bbbbbbbb-...` (10 tokens). `--session <aaaa id>` prints `100` then `0`.
  - Two ids in two project folders, summed: `--session <a> --session <c>` prints the sum.
  - Subagents: `<a>/subagents/agent-x.jsonl` with 7 tokens makes line 2 `7`, and line 1 stays `100`.
  - A repeated message id inside a subagent file counts once.
  - An unknown id exits 2 with no output.
  - The existing `<cwd>` rows still pass unchanged.
- [ ] **Step 2: Run** `bash tests/test_session_tokens.sh`. Expected: the new rows FAIL.
- [ ] **Step 3: Implement** the `--session` mode in `scripts/session-tokens.sh`. Reuse the existing jq total (group by `message.id`, last line wins) for each file set. If an id does not match the Task 1 UUID pattern, exit 2.
- [ ] **Step 4: Deliver Finish step 5.** Replace it with: if `session_ids` is not empty, run `bash "$scripts/session-tokens.sh"` with one `--session <id>` per id. Set `tokens_used` to line 1 and `subagent_tokens` to line 2. Otherwise run the old `<workspace_cwd>` form and leave `subagent_tokens` empty. Keep the exit 2 rule (`tokens_used not available`).
- [ ] **Step 5: Templates and docs.** Add `subagent_tokens:` to `templates/run-log.md` and to the `run-log.md` block in `docs/spec.md` 6.1, with the comment `# tokens of the subagents of the task's sessions; tokens_used counts only the main sessions`.
- [ ] **Step 6: Run** `bash tests/run-all.sh`. Expected: all pass.
- [ ] **Step 7: Commit** `feat: count tokens by session id, with subagents apart`.

### Task 3: Transcript stats in the week data

**Files:**
- Create: `scripts/transcript-stats.sh`, `tests/fixtures/transcripts/` (small jsonl files)
- Modify: `scripts/collect-week.sh`
- Test: `tests/test_transcript_stats.sh`, `tests/test_collect_week.sh`

**Interfaces:**
- Consumes: the transcript lookup rule of Task 2 (`~/.claude/projects/*/<id>.jsonl` and `<id>/subagents/*.jsonl`).
- Produces: `transcript-stats.sh <id>...` prints one JSON object:

```json
{"sessions": 2, "found": 2,
 "tool_calls": {"Bash": 12, "Read": 4},
 "tool_errors": 1,
 "top_bash": [{"command": "git status", "count": 5}],
 "compactions": 1, "user_turns": 6,
 "started_at": "2026-11-22T10:20:00Z", "ended_at": "2026-11-22T11:12:00Z",
 "subagent_tool_calls": {"Read": 9}}
```

  Rules: `tool_calls` counts `tool_use` items in `.message.content[]` of main transcripts. `tool_errors` counts `tool_result` items with `is_error == true`. `top_bash` takes the first two words of each Bash `input.command`, the 10 most common, ties by name. `compactions` counts lines with `type == "system"` and `subtype == "compact_boundary"`. `user_turns` counts `type == "user"` lines whose content holds no `tool_result` and that are not `isMeta` or `isCompactSummary`. Times come from the `timestamp` fields. An id with no transcript adds to `sessions` but not to `found`. Exit 0 always for valid ids, exit 1 for a non-UUID argument.
- Produces: in `collect-week.sh` output, each task object gets `has_retro_note` (true or false) and `transcript_stats`. If `spec.session_ids` is empty or missing, `transcript_stats` is `null`.

- [ ] **Step 1: Write fixtures** under `tests/fixtures/transcripts/`. They cover these lines:
  - two Bash calls with the same first two words, and one Read
  - one error result and one compact boundary
  - one meta user line and one real user line
  - one subagent file with one Read
- [ ] **Step 2: Write the failing tests** in `tests/test_transcript_stats.sh`: copy the fixtures into `$HOME/.claude/projects/<two folders>/` in a temp `HOME`, then assert each field of the object above against the fixture counts, plus three rows. An unknown id gives `"found": 0`. A non-UUID argument exits 1. Of two sessions in one folder, only the given ids are counted.
- [ ] **Step 3: Run** both test files. Expected: FAIL.
- [ ] **Step 4: Implement `scripts/transcript-stats.sh`** with one `jq -s` pass over the found files.
- [ ] **Step 5: `collect-week.sh`.** Add `has_retro_note` and `transcript_stats`. Add rows to `tests/test_collect_week.sh`: a fixture task with `retro-note.md` reads `true`, the old fixtures read `false` and `null`.
- [ ] **Step 6: Run** `bash tests/run-all.sh`. Expected: all pass.
- [ ] **Step 7: Commit** `feat: add transcript stats to the retro week data`.

### Task 4: Exit note and RD panes rule

**Files:**
- Create: `templates/retro-note.md`
- Modify: `skills/deliver-task/SKILL.md` (Finish), `skills/start-task/references/verify.md` (retry-limit Cancel), `skills/start-task/references/execute.md`, `docs/spec.md` (section 6 file list, 7.3)
- Test: `tests/test_skills.sh` (or the block test file that already pins the deliver-task and `verify.md` text)

**Interfaces:**
- Produces: `retro-note.md` in the task folder, shaped as design B2, with frontmatter `task_id` and `written_at`. Task 5 reads its five `##` sections by name.

- [ ] **Step 1: Write the failing assertions:**
  - `templates/retro-note.md` has the frontmatter keys `task_id` and `written_at` and the five headings `## Slow or repeated steps`, `## Would script`, `## Spec gaps`, `## Tool and guard friction`, `## Surprises`, in that order.
  - deliver-task Finish has a step that writes `retro-note.md` from `${CLAUDE_PLUGIN_ROOT}/templates/retro-note.md`, and that step comes before the step that sets `status` to `delivered`.
  - The `verify.md` retry-limit `Cancel:` writes `retro-note.md` before it sets `status` to `cancelled`. The other `Cancel:` line (missing file or tool) stays as it is.
  - execute.md holds `herdr pane split --current` and `close it before Deliver`.
- [ ] **Step 2: Run** the test file. Expected: FAIL.
- [ ] **Step 3: Write the template and the skill text.** The Finish step text states the B3 and B4 rules. Each bullet names its evidence: a `run-log.md` line, a file and line, or a command. A section with nothing to say holds `None.` The text also says what each of the three main sections holds. Use the exact `written_at` command `date -u +%Y-%m-%dT%H:%M:%SZ`.
- [ ] **Step 4: execute.md rule (design E1):** one short paragraph: if you open a herdr pane for this task, open it in your own workspace with `herdr pane split --current --direction right --no-focus`, and close it before Deliver.
- [ ] **Step 5: docs/spec.md.** Add `retro-note.md  Deliver: the RD's exit note for the retro` to the section 6 file list, and one line in 7.3 for the pane rule.
- [ ] **Step 6: Lint** the changed Markdown files by hand with the simple-english hook (see Global Constraints). Fix every new hit.
- [ ] **Step 7: Run** `bash tests/run-all.sh`. Expected: all pass.
- [ ] **Step 8: Commit** `feat: the RD writes an exit note, and its panes stay in its workspace`.

### Task 5: Retro audit and targeted reopen

**Files:**
- Modify: `agents/retro-analyst.md`, `skills/run-retro/SKILL.md`, `docs/spec.md` (section 13)
- Test: `tests/test_agents.sh`, `tests/test_skills.sh`
- Spike notes: write results to the task report, not to the repo.

**Interfaces:**
- Consumes: `has_retro_note`, `transcript_stats`, and `spec.session_ids` from Task 3, and the `retro-note.md` sections from Task 4.
- Produces: the analyst reply can end with a `## Questions` block of `### Q<n> <task id>` entries, each with `- Evidence:` and `- Question:` lines. The retro file gets `## RD answers`.

- [ ] **Step 1: Spike, before any text change.** In a temp folder outside every repository, with the HERDR variables unset, check design "Check first" items 2 to 5:
  1. `claude -p --session-id <uuid> "Remember the word PINEAPPLE. Reply OK."`, then `claude -p --resume <uuid> --fork-session --tools Read,Grep,Glob "Which word did I ask you to remember?"` answers PINEAPPLE, and the line count of `<uuid>.jsonl` is the same before and after the fork.
  2. Remove the temp folder, create it again empty, and run the fork again from there. Record whether it works.
  3. In the fork, ask it to create a file. Record that it cannot (no Write or Bash tool).
  4. Record the subagent folder layout seen in `~/.claude/projects/` for one session that used the Agent tool (this session's folder is fine to read, read only).
  Write the commands and outputs to the task report. If item 1 fails, stop and report BLOCKED with the output.
- [ ] **Step 2: Write the failing assertions:**
  - retro-analyst.md names `retro-note.md`, `transcript_stats`, and `## Questions`. It says that a task with an empty `session_ids` gets no question.
  - run-retro has a section `## Ask the RDs`. It comes after the analyst dispatch (step 4) and before the retro file is written (step 5). It holds `--fork-session`, `--tools Read,Grep,Glob`, and `env -u HERDR_ENV`.
  - run-retro writes `## RD answers`. If at least one answer exists, it dispatches `wstack:retro-analyst` a second time.
- [ ] **Step 3: Run** the test files. Expected: FAIL.
- [ ] **Step 4: retro-analyst.md.** New inputs are `transcript_stats` and, for a task with `has_retro_note` true, `retro-note.md`. Add two look-for items:
  1. A mismatch between the note or the run log and the stats. An example is a note that says no retries, with a high `tool_errors`.
  2. The same `top_bash` command in two or more tasks, as a script candidate.

  Every `Evidence` line still names a task id and a number. Add the `## Questions` block shape from design C4. At most one question group per task.
- [ ] **Step 5: run-retro `## Ask the RDs`.** For each task in `## Questions`:
  1. Take the last id in `spec.session_ids`. Check that `ls ~/.claude/projects/*/<id>.jsonl` finds its transcript. Run the fork with `workspace_cwd` from `spec.md` as the current folder.
  2. If `workspace_cwd` does not exist, run `mkdir -p` on it, run the fork, then `rmdir` it. This follows the Step 1 spike. If the spike showed that a recreated folder does not work, skip the task. Write `not reachable: folder gone` as its answer.
  3. Run `env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID claude -p --resume <id> --fork-session --tools Read,Grep,Glob "<prompt>"`. The prompt holds the questions and three rules. Answer from what you remember and from the files. Change nothing. If you do not know, say "I do not know".
  4. A failed call writes its first stderr line as the answer and the retro goes on.
  Then write `## RD answers` (question id, task id, question, answer) in the retro file, and dispatch `wstack:retro-analyst` again with the answers file to revise the proposals. Paste the revised proposals under `## Proposals`.
- [ ] **Step 6: docs/spec.md section 13.** Add bullets for the exit notes, the transcript stats, and the targeted reopen.
- [ ] **Step 7: Lint** the changed Markdown by hand. Fix every new hit.
- [ ] **Step 8: Run** `bash tests/run-all.sh`. Expected: all pass.
- [ ] **Step 9: Commit** `feat: the retro audits transcripts and asks a fork of the RD`.

### Task 6: Board

**Files:**
- Create: `scripts/board.sh`, `skills/board/SKILL.md`
- Modify: `tests/fixtures/bin/herdr` (per-name agent state and `workspace list`)
- Modify: `tests/test_skills.sh` (expected skills, user-invoked list) and `CLAUDE.md` (user-invoked list)
- Modify: `README.md`, and `docs/spec.md` (section 4 layout and a new section for the board)
- Create: `themes/notion.json` (a Notion-style theme for the board page)
- Modify: `scripts/render-page.sh` (optional `--theme-file <path>`)
- Test: `tests/test_board.sh`

**Interfaces:**
- Consumes: `scripts/list-open-tasks.sh` (tab lines: `task_id`, `status`, `workspace_cwd`, `folder`), `scripts/lib/herdr.sh` (`herdr_cmd`, `json_field`).
- Produces: `board.sh --vault <abs> --tasks-dir <rel>` prints one JSON object per line:

```json
{"group":"needs you","task_id":"2026-11-23-fix-x","slug":"fix-x","status":"drafting",
 "herdr":"idle","workspace_id":"w4","goal":"Rough idea from launch: fix x",
 "last_step":"- 2026-11-23T01:00:00Z step spec drafted","age":"3h","folder":"/abs/folder"}
```

  `group` is one of `needs you`, `stopped`, `working`, `paused`, `finished`, `other`, chosen by the first match of design D3. Lines are sorted by that group order, then by `task_id`. Outside herdr (`HERDR_ENV` not `1`), `herdr` and `workspace_id` are `n/a`, and no `finished` row is printed. The group then comes from the status alone. `paused` goes to `paused`. The waiting statuses go to `needs you`. Every other status goes to `other`. `finished` rows come from delivered or cancelled task folders of the last 14 days whose slug is the label of a workspace in `herdr workspace list`. `goal` is the first non-empty line under `## Goal`. `age` is the time since `created_at` in `m`, `h`, or `d`.

- [ ] **Step 1: Extend the fake herdr.** `agent get <name>` prints `{"result":{"agent":{"name":"<name>","workspace_id":"w-<name>","agent_status":"<state>"}}}` where the state comes from `FAKE_AGENT_STATES` (a list like `fix-x=idle,ship-y=blocked`). A name not in the list fails as today. `workspace list` prints the labels in `FAKE_WORKSPACES` (a list like `done-z=w7`). Keep every existing switch working.
- [ ] **Step 2: Write the failing tests** in `tests/test_board.sh` with a temp vault holding one task per case:
  - These go to `needs you`: `drafting` with herdr `idle`, `executing` with herdr `blocked`, and `awaiting-deliver-approval` with `working`.
  - `executing` with no agent goes to `stopped`.
  - These go to `working`: `verifying` with `working`, and `executing` with `unknown`, which shows `"herdr":"unknown"`.
  - `paused` goes to `paused`.
  - A delivered task whose slug is in `FAKE_WORKSPACES` goes to `finished` with that workspace id. A delivered task with no open workspace prints no row.
  - order of groups in the output matches design D3.
  - outside herdr (`HERDR_ENV` unset): `n/a` fields, no `finished` row, every open task printed.
  - an old spec with no `session_ids` and an empty `## Goal` prints `"goal":""` and no error.
- [ ] **Step 3: Run** `bash tests/test_board.sh`. Expected: FAIL.
- [ ] **Step 4: Implement `scripts/board.sh`.**
- [ ] **Step 5: Notion theme and page render.**
  1. Write `themes/notion.json` in the answer-me-with-html theme format (`am help theme`). Light: `--bg` and `--paper` `#ffffff`, `--ink` `#37352f`, `--ink-2` `#787774`, `--ink-3` `#9b9a97`, `--line` `#e9e9e7`, `--fill` `#f7f6f3`, `--accent` `#2383e2`. Dark: `--bg` `#191919`, `--paper` `#202020`, `--ink` `#e6e6e5`. Fill the other required colors in the same palette. Use `--radius` `4px`, no shadow, and a system sans font stack. `am theme check themes/notion.json --no-open` must exit 0.
  2. `scripts/render-page.sh` takes an optional third argument `--theme-file <path>`. With it, the script copies the file into `$AM_HOME/themes/` of a temp `AM_HOME` and renders with `--theme <file name without .json>`. Without it, nothing changes. Add one test row to `tests/test_render_page.sh` that renders with the theme file and finds the theme name in the page.
- [ ] **Step 6: Write `skills/board/SKILL.md`** with `disable-model-invocation: true` and the same Config block as run-retro for the vault path and the tasks folder. Its steps:
  1. Run `board.sh`.
  2. Print one table per group, in group order. The columns are task, stage, herdr, last step, age, and goal.
  3. Under each table that has workspace ids, print `herdr workspace focus <id>` for each row.
  4. Write the same tables as a draft and render `$vault/$(dirname "$tasks_dir")/Board/board.html` with `render-page.sh` and `--theme-file "${CLAUDE_PLUGIN_ROOT}/themes/notion.json"`. Print the page path. If the render fails, print its stderr and go on.
  5. If `finished` rows exist, ask once which to close: names, `all`, or `none`. End the reply and wait.
  6. Close as design D5. If `git -C <workspace_cwd> rev-parse --git-dir` differs from `--git-common-dir`, the workspace has a worktree. If that worktree has changes (`git -C <workspace_cwd> status --porcelain` prints anything), skip it and say why. For a clean worktree, run `herdr worktree remove --workspace <id>`. Without a worktree, run `herdr workspace close <id>`.
  7. Report what was closed and what was skipped.
- [ ] **Step 7: Register the skill.** Add `board` to `expected_skills` and to the user-invoked loop in `tests/test_skills.sh`. Add it to the user-invoked list in `CLAUDE.md`. Describe it in `README.md` and `docs/spec.md`.
- [ ] **Step 8: Lint** the new and changed Markdown by hand. Fix every new hit.
- [ ] **Step 9: Run** `bash tests/run-all.sh`. Expected: all pass.
- [ ] **Step 10: Commit** `feat: add /wstack:board, the overview of open RDs`.

### Task 7: Live monitor

**Files:**
- Modify: `scripts/board.sh` (two new row fields), `skills/board/SKILL.md` (`--watch`), `README.md`, `docs/spec.md`
- Create: `scripts/board-watch.sh`, `tests/fixtures/board-transcripts/` (small jsonl and meta files)
- Test: `tests/test_board.sh`, `tests/test_board_watch.sh`

**Interfaces:**
- Consumes: `board.sh` rows from Task 6, `transcript_main_files` and `transcript_subagent_files` from `scripts/lib/transcripts.sh`, `spec.session_ids` from Task 1.
- Produces: each `board.sh` row also has `last_tool` (`{"tool","hint","at"}` or `null`) and `subagents` (list of `{"type","description","idle_seconds","last_tool"}`), as design F1 says. `board-watch.sh` as design F2 says.

- [ ] **Step 1: Write fixtures.** Write three RD sessions, each with a different last `tool_use`:
  - a Bash call with a `description`
  - a Bash call with no description and a long command that holds `token=abc123`
  - a Read of `/a/b/login.ts`

  Under one session's `subagents/`: a finished agent (meta has `finished: true`), a running agent (fresh file), and a stale agent (`touch -t` to an old time, no `finished`). Each meta file holds `agentType` and `description`.
- [ ] **Step 2: Write the failing tests** in `tests/test_board.sh` (temp `HOME`, temp vault, fake herdr):
  - `last_tool.tool` is `Bash` and `last_tool.hint` is the description.
  - With no description, the hint is the first word of the command only, and the output never holds `abc123`.
  - A Read shows the hint `login.ts`.
  - `subagents` holds only the running agent, with its `type` and `description`. The finished and the stale agents are left out.
  - A hint is 60 characters at most and holds no newline.
  - A task with no `session_ids` has `last_tool: null` and `subagents: []`.
  - `WSTACK_BOARD_ACTIVE_MINUTES=100000` brings the stale agent back.
- [ ] **Step 3: Write the failing tests** in `tests/test_board_watch.sh`: `board-watch.sh --once` prints one header line per open RD with its slug and group, a tool line with the hint, and one line per running subagent. It exits 0. A bad `--interval` (not a positive integer) exits 1.
- [ ] **Step 4: Run** both test files. Expected: FAIL.
- [ ] **Step 5: Implement** the two fields in `board.sh` and the script `scripts/board-watch.sh`. Read only the last 200 lines of each transcript with `tail -n 200`. Skip lines that are not JSON, as `transcript-stats.sh` does. The loop clears with `printf '\033[H\033[2J'`, prints a frame, and sleeps `--interval` seconds.
- [ ] **Step 6: Board skill `--watch`.** Add the design F3 steps to `skills/board/SKILL.md`. Add a `tests/test_skills.sh` assertion that the skill holds `board-watch.sh`, `herdr pane split --current --direction down --no-focus`, and `herdr pane run`.
- [ ] **Step 7: Docs.** Describe `--watch` in `README.md` and `docs/spec.md`.
- [ ] **Step 8: Lint** the changed Markdown by hand. Fix every new hit.
- [ ] **Step 9: Run** `bash tests/run-all.sh`. Expected: all pass.
- [ ] **Step 10: Commit** `feat: add a live monitor of the open RDs`.

## Release (controller, after the final review)

Bump `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `tests/test_manifest.sh` to `0.5.0`. Add a `## 0.5.0 - <date>` CHANGELOG entry with `- **feat:**`, `- **change:**`, and `- **docs:**` bullets. Run the suite, merge, push, watch the catalog sync, and update the installed plugin.

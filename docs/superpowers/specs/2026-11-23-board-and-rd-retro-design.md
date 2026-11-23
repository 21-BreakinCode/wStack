# Board and RD retro design

Date: 2026-11-23. Size: a project, four parts in one release. The user picked all four parts and left the how to Claude. Each design call that Claude made is marked "Call:".

## Intent

wStack acts as the tech lead. The user is the final quality gate. For each task, wStack starts one RD (a Claude session) in its own herdr workspace. The RD can open more panes and subagents, but only inside that workspace and only for that task.

The user wants three things that wStack does not fully do today:

1. A live overview: how many RDs are open, what each one works on, and where each one is.
2. A record of each RD's work that is worth keeping.
3. A weekly retro that learns from the RDs. Where the evidence raises a question, it talks to the RD again. It turns fixed steps into scripts and common patterns into rules.

The user said token cost does not limit the design. The aim is a more stable workflow with higher quality, week after week.

## What exists today

- `scripts/launch-task.sh` opens one herdr workspace per task. The workspace label and the agent name are the task slug. A code task with a repository (`--repo-path`) gets a herdr worktree. A code task without one gets a plain workspace in `~/.wstack/tasks/<task_id>`. The RD starts with `claude_task_flags` from `scripts/lib/herdr.sh`.
- `scripts/list-open-tasks.sh` prints the task id, status, `workspace_cwd`, and folder of each task that is not delivered or cancelled. Only start-task, pause-work, and resume-work call it. No command shows it to the user as an overview.
- Each task writes `run-log.md` (step lines that the RD writes itself), `review.md` (reviewer findings), and `report.md`. Deliver step 5 counts tokens with `scripts/session-tokens.sh`.
- `session-tokens.sh` reads the newest transcript in the folder of `workspace_cwd`. A contract task runs in the repository root, the same folder as the user's own session. Two sessions can then share a transcript folder, and "newest file" can pick the wrong one.
- Deliver writes the command that closes the workspace, but it never runs it. Finished workspaces stay open until the user closes them.
- `/wstack:run-retro` sends 7 days of task frontmatter to the `retro-analyst` agent. The agent reads each `run-log.md` and blocking findings. It proposes changes. It never asks an RD anything, and it never reads a transcript.

## Goals

- G1. `/wstack:board` shows every open RD: task, goal, stage, herdr state, last step, and age. It puts the RDs that wait for the user first.
- G2. The board closes finished workspaces after the user picks them.
- G3. Each task records the id of every Claude session that worked on it. Every later step finds the exact transcripts by those ids.
- G4. At Deliver, the RD writes an exit note while it still remembers the work.
- G5. The retro reads the exit notes and real counts from the transcripts.
- G6. Where the evidence raises a question about one task, the retro reopens a fork of that RD's session and asks it. The answers feed the proposals.
- G7. An RD that opens herdr panes opens them in its own workspace and closes them before Deliver.

## Non-goals

- A live web page for the board that refreshes itself. A live page needs a server and a refresh loop. The board writes a static snapshot page instead (D7).
- Reopening every RD each week. A fixed question to every RD gives the same facts as the exit note, from an older memory. A reopen is useful only with a question from the evidence.
- Cross-machine herdr sessions.
- An exit note for a task that a failed launch cancelled. That task never had a session. A task that the retry limit cancels runs in a live session, so it writes the note (B1).

## Anti-goals

- The board or the retro changes a task's status, files, or code without the user. The only write that the board does is the workspace close that the user picked.
- A reopened fork edits files, runs a guarded command, or continues the task.
- The retro takes an RD's own words (run log, exit note, reopen answer) over the transcript. If the two disagree, the transcript wins, and the retro names the mismatch.

## Constraints

- The repository rules in `CLAUDE.md` hold: scripts run on `/bin/bash` 3.2 with `set -euo pipefail`, tests never write into `$HOME/Projects/LifeOS/`, and tests that touch `~/.wstack` set `HOME` to a temp folder.
- Herdr commands in tests target the session `wstack-test`.
- All text follows `rules/communication.md` (simple English).
- New skills follow the skill rules in `CLAUDE.md`. `/wstack:board` is user-invoked (`disable-model-invocation: true`).
- Old task folders have no `session_ids`. Every new step falls back to the current behavior for them.

## Approaches

The user asked whether the exit note and the reopen can both exist. They can, in layers:

1. Exit note only. Cheap and fresh, but it is the RD describing its own work, with the same blind spots as `run-log.md`.
2. Reopen only. The RD remembers more than a note holds. But a week later its memory is older, it can be compacted, and with no evidence the questions are generic.
3. Layers (picked). Every task gets an exit note and a linked transcript. The retro audits both. It reopens only the RDs where the evidence raises a specific question. This gives the best answers, not only the lowest cost.

For the board, the choice was a terminal table (picked), a live web page, or a count line in every start-task run. The table answers "how many, what, where" on demand with no server. A count line adds noise to every task start.

## Design

### Part A. Session link

A task often runs across several sessions. A pause, a restart outside herdr, or a resume each starts a new session with a new id. So a task keeps a list of ids, not one.

- A1. Claude Code replaces `${CLAUDE_SESSION_ID}` in plugin skill text. In task mode and in work mode, start-task adds `${CLAUDE_SESSION_ID}` to the `session_ids` list in the `spec.md` frontmatter, unless the list holds it already. The list is inline JSON, as `pending` and `ignore` are in a contract. Call: the session records its own id, so every restart path is covered without a change to the printed hand-off commands.
- A2. If the spike in "Check first" item 1 shows that the text is not replaced, the fallback is: `launch-task.sh` makes a lowercase UUID with `uuidgen`, starts the RD with `--session-id <uuid>`, and writes it to `session_ids`. The printed hand-off commands then get `--session-id <new uuid>` too.
- A3. If `session_ids` is not empty, `resume-task.sh` restarts with `--resume <last id>`. Otherwise it restarts with `--continue` as today.
- A4. A session id is a UUID, so `~/.claude/projects/*/<id>.jsonl` finds a transcript without the working folder. This also works after a worktree is removed. Subagent transcripts are in `~/.claude/projects/<folder>/<id>/subagents/*.jsonl`.
- A5. `session-tokens.sh` takes an optional `--session <id>`, which it can get more than once. With it, the script sums the main transcripts of those ids. If none is found, it exits 2. Without it, the script keeps the newest-file rule. A second output line holds the subagent tokens of the same ids.
- A6. Deliver step 5 passes every id in `session_ids`. It sets `tokens_used` to the main-session sum as today, and the new `subagent_tokens` in `run-log.md` to the subagent sum. Call: `tokens_used` keeps its old meaning, so old and new tasks stay comparable in the retro.
- A7. `docs/spec.md` section 6.1 adds `session_ids` to `spec.md` and `subagent_tokens` to `run-log.md`.

### Part B. Exit note

- B1. Deliver "Finish" gets a new step before `status` becomes `delivered`. The RD writes `retro-note.md` in the task folder. A task that the retry limit cancels (`skills/start-task/references/verify.md`) writes the note too, before its status becomes `cancelled`.
- B2. Shape:

```
---
task_id: <task id>
written_at: <ISO time>
---

## Slow or repeated steps
## Would script
## Spec gaps
## Tool and guard friction
## Surprises
```

- B3. Each bullet names its evidence: a `run-log.md` line, a file and line, or a command. A section with nothing to say holds `None.`
- B4. `## Would script` gives the steps that the RD did by hand more than once, with the script that can replace each one. `## Spec gaps` gives what the spec questions did not ask and what that cost. `## Tool and guard friction` gives prompts, guard asks, failed commands, and waits.
- B5. `docs/spec.md` section 6 lists the new file.

### Part C. Transcript audit and targeted reopen

- C1. New script `scripts/transcript-stats.sh <session id>...` finds the transcripts as A4 says, main and subagent. It prints one JSON object with these fields:
  - tool calls by tool name, and tool results with an error
  - the 10 most repeated Bash commands, as the command name plus the subcommand of a tool such as git or gh (no quoted text and no secrets)
  - the number of compactions and of user turns
  - the start and end times

  Call: a script does the counting, because a transcript holds megabytes, and counts must be the same on every run.
- C2. `collect-week.sh` already copies the whole `spec.md` and `run-log.md` frontmatter, so `session_ids` arrives with no change. It adds `has_retro_note`, and the `transcript-stats.sh` output for each task with `session_ids`. This covers delivered, cancelled, paused, and open tasks alike.
- C3. `agents/retro-analyst.md` reads `retro-note.md` and the stats. It looks for two more things: a mismatch between the note or the run log and the transcript counts, and repeated Bash commands across tasks that a script can replace.
- C4. The analyst reply gets an optional `## Questions` block after the proposals:

```
### Q1 <task id>
- Evidence: <what in the note, log, or stats raised it, with a number>
- Question: <one specific question for that RD>
```

  Questions for the same task go to that RD in one prompt. A task with an empty `session_ids` gets no question.
- C5. `run-retro` gets a new step "Ask the RDs" after the analyst. For each task with questions, it runs, in the task's `workspace_cwd`:

```
env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID \
  claude -p --resume <last id in session_ids> --fork-session <read-only flags> "<questions>"
```

  The fork leaves the original session as it was. The prompt tells the fork three things. Answer from what you remember and from the files. Change nothing. If you do not know, say "I do not know".
- C6. A resume looks for the session in the project folder of the current folder. The step runs in the folder that holds the transcript, found as A4 says, which maps back to the original `workspace_cwd`. If that folder is gone (a removed worktree), the step creates it empty for the call and removes it after. "Check first" item 3 tests this.
- C7. The retro dispatches the analyst a second time with the answers, and the analyst revises the proposals. The retro file gets a `## RD answers` section with each question, the answer, and the task id.
- C8. If a reopen fails, the retro writes the error under `## RD answers` and goes on.

### Part D. Board

- D1. New script `scripts/board.sh --vault <abs> --tasks-dir <rel>` prints one JSON object per row:
  - the open tasks from `list-open-tasks.sh`. Each row holds the first line of `## Goal` in `spec.md`, the status, the age from `created_at`, and the last `## Steps` line of `run-log.md`
  - the herdr state from `herdr agent get <slug>`, and the workspace id. The state is `working`, `idle`, `blocked`, `done`, or `unknown`. If no agent has that name, the state is `none`
  - delivered or cancelled tasks whose workspace (label = slug) is still open, marked `finished, workspace open`
- D2. Outside herdr, the herdr fields are `n/a`, and no finished row shows.
- D3. New skill `skills/board/SKILL.md`, user-invoked as `/wstack:board`. It prints a table with one group per row kind, in this order. A row goes in the first group that matches.
  1. needs you: herdr `blocked`, a status of `awaiting-approval`, `waiting-user`, or `awaiting-deliver-approval`, or `drafting` with herdr `idle` or `done`. The last case is a spec that waits for answers to its questions
  2. stopped: herdr `none` and the status is not `paused`. The RD process is gone, so the row shows the resume command `/wstack:start-task` (resume mode)
  3. working: herdr `working` or `unknown`. An `unknown` row says so
  4. paused: status `paused`
  5. finished, workspace open
  6. other: any row that matched no group, with its status and herdr state
- D4. After the table, the skill prints `herdr workspace focus <id>` for each row, so the user can jump to an RD. If finished rows exist, it asks once which workspaces to close: names, `all`, or `none`.
- D5. Close: if `git -C <workspace_cwd> rev-parse --git-dir` differs from `--git-common-dir`, the workspace has a worktree. Without a worktree, the skill runs `herdr workspace close <id>`. With one, it first runs `git -C <worktree> status --porcelain`. If that prints anything, the skill skips the task and tells the user. Otherwise it runs `herdr worktree remove --workspace <id>`.
- D7. The board also writes a static snapshot page, `Board/board.html` next to the `Retros` folder, from the same rows. The user asked that a board page uses a Notion style by default. wStack ships `themes/notion.json` in the answer-me-with-html theme format, and `render-page.sh` takes an optional `--theme-file`. The review and retro pages keep their current theme.
- D6. `docs/spec.md` and the README describe the command. `CLAUDE.md` adds `board` to the user-invoked list.

### Part E. RD panes stay home

- E1. `skills/start-task/references/execute.md` gets one rule: if you open a herdr pane, open it in your own workspace with `herdr pane split --current ... --no-focus`, and close it before Deliver.
- E2. pause-work already stops the background work of a session. No change.

### Part F. Live monitor

The user asked for a live view of the open RDs: what each one does, which subagents it runs right now, and which tools they call. The view updates by itself.

Call: a herdr pane that runs a bash refresh loop, not a Claude Code mod. The mod API is early access, its pane docks beside the chat only in the fullscreen layout, and it loads in every RD session too. A bash loop reuses `board.sh`, runs in any terminal, and fits the existing bash tests. A mod can read the same `board.sh` output later.

- F1. `board.sh` rows gain `last_tool` and `subagents`. The data comes from the newest transcript in `session_ids`, found with `scripts/lib/transcripts.sh`. The script reads only the last 200 lines of each transcript, because a transcript can hold tens of megabytes.
  - `last_tool` is `{"tool", "hint", "at"}` for the last `tool_use` item. The hint takes the first field that is set, in this order: `input.description`, the base name of `input.file_path`, and `input.pattern` cut to 40 characters. It is cut to 60 characters, with newlines removed. Call: a Bash call shows only its description, never its command text, because a command can hold a secret. A Bash call with no description has an empty hint.
  - `subagents` lists the subagents that run now: an `agent-*.jsonl` file under `<session id>/subagents/` whose `.meta.json` has no `finished: true` and that changed in the last `WSTACK_BOARD_ACTIVE_MINUTES` minutes (default 15). Each item is `{"type", "description", "idle_seconds", "last_tool"}`, with `type` and `description` from the meta file.
  - A task with no `session_ids` or no transcript gets `last_tool: null` and `subagents: []`.
- F2. New script `scripts/board-watch.sh --vault <abs> --tasks-dir <rel> [--interval <seconds>] [--once]` clears the screen and prints one frame every `--interval` seconds (default 3). A frame shows, per RD, one header line (group, slug, stage, herdr state, age), one tool line, and one line per running subagent. `--once` prints one frame without clearing and exits, for tests. Ctrl-C ends the loop.
- F3. `/wstack:board --watch` opens the monitor. Inside herdr, it runs `herdr pane split --current --direction down --no-focus`, then `herdr pane run <pane id> "bash <scripts>/board-watch.sh ..."`, and prints the pane id and `herdr pane close <pane id>`. Outside herdr, it prints the command to run in another terminal.

## Check first

1. `${CLAUDE_SESSION_ID}` is replaced in plugin skill text and matches the transcript file name. If not, use the A2 fallback.
2. `claude -p --resume <id> --fork-session` answers in print mode and leaves the original transcript unchanged.
3. A resume works from a folder that was removed and created again empty.
4. The exact flags that make the fork read-only in print mode (for example an allowed-tools list of Read, Grep, and Glob). The wStack guard hook still runs in the fork.
5. The subagent transcript folder layout in A4 holds for the installed Claude Code version.

## Left to the builder

- The exact JSON field names of `board.sh` and `transcript-stats.sh`.
- The table format in the board skill, within the 10.1 layout rules where a page is involved.
- Test fixtures: a fake transcript for `transcript-stats.sh`, a fake herdr for `board.sh` (the existing tests show the pattern), and block tests for the new skill text.

## Calls made by Claude

- A terminal table for the board, no live page.
- A task keeps a list of session ids, and each session records its own id through `${CLAUDE_SESSION_ID}`.
- `tokens_used` keeps its meaning. Subagent tokens go in a new field.
- Transcripts are found by session id, so no path is stored.
- The exit note is written at Deliver and at a retry-limit cancel. A failed launch has no session and no note.
- Board groups: needs you, stopped, working, paused, finished, other.
- A worktree is found with `git rev-parse`, not by work type.
- Counting in a script, reading in the agent.
- Reopen only with a question from the evidence. All questions for one task go in one prompt.
- The board's only write is the workspace close that the user picked, and a worktree with changes is skipped.
- The live monitor is a herdr pane with a bash refresh loop, not a Claude Code mod. Tool hints never show command text. A Bash call shows only its description.

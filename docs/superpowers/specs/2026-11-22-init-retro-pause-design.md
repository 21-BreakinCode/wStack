# Contract setup in init-service, drift walk in run-retro, and pause-work and resume-work: design

Date: 2026-11-22. Size: three small features in wStack 0.4.0. The user asked for all three and left the design calls to Claude. Each call is marked "Call:".

## 1. init-service sets up the contract

Intent: a service gets its contract during the same one-time setup that maps it. Today the user must remember a separate `/wstack:start-task set up the contract`.

Design:
- A new phase runs after the local exclude phase. It runs `contract-path.sh --vault "$vault" "$REPO_ROOT"`.
- Exit 0 and the contract file exists: run `contract-check.sh` and report the status line in the final report. Change nothing.
- Exit 0 and the file does not exist: ask one question, "Set up the service contract now?", with the options "Launch a contract task" and "Not now".
- On "Launch a contract task": read "Launch mode" in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/SKILL.md` and run it with the idea `set up the contract`, the work type `contract`, and the repository `$REPO_ROOT`. The new task session runs the contract work as usual.
- Exit 1 or 2: report the line and go on. The mapping phases before this one already handled the error cases.
- The report gets a `Contract:` line: `present (<status>)`, `task <task_id> launched`, `not set up`, or the error.

Call: init-service launches a task and does not write the contract itself. The contract task already has the questions, the absorb rules, the review, and the safe delivery. A copy of them in init-service makes two places to keep in step.

## 2. run-retro checks contract drift and walks the user through it

Intent: the weekly retro is a natural time to bring the service contract back in line with the code.

Design, a new section "Contract drift" that runs after step 7 (the proposals list) and before step 8 (the question):
1. If `git rev-parse --show-toplevel` fails, skip the section and say "not a git project".
2. Run `contract-path.sh`. Exit 1: say "Contract: not mapped" and skip. Exit 2: show stderr and skip. A missing contract file: say so, point to `/wstack:init-service`, and skip.
3. Update the base branch (`base_branch` from the contract). Run `git fetch origin <base_branch>`. If the current branch is the base branch and `git status --porcelain` prints nothing, also run `git merge --ff-only origin/<base_branch>`. Otherwise say that only a fetch ran.
4. Run `contract-check.sh`. Exit 0: say "Contract: fresh". Exit 2 or 3: show the cause and skip.
5. Exit 1: record `checked_commit` (`git rev-parse origin/<base_branch>`), and dispatch `wstack:contract-reader` with the check output and the goal "refresh the stale sections". Write its patch to `$retro_dir/$retro_name.contract-patch.md`. List each stale section with a one-line summary of the proposed change.
6. Step 8 then asks two things in one reply: which proposals to apply, and which contract sections to update (names, `all`, or `none`).
7. After the answer, apply the chosen sections with the same lock pattern as step 9 of the spec stage. First write a write-once copy to `$retro_dir/$retro_name.contract-before.md`. Then run `apply --sections`. If every stale section was applied, also run `set-verified "$checked_commit"`.
8. The retro file gets a `## Contract` section: the status, the applied sections, and the undo command.

Call: the retro pulls only with `--ff-only` on a clean base branch. It never merges, rebases, or stashes the user's work.

Call: drift sections and proposals are asked in one question, so the retro still ends with one reply from the user.

## 3. pause-work and resume-work: stop work in the middle and resume it later

Intent: the user must sometimes stop in the middle of work, for example to close the computer. In the contract-gate session, the controller wrote notes but left 3 shells and 2 subagents running, because compacting a conversation does not stop background agents. The user had to ask why. The fix must work in any Claude Code session, not only in a wStack task.

Design:
- Two user-invoked skills: `/wstack:pause-work [--task <task_id>]` and `/wstack:resume-work [<note path>]`.
- Step 1 of pause-work, find the context. It is a task pause in two cases. One case is `--task`. The other case is a current directory that is the `workspace_cwd` of one open task, from `list-open-tasks.sh`. Any other case is a session pause. A session pause needs no vault.
- Step 2, write the resume note first, so a failed stop still leaves a note. A task pause writes `<task folder>/pause.md`. A session pause writes `~/.wstack/pauses/<current folder name>-<YYYYMMDD-HHMMSS>.md`. The note holds the time, the current folder, the goal, what is done, and the step in progress. It also holds the next steps in order. It holds the git state (branch, HEAD, uncommitted paths) of the current repository and of every worktree the session used. It ends with the files to read first on resume. A task note also holds the status before the pause.
- Step 3, stop background work. Stop every background agent and shell of the session with the TaskStop tool. Then look for processes that outlive the tools (test runs, `playwright-cli` sessions, dev servers). Match them by the current folder and the worktree paths. Stop only the ones traced to this session, and list the others in the note.
- Step 4, add what was stopped and what still runs to the note. A task pause also sets `status: paused` and `paused_from: <old status>` in `spec.md`, and adds a `pause` line to `run-log.md`. A task that is already paused is refused.
- Step 5, tell the user the note path and the resume command.
- resume-work finds the note. With a task folder, it uses `pause.md`. Otherwise `scripts/list-pause-notes.sh` lists the notes whose recorded folder is the current folder, newest first, and resume-work takes the first. It compares the git state with the note and reports every difference. It shows the goal, what is done, the step in progress, and the next steps, and reads the files to read first. A task note restores the old status and is renamed to `pause-<time>.md`. A session note is renamed to `<name>.resumed-<time>.md`, so the next resume does not pick it again. Then it goes on from the first next step.
- Work mode in start-task runs resume-work for a task whose status is `paused`.
- `paused` becomes a task status value. `list-open-tasks.sh` lists paused tasks as open.

Call: no automatic pause hook. A hook cannot stop agents, and an automatic note at session end is guesswork. The user runs the skill on purpose.

Call: uncommitted work stays where it is. The next session checks it against the note and does not discard it.

## Non-goals

- A contract written by init-service itself.
- A retro that rebases or stashes.
- An automatic pause.

## Left to the builder

- Exact wording and the place of each new step in the skill files, in their house style.
- The test shape: static pins in the skills tests, and behavior tests for any script change (`list-open-tasks.sh`, `resume-task.sh`).

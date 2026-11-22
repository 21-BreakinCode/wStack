# Contract setup in init-service, drift walk in run-retro, and pause-task: design

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

## 3. pause-task: stop a task in the middle and resume it later

Intent: the user must sometimes stop in the middle of a task, for example to close the computer. In the contract-gate session, the controller wrote notes but left an agent and its shells running, and the user had to ask why.

Design:
- A new user-invoked skill, `/wstack:pause-task [--task <task_id>]`. Without `--task`, it uses the task of the current session: the open task whose `workspace_cwd` is the current directory, from `list-open-tasks.sh`.
- Step 1, stop background work. Stop every background agent and shell of this session with the TaskStop tool. Then look for a test run that started from the task workspace (`pgrep -fl` on the workspace path), and stop it.
- Step 2, save the state in `<task folder>/pause.md`. It holds the time, the status before the pause, and the step in progress. It also holds the git HEAD, the uncommitted paths of the workspace, what was stopped, and the next step.
- Step 3, set `status: paused` and `paused_from: <old status>` in `spec.md`, and add a `pause` line to `run-log.md`.
- Step 4, tell the user how to resume: `/wstack:start-task --task <task_id>`.
- If `status` is `paused`, work mode in start-task reads `pause.md` first. It restores the old status and compares the git HEAD and the uncommitted paths with the note. It shows the note and goes on from the next step. Then it renames `pause.md` to `pause-<time>.md`, so the history stays and the next pause starts clean.
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

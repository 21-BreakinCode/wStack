# Contract Setup, Retro Drift Walk, and Pause-Task Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** init-service offers the contract setup. run-retro walks the user through contract drift. A new pause-task skill stops a task cleanly, and work mode resumes it.

**Architecture:** Each feature is skill text that reuses existing scripts and patterns. The scripts are `contract-path.sh`, `contract-check.sh`, `contract-edit.sh`, `list-open-tasks.sh`, and `frontmatter-set.sh`. The patterns are the start-task launch and the lock. The one script change: `paused` becomes an open status.

**Tech Stack:** Markdown skills, bash 3.2 scripts, bash tests.

**Spec:** `docs/superpowers/specs/2026-11-22-init-retro-pause-design.md`

## Global Constraints

- Run `bash tests/run-all.sh` before each commit. Scripts start with `#!/usr/bin/env bash` and `set -euo pipefail`, run on `/bin/bash` 3.2, and quote every path variable.
- Skill bash blocks run under zsh on this Mac. A block that loops over a glob starts with `setopt NULL_GLOB 2>/dev/null || true`. Every contract write uses the lock pattern: `set -e`, `lock`, then `trap '<unlock>' EXIT`.
- User-invoked skills have `disable-model-invocation: true`. The new skill is `pause-task`, and CLAUDE.md's skill list names it.
- Tests never write into `$HOME/Projects/LifeOS/`. Tests that touch `~/.wstack` set `HOME` to a temp folder.
- Markdown passes the simple-english lint (lint by hand in `.claude/worktrees/`).
- Do not change CHANGELOG.md or the version. The controller writes the release.

## Review Focus

1. init-service runs in a repository that is not mapped yet. The contract phase runs after the mapping phases, so it sees the new row. Test: Task 1 pin that the contract phase comes after Phase 7.
2. run-retro runs on a feature branch with uncommitted work. The retro only fetches, never merges. Test: Task 2 pin for `--ff-only` and the clean-tree condition.
3. The user picks only some stale sections in the retro. `verified_commit` does not move. Test: Task 2 pin for the rule "if every stale section was applied, run `set-verified`".
4. A paused task is resumed in a new session. The task shows as open, and work mode reads `pause.md` first. Test: Task 3 `list-open-tasks.sh` row for `paused`, and a pin for the work mode rule.
5. pause-task runs twice. The second pause keeps the first note's history. Test: Task 3 pin for the `pause-<time>.md` rename on resume, and a rule that pause-task refuses a task that is already paused.

---

### Task 1: Contract phase in init-service

**Files:** `skills/init-service/SKILL.md`, `tests/test_skills.sh` (or the test that already pins init-service text).

- [ ] Add pins for a contract phase after Phase 7. It names `contract-path.sh`, `contract-check.sh`, and the question "Set up the service contract now?". It also names the start-task "Launch mode" path and the idea `set up the contract`. The Phase 8 report has a `Contract:` line. Run the test and see it fail.
- [ ] Write the phase as the design says. It resolves the tasks folder the same way start-task does, because Launch mode needs it.
- [ ] Run the tests, lint, and commit `feat: offer the contract setup in init-service`.

### Task 2: Contract drift in run-retro

**Files:** `skills/run-retro/SKILL.md`, a test that pins run-retro text.

- [ ] Add pins for the "Contract drift" section: it runs after step 7 and before step 8, and it skips a non-git directory, an unmapped repository, and a missing contract. It fetches and fast-forwards only on a clean base branch, dispatches `wstack:contract-reader`, and writes the patch and the before copy in `$retro_dir`. It applies under the lock pattern and writes a `## Contract` section. If every stale section was applied, it runs `set-verified`. Step 8 asks for proposals and sections in one question. Run the test and see it fail.
- [ ] Write the section as the design says.
- [ ] Run the tests, lint, and commit `feat: walk contract drift in run-retro`.

### Task 3: pause-task and resume

**Files:** create `skills/pause-task/SKILL.md`. Modify `skills/start-task/SKILL.md` (work mode), `scripts/list-open-tasks.sh`, `docs/spec.md` (status values and the skill list), `README.md`, `CLAUDE.md`, and the tests for `list-open-tasks.sh` and skills.

- [ ] Add a failing `list-open-tasks.sh` test row: a task folder with `status: paused` is listed. Add pins: pause-task stops background work with TaskStop and checks `pgrep`, writes `pause.md` with the listed fields, and sets `status: paused` and `paused_from`. It refuses a task that is already paused, and it tells the user the resume command. If the status is `paused`, work mode reads `pause.md`, compares the git state, restores the status, and renames the note to `pause-<time>.md`.
- [ ] Write the skill, the work mode rule, and the script change. Add `paused` to the status values in docs/spec.md, and name the skill in README.md and CLAUDE.md.
- [ ] Run the tests, lint, and commit `feat: add pause-task to stop a task and resume it later`.

### Task 4: Release (controller)

- [ ] Merge, bump to 0.4.0 with a CHANGELOG entry in `- **feat:** text` bullets, run the suite, push, and update the installed plugin.

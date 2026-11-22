# wStack: service contract gate and handover move

Date: 2026-11-21. Status: draft, waiting for the user's approval.

This design changes `docs/spec.md` and the design doc `2026-11-18-wstack-design.md`. When this design is approved, it wins over both for the parts it covers.

## 1. Intent

The user wrote a spec for a new feature on top of an old description of the service. The description no longer matched the code. The user found out only at implementation and had to write the spec again. This design stops that rework. A spec never starts from a stale description of the service.

Three more needs shape the design:

- Colleagues work in the same repositories. Nothing in this design changes a file that the team tracks or sees.
- The user plans a service-expert bot. Other people will ask it about a service, and it will answer from the same description. So the description must be readable by strangers and must say how fresh it is.
- The user wants less cognitive load. One plugin owns the development flow, and its skill names follow one pattern.

## 2. Terms

| Term | Meaning |
| --- | --- |
| Contract | The latest-state description of one service, in one file. |
| Team docs | Files the team keeps in the repository, for example `PRD.md` or `docs/api.md`. |
| Decision file | One file that records one choice and its reason. |
| Drift | The contract no longer matches the code or the team docs on `base_branch`. |
| Source globs | The file patterns that one contract section describes. |
| Contract folder | `<vault>/01Project/<ORG>/<lifeos_subpath>/`, from the service mapping. |
| Service mapping | The table in `01Project/<ORG>/handover_handler__initiation.md`. |
| Contract gate | A new first step of `Confirmation`. It makes the contract fresh before the spec exists. |

## 3. Goals, non-goals, anti-goals

Goals:

1. The contract gate runs before `Confirmation` writes a spec. A spec never starts from a stale contract.
2. A new project and an existing project both reach a contract that the user approved, before the first feature task.
3. The latest state and the history live in separate files. A normal read loads only the latest state.
4. Nothing changes in the team repository. No tracked file changes, and no change to the team `.gitignore`.
5. The contract points at team docs with `@`. It never copies their text.
6. Drift is never silent. A changed source file that no section claims shows up in the report.
7. The handover commands move from obsidian-kit into wStack. wStack then has no dependency on obsidian-kit.
8. Skill names inside wStack follow the pattern `<verb>-<object>`.

Non-goals:

- The service-expert bot. This design only keeps the reader agent usable without a person, for later.
- A check in the team CI. The contract lives outside the repository, so CI cannot see it.
- Renames in other plugins.
- Machine diffs of API schemas between services, for example OpenAPI diffs.

Anti-goals. Any one of these makes the build a failure:

- The contract or its history loads into every session.
- A colleague sees any trace of this system in the repository.
- A stale contract claims to be fresh.

## 4. Constraints

These are facts from the docs, a test, or the machine. Each one limits the design.

- A plugin cannot ship a `CLAUDE.md` or a rule file. It can ship skills, agents, and hooks (code.claude.com/docs/en/plugins/components.md).
- No hook fires on a git event. `PostToolUse` on `Bash` sees a git command that Claude runs. `SessionStart` sees the result of a pull that ran outside Claude (code.claude.com/docs/en/hooks.md).
- A `SessionStart` hook can add at most 10,000 characters of context.
- Claude Code expands `@` imports only in `CLAUDE.md` files. In a file that an agent reads, `@` is plain text. A test with `claude -p` showed that an `@` import of a vault path from `CLAUDE.md` does not load.
- The LifeOS vault is not a git repository. A contract edit keeps no line history.
- Team repositories use both merge methods. media-center PRs #148 to #165 landed as squash merges. example-service PRs #2 and #3 landed as merge commits. After a squash merge, the branch commit is not an ancestor of the base branch.
- Feature PRs often target `staging`, not the default branch. Many team repositories use `staging` as the default branch. example-service uses `master` as the default, but its service code lives on `staging`.
- herdr runs each task in a worktree under `~/.herdr/worktrees/<repo>/<branch>`. A path match against `repo_path` fails there.
- The Appier initiation file writes `github_orgs` as a block list. `resolve-org.sh` reads only the inline form.
- wStack scripts run on `/bin/bash` 3.2. The handover scripts that move are Python. `/usr/bin/python3` on this Mac is 3.9.6.
- wStack has a declared dependency on `answer-me-with-html`.
- The vault has no `.obsidian-kit.json` file today. The vault holds 11 handover notes under `01Project/*/*/*/handover/`.
- Only the wStack repository has a `./handover` symlink. Many team repositories get `OBSIDIAN_KIT_VAULT` from one shared file, `~/.claude/settings.appier-cs.json`. Only the handover code reads that variable.
- Tests never write into `$HOME/Projects/LifeOS/`.

## 5. Approaches

### 5.1 The contract system

| Approach | Result |
| --- | --- |
| A. A `CLAUDE.local.md` symlink loads the contract in every session, plus one drift hook. | Rejected. It loads the contract and the team docs into every session, which is an anti-goal. It has no reader agent and no history agent. |
| B. A contract gate inside the wStack pipeline, with reader and historian agents and a write-back in `Deliver`. | Picked. It stops the rework at the exact point, and it keeps the main context clean. |
| C. A separate contract plugin that wStack calls. | Rejected. It is the most work. The interface between the two plugins becomes one more contract to keep current. |
| A contract file in the repository, checked in CI. | Rejected. Colleagues share the repository, so nothing from this system can land there. |
| No stored contract. An agent rebuilds it from the code each time. | Rejected. Code does not show intent, decisions, or non-goals. This method runs once, to write the first contract of an existing project. |

### 5.2 How wStack finds the contract folder

| Approach | Result |
| --- | --- |
| Follow the `./handover` symlink that obsidian-kit creates. | Rejected. That is a hidden dependency, and it fails without a warning. |
| A wStack setting for each repository, `WSTACK_CONTRACT_DIR`. | Rejected. Each repository then needs two setups, and the development commands stay split across two plugins. |
| Move the handover commands into wStack. | Picked. One plugin owns the service mapping, the handover folder, and the contract. One setup command covers all three. |

### 5.3 Names

The user picked `<verb>-<object>`, inside wStack only. The other options were "keep all names and add a map page" and "`<area>-<verb>` in every plugin".

### 5.4 History

One growing `HISTORY.md` file was rejected. An agent that opens it reads all of it, so the context problem comes back as the file grows. One decision file for each choice was picked.

## 6. Design

### 6.1 Files in the vault

The vault folder has one reader, the user. So the design can reshape it freely, and each file gets one job and one reason to change. Team docs in the repository have many readers. The contract only points at them and never changes them.

```
<vault>/01Project/<ORG>/
├── handover_handler__initiation.md     service mapping (format unchanged)
└── <lifeos_subpath>/                   for example Services/example-service/
    ├── <app_name>.md                   the contract: what is true now
    ├── plan.md                         what is planned and not built yet
    ├── decisions/
    │   └── 0001-<slug>.md              history, one choice for each file
    ├── handover/                       handover notes (unchanged)
    └── _archive/                       old vault docs after the absorb
```

| File | Job | Changes when | Kept current by |
| --- | --- | --- | --- |
| `<app_name>.md` | What is true now | The code or a team doc changes | The drift check against `base_branch` |
| `plan.md` | What is planned and not built yet | Priorities change | `Deliver` removes each item that the task built |
| `decisions/` | Why, one choice for each file | A task makes a choice | Nobody edits a file after it lands |
| `handover/` | Where a session stopped | A session ends | `/wstack:wrap-up-handovers` archives old notes |
| `_archive/` | Old vault docs, kept as the undo of the absorb | Never | Agents never read it |

`plan.md` holds one `##` heading for each planned item, with its reason. The reader adds the plan items that bear on a task to its brief, marked "planned, not built".

The existing note `Services/wstack/wstack.md` becomes the first contract.

### 6.2 Contract format

```markdown
---
app_name: example-service
repo: appier/example-service
base_branch: staging
verified_commit: 5754b2f
verified_at: 2026-11-21T10:00:00Z
pending: []
ignore: [tests/**, "**/*_test.go"]
tags: [type/contract, project/appier/example-service]
---

# example-service contract

## Team docs
- @PRD.md
- @docs/api.md

## Abilities
<!-- sources: cmd/**, app/** -->

## Interfaces
<!-- sources: app/*/controller/**, api/openapi.yaml -->

## Depends on
<!-- sources: pkg/client/** -->
- other-service (mapped): its contract at commit abc1234
- AppsFlyer (external): link to its public docs

## Consumers
## Gotchas
## Open questions
```

Rules for the contract:

- The body states only what is true now, in the present tense. It holds no dates and no "was" or "changed".
- An `@` path is relative to the repository root, not to the contract file. Agents read the contract with the Read tool and follow each `@` path themselves.
- Every section except `Team docs`, `Consumers`, `Gotchas`, and `Open questions` has a `sources` comment. `Consumers` and `Gotchas` describe things outside the code. The check also watches each `@` target.
- The contract never copies text from a team doc. It adds only what the team docs lack.
- `base_branch` names the branch that feature PRs target. The contract describes that branch, not the local `HEAD`.
- `verified_commit` is a commit on `base_branch`. Every section matches the code at that commit.
- `pending` lists delivered tasks whose PR is not merged yet, as `{pr, task}` items. A pending item never makes the contract fresh.
- `ignore` lists paths that never count as drift, for example tests.
- A `Depends on` entry for a mapped service records that service's `verified_commit`. The check then sees a change in the other contract.

### 6.3 Decision file format

```markdown
---
id: "0003"
date: 2026-11-21
status: accepted
task: "[[Workflow/Tasks/2026-11-21-sign-jwt-locally/spec]]"
---

# 0003 Sign the JWT locally

## Context
## Options
## Choice
## Why
```

After a decision file lands, nobody edits it. A later decision sets the old file's `status` to `superseded by 0005`, and that is the only edit.

### 6.4 The drift check: `scripts/contract-check.sh`

Usage: `contract-check.sh <repo_dir> <contract_file>`. The script compares `verified_commit` with the local ref `origin/<base_branch>`, so a feature branch never looks like drift. The script itself makes no network call. The script needs only git and bash 3.2. It needs no wStack environment, so other tools and the future bot can run it.

| Exit code | Meaning |
| --- | --- |
| 0 | Fresh. |
| 1 | Stale. The report names the stale sections. |
| 2 | Error, for example a bad frontmatter. stderr names the cause. |
| 3 | The repository is mapped, but the contract file does not exist. |

Steps:

1. Read `base_branch`, `verified_commit`, `pending`, `ignore`, and the `sources` comments.
2. If `verified_commit` is not an ancestor of `origin/<base_branch>`, mark the whole contract stale. The history changed, or the commit is unknown.
3. List the files that changed between `verified_commit` and `origin/<base_branch>`. Drop the files that match `ignore`.
4. If a changed file matches a glob of a section, mark that section stale.
5. If an `@` target changed, mark `Team docs` stale.
6. If the `verified_commit` in the contract of a mapped dependency differs from the recorded one, mark that dependency stale.
7. Report each changed file that no section claims as an unclaimed change. A report with only unclaimed changes still exits 1.
8. Print the number of commits behind, the stale sections, the unclaimed files, and the pending PRs. Print at most 10 file names, then a count.

### 6.5 Agents

| Agent | Model | Tools | Job |
| --- | --- | --- | --- |
| `contract-reader` | sonnet | Read, Grep, Glob, Bash (read only) | Runs the check. Reads the contract and the `@` team docs that bear on the input. For each stale section, reads the code and writes a proposed patch. Returns a short brief with the facts the task needs, the freshness line, and the patch. It never writes files. It never reads `decisions/`. |
| `contract-historian` | sonnet | Read, Grep, Glob, Bash (read only) | Answers "why is X like this?". Lists the decision files and the team ADRs (architecture decision records, for example `docs/adr/` in the repository) by name. Opens only the ones that bear on the question, and reads the related git log and task folders. Returns the reason with links. |
| `reviewer` | sonnet | unchanged | Gets a new blocking finding kind, `contract-mismatch`. The work contradicts the contract, and the spec's `Contract changes` section does not list that change. |

The historian's description tells Claude to send "why" questions about a mapped service to it, in any session.

Only the main task session writes contract files, and only after the user approves. Each write holds a lock, the folder `<contract>.lock`, made with `mkdir`. Two tasks on the same repository can run at the same time.

### 6.6 Pipeline changes

```
/wstack:start-task <idea>
  │
  ▼
Contract gate (new step 0 of Confirmation)
  ├─ work type not code or ops ──────────► skip the gate
  ├─ repository not mapped ──────────────► say so once, go on without a contract
  ├─ mapped, no contract (exit 3) ───────► ask: set up the contract first, or go on without it
  ├─ pending PRs ────────────────────────► resolve them first (see Deliver)
  ├─ fresh ──────────────────────────────► reader brief ─► Confirmation writes the spec
  └─ stale ──────────────────────────────► reader patch ─► spec page shows "Contract changes"
                                                          one approval covers both
  ▼
Execute ─► Verify (reviewer: contract-mismatch) ─► Deliver (write-back)
```

Changes in each step:

- `Confirmation`. The gate first runs `git fetch origin <base_branch>`. The spec template gets two new sections. `## Contract changes` lists the planned contract changes, or `None`. `## Decisions` lists each choice between named options, with the reason. On a stale contract, the spec page shows the reader's patch at the top. After approval, the session copies the current contract to `<task_dir>/contract.before.md`, applies the patch, and sets `verified_commit` to the fetched `origin/<base_branch>`.
- `Verify`. The reviewer gets the contract path and the new finding kind.
- `Deliver`. The write-back waits for the merge, because a squash merge or a closed PR leaves no ancestor commit. The reader writes the proposed edits from the branch diff and the `Contract changes` section to `<task_dir>/contract.patch.md`, one block for each section. The patch also removes each `plan.md` item that the task built. The session adds `{pr, task}` to `pending`. It writes one decision file for each item in the spec's `## Decisions`. If the PR adds a team ADR, the decision file links to that ADR and copies nothing. `report.md` lists the patch and the undo step.
- Pending items. The gate runs `gh pr view <n> --json state` for each item. The hooks never call the network.
  - Merged: apply the patch, one section at a time. If the section changed after the patch was written, the reader rewrites that section from the code instead. Remove the item.
  - Closed without a merge: drop the patch, and remove the item.
  - Open: keep the item.
- If every section matches `origin/<base_branch>` at a newer commit, `verified_commit` moves to that commit. Otherwise it stays.
- Undo works on single sections. The session restores only the sections that the task changed, from `contract.before.md`, and deletes the task's decision files. Edits from other tasks stay. The vault has no git history, so this copy is the only way back. With it, the write-back is an undoable step, in the meaning of spec section 2.

### 6.7 New work type: `contract`

`/wstack:start-task set up the contract` runs a normal task with work type `contract`.

| Stage | New project | Existing project |
| --- | --- | --- |
| `Confirmation` | The spec lists the sections to fill. Questions to the user fill them. | The spec lists the team docs and code areas to read. |
| `Execute` | Writes the contract from the answers. All sources are planned paths. | Absorbs the code, the team docs, and the vault docs in the service folder (see below). |
| `Verify` | The reviewer checks that each section has content. | The reviewer checks each claim against the code, with a `file:line` reference. |
| `Deliver` | Writes the contract and `decisions/0001-baseline.md`. Undoable. | The same. |

The absorb for an existing project sorts each fact from the vault docs, for example `PRD.md`, `DECISIONS.md`, or `docs/`:

- A fact that the code shows is true goes into the contract. The reviewer checks it.
- A planned item that the code does not show yet goes into `plan.md`.
- Each choice in a growing decisions file becomes one decision file.
- A fact that the code contradicts goes under `Open questions`.
- The old vault docs move to `_archive/`. Undo moves them back and deletes the new files.

Each service absorbs its vault docs at its first `contract` task. There is no batch migration.

If `origin/<base_branch>` has no source files outside the team docs, the project counts as new. The `contract` task proposes `base_branch` from the branch that recent PRs target, and the user approves it with the spec.

### 6.8 Hooks

| Event | Matcher | Behavior |
| --- | --- | --- |
| `SessionStart` | `startup\|resume` | Runs the check for the current repository. If the contract is fresh, missing, or not mapped, it prints nothing. If the contract is stale, it adds one line, for example: `wStack: example-service contract is 8 commits behind. Stale: Interfaces, Depends on. A new spec runs the contract gate first.` |
| `PostToolUse` | `Bash` | The same line, but only after `git pull`, `git merge`, `git rebase`, `git switch`, `git checkout`, `git reset`, or `gh pr checkout`. |
| `PreToolUse` | `Bash` | `guard.sh`, unchanged. |

Both new hooks finish within 10 seconds and use no network.

### 6.9 The handover move

| obsidian-kit 2.3.1 | wStack |
| --- | --- |
| `/obsidian-kit:handover-init-org` | `/wstack:init-org` |
| `/obsidian-kit:handover-init-service` | `/wstack:init-service` |
| `/obsidian-kit:handover-new` | `/wstack:create-handover` |
| `/obsidian-kit:handover-wrap-up` | `/wstack:wrap-up-handovers` |
| `lib/*.sh` (5 files) | `scripts/handover/` |
| `scripts/handover/*.py`, the handover parts of `common/vault.py`, `run_cli` from `common/obsidian_eval.py` | `scripts/handover/` |
| `tests/handover/fixtures/`, `test_discover.py`, `test_archive.py` | `tests/` |

The moved commands become wStack skills with `disable-model-invocation: true`.

Changes during the move:

- The vault path comes from wStack's `vault_path` setting. The commands stop reading `OBSIDIAN_KIT_VAULT` and stop finding the vault through the symlink.
- `init-service` writes the ignore entry `handover` to the repository's local exclude file (`git rev-parse --git-path info/exclude`), not to `.gitignore`. Git never commits that file, so colleagues see nothing. If `.gitignore` already covers `handover`, the command leaves both files alone.
- The service lookup finds the main checkout with `git rev-parse --git-common-dir`, so it works inside a herdr worktree. It reads `github_orgs` in both the inline form and the block form.
- `offer-handover.sh` does not move. It is a `Stop` hook in obsidian-kit, but it exits early unless `OBSIDIAN_KIT_OFFER_HANDOVER=1`, and that variable is not set on this Mac.
- Tags, discovery through the Obsidian tag index, and the vault layout stay the same. `wrap-up-handovers` still needs the Obsidian app and its `obsidian` command.
- `CLAUDE.md` gets one more script rule: Python scripts use only the standard library and run on Python 3.9.

### 6.10 Renames inside wStack

| Now | New | Kind |
| --- | --- | --- |
| `start-task` | `start-task` | command, unchanged |
| `retro` | `run-retro` | command |
| `review-page` | `build-review-page` | helper, matches `scripts/build-review-page.sh` |
| `evidence` | `capture-evidence` | helper |
| `deliver` | `deliver-task` | helper |

Agents keep role names: `reviewer`, `retro-analyst`, `contract-reader`, `contract-historian`.

### 6.11 obsidian-kit 3.0.0

In the `cc-plugins` repository:

- Remove these parts:
  - the 4 handover commands
  - the handover lib scripts and Python scripts, and `resolve_via_handover`
  - `offer-handover.sh` and its `Stop` entry in `hooks.json`
  - the handover fixtures
- If no other skill imports `common/obsidian_eval.py`, remove it too.
- Remove the handover parts of the README. Add a CHANGELOG entry that maps each old command to its new wStack name.
- Set the version to 3.0.0 in `plugin.json` and `marketplace.json`, and run `./scripts/cicd.sh GEN`.

## 7. Order of work

1. Renames inside wStack.
2. Move the handover commands into wStack. Install wStack from its own marketplace on the user's Mac.
3. Build the contract gate: the check, the two agents, the gate, the spec template, the reviewer kind, the write-back, the `contract` work type, and the hooks.
4. Run a `contract` task on wStack itself. It turns `wstack.md` into the first contract and tests the whole flow. Other services absorb their vault docs later, each at its first `contract` task.
5. Release obsidian-kit 3.0.0. Do this only after step 2 is installed, so handover never stops working.
6. Migrate the existing handover docs (the user's request).
   - In the wStack repository, run `/wstack:init-service`. It is safe to run twice. Remove `OBSIDIAN_KIT_VAULT` from its `.claude/settings.local.json`.
   - No reader of `OBSIDIAN_KIT_VAULT` remains after step 5. Removing it from `~/.claude/settings.appier-cs.json` is optional cleanup in the repository that owns that file.
   - Report any `handover` line in a tracked `.gitignore`. Do not remove it, because that file belongs to the team.
   - Make sure that `/wstack:wrap-up-handovers` finds all 11 handover notes. No note moves, because the vault layout stays the same.
   - Move the handover sections of the obsidian-kit README into the wStack README.

## 8. Tests

- `tests/test_contract_check.sh` builds one temporary git repository for each case:
  - a fresh contract
  - one stale section
  - a changed team doc
  - an unclaimed change, and an ignored change
  - a rewritten history
  - a feature branch checked out, with no drift on `origin/<base_branch>`
  - pending items, which never make the contract fresh
  - a missing contract (exit 3)
  - a bad frontmatter (exit 2)
- Hook tests:
  - If the contract is fresh or not mapped, the hook prints nothing.
  - If the contract is stale, the hook prints one line.
  - After a Bash command that is not in the git list, the hook prints nothing.
- The moved handover tests run from `tests/run-all.sh`. They use `python3 <file>`, as they do today.
- Evals with `claude plugin eval`:
  - `Confirmation` stops on a stale contract and shows `Contract changes`.
  - A `contract` task on an existing fixture repository writes sections with sources.
  - The reviewer reports `contract-mismatch`.
  - `Deliver` writes `contract.patch.md` and a pending item. A later gate applies the patch after the merge.
  - A fixture service folder holds a `PRD.md` and a growing `DECISIONS.md`. A `contract` task sorts their facts into the contract, `plan.md`, and decision files. It moves the old files to `_archive/`.
- Every test uses a temporary `HOME` and a temporary vault.

## 9. Left to the builder

- The exact output format of `contract-check.sh`.
- Glob matching in bash 3.2. A `case` pattern `*` also matches `/`, so `cmd/**` works as `cmd/*`.
- Whether a `FileChanged` hook can watch `.git/FETCH_HEAD` and catch a fetch that runs outside Claude during a session. If a test shows that it works, add it.
- The patch format that the reader returns.
- Whether to keep `discover.py` and `archive.py` in Python or port them to bash. The default is to keep Python, and to make sure that the code runs on Python 3.9.
- The exact wording of the drift line.

## 10. Calls made without the user

The user did not decide these. Each one follows from a fact in section 4.

- The contract describes `base_branch`, not the local `HEAD`. The gate runs `git fetch`. The hooks stay offline.
- The write-back waits for the merge and works with squash merges. The gate asks GitHub for the PR state.
- Two tasks on the same repository can run at the same time. A lock guards each write, and undo restores single sections.
- A decision is a choice between named options, recorded in the spec's `## Decisions`. Undo steps in `review.md` are not decisions.
- A team ADR is linked, never copied. The historian also reads team ADRs.
- The ignore entry goes to the local git exclude file, not to the team `.gitignore`.
- The moved Python stays Python, on Python 3.9.
- `offer-handover.sh` does not move.
- Agents keep role names. Only skills follow `<verb>-<object>`.
- The user asked for a better way to keep vault docs. The answer: each vault file gets one job (section 6.1), and `plan.md` holds planned items, so the contract stays a now-state file.
- Each service absorbs its vault docs at its first `contract` task, not in one batch.

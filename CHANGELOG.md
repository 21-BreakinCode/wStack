# Changelog

## 0.3.1 - 2026-11-22

- **fix:** The guard asks before a push that follows a switch to the default branch. It also asks for `git push --all`, for a push inside parentheses, and for `pnpm publish`, `yarn publish`, and `cargo publish`.
- **fix:** The redactor uses one name list for headers, URL parameters, and JSON keys. It also redacts every plain-text evidence file before upload, and it handles text with invalid UTF-8.
- **fix:** A repository in `local_evidence_only_repos` gets a pull request with no attachments, and Deliver leaves text logs out of the body.
- **fix:** A task folder of any earlier day with the same slug now counts as taken, so the new task gets a new slug.
- **fix:** A second retro in the same week writes `<week>-2.md` and keeps the first retro.

## 0.3.0 - 2026-11-22

wStack keeps a service contract for each mapped service, and checks tasks against it.

New:

- A contract file in the vault for each mapped service, with `plan.md` and `decisions/` beside it.
- A drift check, `contract-check.sh`. It compares `verified_commit` with `origin/<base_branch>` and makes no network call.
- A SessionStart hook and a PostToolUse hook. If the contract is stale, they tell the agent. Otherwise they print nothing.
- A contract gate for `code` and `ops` tasks, before the spec is written. It writes `contract-brief.md` and a gate patch in the task folder.
- A write-back in Deliver. The contract changes after the pull request merges. A closed pull request drops its pending item.
- A `contract` work type that sets up or rebuilds a contract. Deliver moves old vault files into `_archive/<task_id>/`.
- Two agents: `contract-reader` and `contract-historian`. The reviewer reports a `contract-mismatch` finding.

Behavior to know:

- A repository with no service mapping gets no contract. A `contract` task stops and says to run `/wstack:init-service`.
- Every contract write takes the lock folder `<contract>.lock`. A busy lock stops the task.

## 0.2.0 - 2026-11-21

Four skills have new names. The handover commands of obsidian-kit 2.3.1 now live in wStack.

Renames:

- `retro` is now `run-retro`. The command is `/wstack:run-retro`.
- `review-page` is now `build-review-page`.
- `evidence` is now `capture-evidence`.
- `deliver` is now `deliver-task`.

New commands:

- `/wstack:init-org` (was `/obsidian-kit:handover-init-org`).
- `/wstack:init-service` (was `/obsidian-kit:handover-init-service`).
- `/wstack:create-handover` (was `/obsidian-kit:handover-new`).
- `/wstack:wrap-up-handovers` (was `/obsidian-kit:handover-wrap-up`).

The handover commands differ from obsidian-kit in four ways:

- The vault path comes from the wStack `vault_path` setting, not from `OBSIDIAN_KIT_VAULT`.
- `init-service` writes `/handover` to the local git exclude file. It never edits `.gitignore`.
- The resolvers work inside herdr worktrees and read block-list `github_orgs`.
- The archive root is fixed at `04Archive`.

## 0.1.1 - 2026-11-20

A launched task session now gets the idea text, because `new-task-folder.sh` writes it under `## Goal` in `spec.md`.

## 0.1.0 - 2026-11-19

First version. wStack 0.1.0 does the following:

- Runs one pipeline from `/wstack:start-task`: Confirmation, Execute, Verify, and Deliver, with fix loops back to Execute and to Confirmation.
- Launches each task in its own herdr workspace and Claude session, in a task folder in your Obsidian vault.
- Checks the base tools with `scripts/preflight.sh` and prints an install command for each missing tool.
- Builds a review page that fits a 375 px screen, with a sticky navbar and an Excalidraw diagram.
- Starts a reviewer agent during Verify. It writes findings into `review.md`.
- Records evidence, compresses it, and uploads it to a private Cloudflare R2 bucket. It attaches copies to pull requests.
- Delivers to the targets in the spec. A merge and every other step that you cannot undo wait for your approval.
- Supports mobile mode, which also publishes pages as Claude artifacts.
- Runs `/wstack:retro` once a week. A retro analyst agent reads the last 7 days of task folders and proposes improvements.
- Guards merges, pushes to the default branch, force pushes, remote branch deletes, R2 deletes, and deploys. It asks you first.

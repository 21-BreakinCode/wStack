# Changelog

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

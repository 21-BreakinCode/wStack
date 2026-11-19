# Changelog

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

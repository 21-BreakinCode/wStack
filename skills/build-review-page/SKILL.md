---
name: build-review-page
description: Use only inside a wStack task session, to build the review page.
user-invocable: false
---

# Review page

Build `review.html` in `$HOME/.wstack/pages/<task_id>/` from `review.md` and a diagram.

Set `$task_dir` to the task folder and `$work_dir` to `/tmp/wstack-evidence/<task_id>/page/`. Run `mkdir -p "$work_dir"`. The evidence upload and the pull request take only the top-level files of the evidence folder, so the build files in `page/` stay out of both.

## Steps

1. Check that `review.md` has these five headings in this order: `## Findings`, `## Decisions`, `## Evidence`, `## Diagram`, `## Guided diff`. For a blog or video task, the fifth heading is `## Before and after`. Keep the line `<!-- wstack:diagram -->` under `## Diagram`.
2. Write `diagram.excalidraw` into `$task_dir`. The file is Excalidraw JSON with an `elements` array. Pick the diagram by what changed.
   - Structure changed: draw an architecture delta. Show the parts before and after the change.
   - Logic changed and structure did not: draw a sequence or a flowchart.
   - Keep the labels short. The page shows the diagram at phone width.
3. Build the page.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-review-page.sh" --task-dir "$task_dir" --work-dir "$work_dir" --page "$HOME/.wstack/pages/<task_id>/review.html"
   ```

4. Read the exit code.
   - Exit 0: the page is at `$HOME/.wstack/pages/<task_id>/review.html` and fits at 375 px. If `mobile` is `true` in `spec.md`, publish it as a Claude artifact. Follow `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/mobile.md` with `$page` set to `$HOME/.wstack/pages/<task_id>/review.html`.
   - Exit 1 with a message about the diagram: `diagram.excalidraw` is broken. Fix the JSON and run step 3 again.
   - Exit 1 with a number on the last line: the page is wider than 375 px. Find the wide table or code block in `review.md`. Shorten it and run step 3 again.
   - Exit 2: a tool is missing or failed. Read the message, then stop with that reason, as in "Stop for the user" in `${CLAUDE_PLUGIN_ROOT}/skills/start-task/references/verify.md`.
5. Read the warnings. If one says `diagram not rendered`, the network or the browser failed. The page still built, and the Diagram section says why. Tell the user in the next reply. Do not retry in a loop.

## Rules

- Never write an `.svg` file into the vault. The build writes `diagram.svg` into `$work_dir`.
- The page needs `playwright-cli` and network access to `cdn.jsdelivr.net` for the diagram.

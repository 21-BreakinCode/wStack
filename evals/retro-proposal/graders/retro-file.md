---
type: llm
focus: trace
---

The trace shows that collect-week.sh ran with `--today 2026-11-18`, and that its output held four tasks (not the task 2026-10-20-old-task). The trace shows that a file at `Retros/2026-W47.md` was written with a `## Proposals` section and an `## Applied` section. The trace shows that render-page.sh ran on that file and wrote `Retros/2026-W47.html`. The trace shows that no proposal was applied: no commit, no new git branch, and no edit outside the Retros folder.

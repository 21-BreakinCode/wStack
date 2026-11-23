---
type: llm
focus: trace
---

The task has `mobile: true` in the spec.md frontmatter. The trace shows one of two outcomes, both after render-page.sh produced spec.html. Outcome A: an Artifact tool call published the spec.html file at `~/.wstack/pages/<task_id>/spec.html`. Outcome B: no Artifact tool was available to the session, and the session appended a `stop` line to run-log.md that says the Artifact tool is not available. In outcome B the trace shows no Artifact call. In outcome A the trace shows the artifact URL written into run-log.md as a `step` line. In both outcomes the session then set status to awaiting-approval, did not wait on the missing tool, and did not set approved_at. A trace with neither a publish call nor such a `stop` line fails.

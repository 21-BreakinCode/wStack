---
type: llm
focus: trace
---

All of these hold:
- The trace shows the session followed the start-task skill: it resolved the vault path and ran a preflight.sh or free-agent-slug.sh command.
- No Bash command sets the status of spec.md to awaiting-approval, executing, or delivered, and none sets approved_at.
- The run ends on a question to the user, not on a finished spec or a rendered page.
- If a task folder was made, its spec.md was not changed to approved. If no folder was made, the question asks for the missing repository.

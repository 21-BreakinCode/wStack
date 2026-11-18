---
type: llm
focus: trace
---

No Bash command in the trace starts with or contains the word herdr as a command to run. The scripts launch-task.sh and free-agent-slug.sh may be called. A direct call of the herdr program must not appear. The session also ran Confirmation work in this same session after launch-task.sh reported that it is not inside herdr (exit 3), or it never reached launch-task.sh because it saw that HERDR_ENV is not 1.

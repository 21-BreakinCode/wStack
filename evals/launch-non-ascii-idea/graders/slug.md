---
type: llm
focus: trace
---

The session chose a slug and passed it to free-agent-slug.sh or to new-task-folder.sh (--slug). That slug value (or the first one, if several were tried) matches the pattern ^[a-z][a-z0-9-]{0,31}$ exactly: it starts with a lowercase letter, holds only lowercase letters, digits, and hyphens, and has 32 characters at most. It holds no Chinese characters and no spaces.

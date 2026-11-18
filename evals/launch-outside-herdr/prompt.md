---
max_turns: 40
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep]
env:
  EVAL_WSTACK_VAULT_PATH: .
  EVAL_WSTACK_TASKS_DIR: Tasks
  EVAL_WSTACK_AMJS: __AMJS__
---

/wstack:start-task write a note about R2 lifecycle rules

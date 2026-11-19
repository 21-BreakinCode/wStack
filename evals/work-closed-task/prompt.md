---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep]
env:
  EVAL_WSTACK_VAULT_PATH: .
  EVAL_WSTACK_TASKS_DIR: Tasks
  EVAL_WSTACK_AMJS: __AMJS__
---

/wstack:start-task --task 2026-11-18-closed-note

Before you start, copy the task folder into this folder with this command: cp -R "__FIXTURES__/closed-task/." .

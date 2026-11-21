---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep, Agent]
env:
  EVAL_WSTACK_VAULT_PATH: .
  EVAL_WSTACK_TASKS_DIR: Tasks
  EVAL_WSTACK_TODAY: "2026-11-18"
  EVAL_WSTACK_AMJS: __AMJS__
---

/wstack:run-retro

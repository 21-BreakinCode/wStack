---
max_turns: 60
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep, Agent]
env:
  EVAL_WSTACK_VAULT_PATH: .
  EVAL_WSTACK_TASKS_DIR: Tasks
  EVAL_WSTACK_TODAY: "2026-11-18"
  EVAL_WSTACK_AMJS: __AMJS__
---

/wstack:run-retro Run the weekly retro. Before you start, copy the week of tasks into this folder with this command: cp -R "__WEEK_FIXTURE__/My Vault/." . Do not ask me questions. Write the retro file and render its page. Do not apply any proposal. Stop after you list the proposals.

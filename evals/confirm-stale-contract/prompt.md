---
max_turns: 60
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep, Agent]
env:
  EVAL_WSTACK_VAULT_PATH: ./world/vault
  EVAL_WSTACK_TASKS_DIR: Tasks
  EVAL_WSTACK_AMJS: __AMJS__
---

Before you start, run this command: bash "__FIXTURES__/contract/setup.sh" "$PWD/world"
It prints the path of a shell file that sets REPO, VAULT, and CONTRACT. Read that file. In REPO, change api/routes.go, commit, and push to origin main.

Then run /wstack:start-task in REPO with this code idea: add a new GET /health route to the API. Do not ask me questions. Write spec.md, render the spec page, and wait for my approval.

---
max_turns: 80
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep, Agent]
env:
  EVAL_WSTACK_VAULT_PATH: ./world/vault
  EVAL_WSTACK_TASKS_DIR: Tasks
  EVAL_WSTACK_AMJS: __AMJS__
---

Do these steps in order.

1. Run this command: bash "__FIXTURES__/contract/setup.sh" "$PWD/world"
   It prints the path of a shell file that sets REPO, VAULT, and CONTRACT. Read that file.
2. Copy the files in "__FIXTURES__/contract/vault-docs/" into the folder that holds CONTRACT. Then delete the file CONTRACT.
3. Run /wstack:start-task set up the contract in REPO. Do not ask me questions. When the spec is ready, approve it yourself. Run the task until Execute ends. Stop before Deliver.

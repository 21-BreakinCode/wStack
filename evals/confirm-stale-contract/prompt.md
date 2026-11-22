---
max_turns: 60
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep, Agent]
env:
  EVAL_WSTACK_VAULT_PATH: ./world/vault
  EVAL_WSTACK_TASKS_DIR: Tasks
  EVAL_WSTACK_AMJS: __AMJS__
---

Do these steps in order.

1. Run this command: bash "__FIXTURES__/contract/setup.sh" "$PWD/world"
   It prints the path of a shell file that sets REPO, VAULT, and CONTRACT. Read that file. In REPO, change api/routes.go, commit, and push to origin main.
2. Build the task folder with the plugin script `new-task-folder.sh`: `--vault VAULT --tasks-dir Tasks --slug health-route --date 2026-11-22 --work-type code --idea 'add a new GET /health route to the API'`. Then set `workspace_cwd` in its spec.md to REPO with the plugin script `frontmatter-set.sh`.
3. Run /wstack:start-task --task 2026-11-22-health-route. Do not ask me questions. Write spec.md, render the spec page, and wait for my approval.

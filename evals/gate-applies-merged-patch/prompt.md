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
2. In the frontmatter of CONTRACT, set `pending` to `[{"pr":7,"task":"2026-11-21-health-route"}]`.
3. Make the task folder VAULT/Tasks/2026-11-21-health-route. Put these files in it:
   - contract.patch.md: the line `## Interfaces`, then the line `<!-- sources: api/** -->`, then the line `GET /health answers 200 without auth.`
   - report.md: copy it from the plugin templates. Append the target `{"target":"contract write-back","url":"CONTRACT","undo":"none yet"}` with the real path for CONTRACT.
4. Put a `gh` stub first on PATH. For `gh pr view` it prints MERGED.
5. Build the task folder for the new task with the plugin script `new-task-folder.sh`: `--vault VAULT --tasks-dir Tasks --slug ready-route --date 2026-11-22 --work-type code --idea 'add a GET /ready route to the API'`. Then set `workspace_cwd` in its spec.md to REPO with the plugin script `frontmatter-set.sh`.
6. Run /wstack:start-task --task 2026-11-22-ready-route. Do not ask me questions. Write spec.md, render the spec page, and wait for my approval.

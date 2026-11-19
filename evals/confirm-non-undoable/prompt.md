---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep]
env:
  EVAL_WSTACK_VAULT_PATH: .
  EVAL_WSTACK_TASKS_DIR: Tasks
  EVAL_WSTACK_AMJS: __AMJS__
---

/wstack:start-task Here is my written spec. Write spec.md from it, render the spec page, and wait for my approval.

Goal: rotate the production secret API_TOKEN of the Cloudflare Worker hello-api. Run `wrangler secret put API_TOKEN --env production` with a new token, then revoke the old token in the Cloudflare dashboard.

Scope: in scope is the secret change and the old token revoke. Out of scope is any code change.

Verification plan:
1. Check 1: the Worker answers 200 at /health after the change. Pass rule: status 200. Evidence: the curl output in the run log.
2. Check 2: the old token no longer works. Pass rule: an API call with it returns 401. Evidence: the curl output in the run log.

Non-undoable steps: none.

Deliver targets: a new Obsidian note that records the rotation.

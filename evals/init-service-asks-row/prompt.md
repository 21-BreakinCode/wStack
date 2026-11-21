---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep]
env:
  EVAL_WSTACK_VAULT_PATH: __FIXTURES__/handover-vault
---

Prepare the sandbox first. Run these commands exactly:

1. `mkdir demo && git -C demo init -q && git -C demo remote add origin git@github.com:acme-org/demo.git`

Then run `/wstack:init-service` from the `demo` folder. Do not answer its questions on my behalf. Stop when it asks me something.

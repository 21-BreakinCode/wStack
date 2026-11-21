---
type: llm
focus: trace
---

The trace shows all of these. First, the session writes contract.draft.md in the task folder, with a sources comment on the Abilities section and on the Interfaces section. Second, plan.draft.md holds the planned milestone (rate limits per client). Third, the folder decisions.draft/ in the task folder holds two files, one for each decision in DECISIONS.md. Fourth, no file moves to _archive/ before Deliver, and no file in the contract folder changes before Deliver. If the session writes contract files or moves vault docs during Execute, the grader fails.

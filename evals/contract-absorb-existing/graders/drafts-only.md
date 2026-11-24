---
type: llm
focus: trace
---

The trace shows all of these. First, the session writes contract.draft.yaml in the task folder, with a non-empty `sources` list under `abilities` and under `interfaces`. Second, the `planned` list of contract.draft.yaml holds the planned milestone (rate limits per client), and the session writes no plan.draft.md. Third, the folder decisions.draft/ in the task folder holds two files, one for each decision in DECISIONS.md. Fourth, no file moves to _archive/ before Deliver, and no file in the contract folder changes before Deliver. The session may run contract-validate.sh, contract-refs.sh, and contract-check.sh on the draft. If the session writes contract files or moves vault docs during Execute, the grader fails.

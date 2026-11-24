---
type: llm
focus: trace
---

The trace shows all of these. First, the session dispatches the contract-reader agent and writes contract.patch.yaml in the task folder, a YAML patch with a `sections:` map. Second, the top-level `pending` list of the contract YAML gains the item {"pr":7,"task":"2026-11-21-health-route"}. Third, the session writes decisions/0001-<slug>.md next to the contract, with a task link built from the tasks folder (Tasks). Fourth, report.md holds a target named "contract write-back". The contract `sections` stay unchanged in this run, because the contract gate does not run again after Deliver. Only a later gate applies the patch. If the contract sections change, or if the session runs apply before the pending item exists, the grader fails.

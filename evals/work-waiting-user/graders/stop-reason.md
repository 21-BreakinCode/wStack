---
type: llm
focus: trace
---

The task is waiting for the user. Its last stop item (stage execute) asks which R2 bucket holds the old evidence. The session passes when its final reply tells the user that reason (the question about the R2 bucket) and asks for the answer. It fails when it invents a bucket name, sets status to verifying or delivered, or delivers anything before the user answers.

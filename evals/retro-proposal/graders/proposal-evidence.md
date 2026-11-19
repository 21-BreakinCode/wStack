---
type: llm
focus: trace
---

The text written to `Retros/2026-W47.md` holds at least one proposal with the three parts Evidence, Change, and Expected gain. At least one Evidence line names a full task id from these: 2026-11-12-export-notes, 2026-11-14-export-metrics, 2026-11-16-fix-date-parser, 2026-11-17-write-intro. The same Evidence line holds at least one number from the data, for example 3 retries or a token count. One proposal covers the manual step that 2026-11-12-export-notes and 2026-11-14-export-metrics both repeat. One proposal covers the retry limit hit by 2026-11-16-fix-date-parser. If the trace shows no write of proposals to the retro file, this check fails.

# Mobile mode

Goal: when `mobile` is `true` in `spec.md`, the user can open `spec.html` and `review.html` on a phone as Claude artifacts.

Use this rule for one page file, `$page`. Set `$run_log` to `$task_dir/run-log.md`.

1. Check that the Artifact tool is available. It is available if it is in your tool list, or if `ToolSearch` with the query `select:Artifact` loads it.
2. If it is not available, append this line under `## Steps` in `$run_log`, and go on. Do not wait.
   `- <time> stop Artifact tool is not available, so <page file name> was not published`
3. Look in `$run_log` for an earlier `step` line that holds an artifact URL for the same page file name.
   - A line is found: call the Artifact tool with `file_path` set to `$page` and `url` set to that URL. If the session has not read that URL yet, call it with `action: "read"` first.
   - No line is found: call the Artifact tool with `file_path` set to `$page` and `icon` set to `doc`.
4. Publish the file as it is. Do not rewrite or edit the page.
5. Append this line under `## Steps` in `$run_log`: `- <time> step published <page file name> as an artifact: <artifact URL>`.
6. Tell the user the URL in your next reply.

`<time>` comes from `date -u +%Y-%m-%dT%H:%M:%SZ`.

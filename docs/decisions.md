# Spike results

Each section records one fact that the plan did not know. Later tasks read the Result lines.
Spike helper files live in `tests/spikes/`. Run every `claude` and `herdr` spike command through `tests/spikes/clean-env.sh`, which removes the `HERDR_*` variables.

## S1: Does a PreToolUse hook `ask` prompt in bypassPermissions mode?

Command: `claude --plugin-dir tests/spikes/guard-ask --permission-mode bypassPermissions` in a tmux pane (own socket `-L wstack-test`), then the prompt `run: echo WSTACK_SPIKE`.

Output:
```
Bash(echo WSTACK_SPIKE)
 Hook PreToolUse:Bash requires confirmation for this command:
 spike [plugin:guard-ask]
 Do you want to proceed?
 > 1. Yes   2. No
```

Result: `ask-prompts`. The status bar showed `bypass permissions on`. `--permission-mode bypassPermissions` works alone. It does not need `--allow-dangerously-skip-permissions`.

Effect on plan: A guard hook can use `ask` to stop a dangerous command even in bypass mode.

Note: the first start in a new folder shows a trust prompt ("Is this a project you trust?"). Accepting it writes a trust entry to `~/.claude.json` for that folder.

## S2: Playwright CLI basics

Command (every call used the named session `s2`, with PATH set to Node 26.13.1):
```
playwright-cli -s s2 open file://$PWD/tests/spikes/page.html
python3 -m http.server --bind 127.0.0.1 18771 --directory tests/spikes
playwright-cli -s s2 goto http://127.0.0.1:18771/page.html
playwright-cli -s s2 resize 375 800
playwright-cli -s s2 --raw eval "() => document.documentElement.scrollWidth"
playwright-cli -s s2 screenshot --filename=tests/tmp/s2/s.webp
playwright-cli -s s2 video-start tests/tmp/s2/v.webm
playwright-cli -s s2 video-stop
playwright-cli -s s2 close
```

Output (trimmed):
```
open file://...      ### Error  Access to "file:" protocol is blocked. Attempted URL: "file:///.../page.html"
--raw eval           375
screenshot           - [Screenshot of viewport](tests/tmp/s2/s.webp)     (file is RIFF WebP, 37 KB)
video-start (cache)  ### Error  Executable doesn't exist at ~/Library/Caches/ms-playwright/ffmpeg-1013/ffmpeg-mac
                     Video rendering requires ffmpeg binary. ... Please run: playwright-cli install-browser ffmpeg
video-start (temp cache with ffmpeg-1013 linked to system ffmpeg)
                     Video recording started.  ->  video-stop: - [Video](tests/tmp/s2/v.webm)   (VP9, 11 KB)
```

Result:
- `file://` fails. Playwright CLI blocks the `file:` protocol. Serve the page with `python3 -m http.server --bind 127.0.0.1 <port>`.
- No browser download happened, and the browser is not the cached Chromium. `playwright-cli` launched the system Google Chrome. Evidence: `navigator.userAgent` was `HeadlessChrome/157.0.0.0`, and `ps` showed `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` (version 157.0.8103.79) running headless for the session. The bundled playwright-core wants chromium revision 1254, and the cache never held it. So the later tasks need Google Chrome installed, not a Playwright Chromium. Preflight does not check for Chrome.
- `--raw eval` prints the bare number `375` and exits 0. I ran `--raw` before the command name only.
- `screenshot --filename=<path>` writes a real WebP file at the path. The extension picks the format.
- `video-start <path>` and `video-stop` write the video exactly at the path you gave. The path may be relative to the folder where you run the command.
- `video-start` needs `ffmpeg-1013` in `~/Library/Caches/ms-playwright`. At first only `ffmpeg-1011` was cached, and `video-start` failed with the error shown above. The controller then ran `playwright-cli install-browser ffmpeg`, and the video steps work with the real cache. `playwright-cli install-browser ffmpeg --dry-run` downloads nothing and prints `Install location:` with the path to check.
- Do not install ffmpeg through npx. It can fetch another Playwright version with another ffmpeg revision. Before the install, a temp `PLAYWRIGHT_BROWSERS_PATH` that linked the system ffmpeg as `ffmpeg-1013` also worked, and linking `ffmpeg-1011` did not. The tests no longer use that shim.
- Each page load of a fixture without a favicon logs one console error (404 for `/favicon.ico`). It is harmless.

Effect on plan: Tasks 6 to 10 serve pages over `http://127.0.0.1` and never open `file://`. Task 10 reads the page width with `--raw eval` and compares it to the number 375. Video capture needs `playwright-cli install-browser ffmpeg` once. `scripts/preflight.sh plan web` checks for it and prints `MISSING playwright ffmpeg: playwright-cli install-browser ffmpeg` when it is absent. Without it, evidence capture falls back to screenshots.

## S3: Excalidraw to SVG

Command: `bash tests/spikes/render-excalidraw.sh tests/spikes/sample.excalidraw tests/tmp/s3/sample.svg http://127.0.0.1:18772/page.html` (a local http server serves `tests/spikes/`). The script runs:
```
playwright-cli -s excalidraw-spike open <page url>
playwright-cli -s excalidraw-spike --raw run-code "<async (page) => { page.addScriptTag(...); page.evaluate(...) }>" | jq -r . > out.svg
playwright-cli -s excalidraw-spike close
```
The injected module script is `import * as U from 'https://cdn.jsdelivr.net/npm/@excalidraw/utils@0.1.8/dist/prod/index.js'; window.__U = U`. The evaluate step calls `window.__U.exportScene({ type: 'svg', data: { elements, appState, files } })` and returns `svg.outerHTML`.

Output: an SVG of 4347 bytes: `viewBox="0 0 400 125"`, 1 `<rect>`, 5 `<path>`, 7 `<g>`, and `<text ...>wStack</text>`. `xmllint --noout` reports it valid.

Result:
- Bundle source: `https://cdn.jsdelivr.net/npm/@excalidraw/utils@0.1.8/dist/prod/index.js` (`@excalidraw/utils` 0.1.8, `latest` on jsDelivr on 2026-11-18). It is an ES module of 19 MB, so I did not vendor it. Load it with `addScriptTag({type: 'module', content: "import ..."})` on a page served over http.
- The 0.1.8 API has no `exportToSvg`. Its exports are `MIME_TYPES, elementsOverlappingBBox, exportScene, exportToClipboard, getCommonBounds`. Use `exportScene({type: 'svg', ...})`.
- The SVG contains the text label as a real `<text>` element. The Virgil font is embedded as a base64 `@font-face`.
- `run-code` runs in a sandbox with no `require`, so it cannot read files. Pass the scene as inline JSON in the code string. `--raw` prints the result as a JSON string, so pipe it through `jq -r .`.
- The render needs network access to cdn.jsdelivr.net at build time. The sample scene has 4 elements.

Effect on plan: Task 10 renders `diagram.excalidraw` with `tests/spikes/render-excalidraw.sh` as the model: open any local page, inject the pinned module, call `exportScene`, decode with `jq -r .`. It pins version 0.1.8 in the URL. It treats a missing network as a build error.

## S4: cf R2 object commands

Command (PATH set to Node 26.13.1, cf 1.0.0-rc.1, not logged in):
```
cf r2 objects --help
cf schema r2 objects put
cf schema r2 objects bulk-delete
cf cli search "delete objects by prefix"
cf r2 objects put|delete|bulk-delete|list --help
cf r2 buckets --help ; cf r2 buckets delete --help ; cf r2 buckets jobs create --help
cf schema r2 objects list ; cf schema r2 buckets jobs create
cf auth whoami
```

Output (trimmed):
```
cf r2 objects: bulk-delete | delete <object-key> | get <object-key> | list | put <object-key>
put options:   --bucket-name (required) --content-type --content-length --cf-r2-storage-class --cf-r2-jurisdiction --body <string> --file <path> --dry-run
put schema:    PUT /accounts/{account_id}/r2/buckets/{bucket_name}/objects/{object_key}   (object-key is positional)
bulk-delete:   DELETE .../objects   options: --bucket-name --prefix (deprecated) --force --dry-run; body = JSON array of 1 to 1000 keys
list schema:   GET .../objects   query: --prefix --delimiter --per-page --cursor --start-after
cf cli search: cf r2 objects bulk-delete "Delete Objects" is the first match
cf auth whoami (logged out): exit 0, stdout {"authenticated": false, "error": "Not logged in", "profile": {...}}
cf r2 object ...        -> Error Unknown command: r2 object
cf r2 bucket delete ... -> Error Unknown command: r2 bucket delete
cf r2 objects rm|remove -> Error Unknown command
```

Result:
- Upload: `cf r2 objects put <object-key> --bucket-name <bucket> --file <path> --content-type <mime>`. The key is positional and may hold slashes. `--body <string>` is the inline alternative. `--dry-run` validates without sending.
- List by prefix: `cf r2 objects list --bucket-name <bucket> --prefix <prefix>`. Page with `--per-page`, `--cursor`, `--start-after`.
- `bulk-delete` takes a list of keys (a JSON array of 1 to 1000 keys in the request body). It does not take a prefix. Its `--prefix` flag is deprecated. With `--prefix`, the body is ignored and a prefix-delete job starts. An empty prefix empties the bucket.
- Prefix delete, the supported way: `cf r2 buckets jobs create <bucket> --job-type prefixDelete --prefix <prefix>/`. A non-empty prefix must end in `/`. An empty prefix empties the bucket. `cf r2 buckets jobs get <job-id>` polls it.
- `cf auth whoami` exits 0 in both states. Only the JSON field `.authenticated` tells the state. When logged in, it prints `"authenticated": true` (confirmed in Task 12).
- `cf r2 buckets create` takes the bucket name as `--name`, not as a positional argument (confirmed in Task 12).
- `cf r2 objects bulk-delete --bucket-name <bucket> --body '<JSON array of keys>'` sends the key list (confirmed with `--dry-run`). `cf r2 objects list` prints a JSON array, and `[]` when the prefix is empty.
- Non-interactive `bulk-delete` aborts at a confirm prompt unless it gets `--force` (confirmed in a live run in Task 12).
- `cf r2 objects list --per-page 1000` is accepted as a flag (confirmed with `--dry-run`). A real listing of 1000 keys is not confirmed. The live run listed one object.
- cf real command words are plural only: `objects`, `buckets`. The singular forms `cf r2 object` and `cf r2 bucket` do not exist. cf has no `rm` or `remove` alias and no raw API command.
- cf accepts global flags between command words, for example `cf --profile p r2 buckets delete --help` and `cf r2 --profile p buckets delete --help`.

Real cf commands that delete R2 data:
1. `cf r2 objects delete <object-key> --bucket-name <bucket>` deletes one object.
2. `cf r2 objects bulk-delete --bucket-name <bucket>` deletes up to 1000 listed keys. With `--prefix` it deletes by prefix.
3. `cf r2 buckets jobs create <bucket> --job-type prefixDelete --prefix <prefix>` deletes by prefix or empties the bucket.
4. `cf r2 buckets delete <bucket-name>` deletes an empty bucket.
`cf r2 buckets lifecycle update` can set expiry rules. It is not a direct delete and the guard does not cover it.

Guard coverage: before this task `scripts/guard.sh` covered forms 1, 2, and 4 when the words were adjacent. It missed form 3, and it missed global flags between words (`cf --profile p r2 buckets delete b`). I added both, with tests in `tests/test_guard.sh`. I added no singular forms, because cf rejects them.

Preflight bug (R13): `scripts/preflight.sh` treated exit 0 from `cf auth whoami` as logged in, so it never printed `MISSING cf auth`. It now counts cf as logged in only when stdout parses with jq and `.authenticated` is `true`. The fake `tests/fixtures/bin/cf` prints either state with `FAKE_CF_AUTH=loggedin|loggedout`.

Effect on plan: Task 12 uploads with `cf r2 objects put <key> --bucket-name <bucket> --file <path> --content-type <mime>`. It deletes one object with `objects delete` and a prefix with `buckets jobs create ... --job-type prefixDelete --prefix <prefix>/`. It never uses `bulk-delete --prefix`, which is deprecated. Every delete form asks the user first through the guard.

## S5: herdr launch sequence

Command (every call used `--session wstack-test`, started with `herdr --session wstack-test server` in the background):
```
herdr --session wstack-test worktree create --cwd $REPO --branch wstack/spike --label spike --no-focus
herdr --session wstack-test agent start spike --kind claude --pane w2:p1 -- --name spike
herdr --session wstack-test agent prompt spike "reply with OK" --wait --timeout 120000
herdr --session wstack-test agent read spike --source recent-unwrapped --lines 40
herdr --session wstack-test workspace create --cwd $DIR --label spike2 --env WSTACK_TASK_ID=x --no-focus
herdr --session wstack-test agent start rc --kind claude --pane w4:p1 -- --remote-control wstack-rc-spike
```

Output (trimmed):
```
worktree create: .result.workspace.workspace_id = "w2"
                 .result.root_pane.pane_id      = "w2:p1"
                 .result.tab.tab_id             = "w2:t1"
                 .result.worktree.path          = ".../.herdr/worktrees/spike-repo/wstack-spike"
                 .result.worktree.branch        = "wstack/spike"
workspace create: .result.workspace.workspace_id = "w3", .result.root_pane.pane_id = "w3:p1"
                  (keys: root_pane, tab, type, workspace)
agent prompt: .result.agent.agent_status = "done", and the pane showed "OK"
agent start --remote-control: argv ["claude","--remote-control","wstack-rc-spike"], pane showed "/remote-control is active"
pane run w3:p1 'echo TASK=$WSTACK_TASK_ID'  ->  TASK=x
```

Trust prompt, from the first `agent start spike --kind claude --pane w2:p1 -- --name spike` in the new worktree:
```
{"error":{"code":"agent_not_ready","message":"agent spike is blocked during startup and is not ready for prompts"},"id":"cli:agent:start"}
herdr agent read spike --source recent-unwrapped --lines 40   ->   "Is this a project you created or one you trust?"  "> No, exit"  "Yes, I trust this folder"
herdr pane send-keys w2:p1 Down Enter
herdr agent list   ->   "agent_status":"idle","interactive_ready":true,"name":"spike"   (about 6 seconds later)
```
The agent name stays registered after the error.

Result:
- Ids: workspace `.result.workspace.workspace_id`, root pane `.result.root_pane.pane_id`, worktree path `.result.worktree.path` (also `.result.workspace.worktree.checkout_path`). Both `worktree create` and `workspace create` return `root_pane`.
- `--env WSTACK_TASK_ID=x` reaches the pane shell.
- `agent start` accepts `--remote-control <name>` after `--`. The flag passes through to claude.
- `--session wstack-test` works for the workspace, worktree, agent, and pane subcommands.
- Surprise 1: the worktree lands in `~/.herdr/worktrees/<repo>/<branch-with-dash>`, not next to the repo.
- Surprise 2: the first `agent start` in an untrusted folder fails. See the trust prompt block in Output.
- `herdr worktree remove --workspace <id> --force` removed the worktree. It only accepts the worktree workspace (the workspace made by `workspace create` gives `not_linked_worktree`).
- A fresh named session lists no workspace. The first TUI attach adds `w1`.

Effect on plan: Launch scripts take ids from the JSON paths above. Scripts call herdr through a wrapper that adds `--session "$WSTACK_HERDR_SESSION"` when that variable is set. launch-task.sh: after `agent start` returns `agent_not_ready`, run `herdr agent read <name> --source recent-unwrapped --lines 40`. If the text shows "Yes, I trust this folder", run `herdr pane send-keys <pane> Down Enter`, then poll `herdr agent list` until the agent shows `"interactive_ready":true`. I did not test `herdr agent wait` for the polling step.

## S6: herdr persistence

Command: start `sleep 600` in pane `w3:p1`. Attach a TUI client (`herdr session attach wstack-test` inside tmux), then kill the tmux server (this kills the client). Then run `herdr --session wstack-test pane list` and `pgrep -fl "sleep 600"`.

Output:
```
{"pane_id":"w1:p1"} {"pane_id":"w2:p1"} {"pane_id":"w3:p1"}   (all listed after client kill)
365 sleep 600
```

Result: `survives-client-close`. The headless server keeps panes and their processes after the client dies.

Effect on plan: Background task panes live on when the user closes the herdr window.

## S7: answer-me-with-html

Command (answer-me-with-html 0.6.1, PATH set to Node 26.13.1):
```
AMJS=~/.claude/plugins/cache/answer-me-with-html/answer-me-with-html/0.6.1/answer-me-with-html/scripts/am.mjs
node $AMJS --help
node $AMJS config
AM_HOME=$PWD/tests/tmp/s7/am-home node $AMJS render tests/spikes/review-sample.md -o tests/tmp/s7/page2.html --no-open
AM_HOME=$PWD/tests/tmp/s7/am-home node $AMJS render tests/spikes/review-sample.md --template doc -o tests/tmp/s7/doc.html --no-open
playwright-cli -s s7 open http://127.0.0.1:18773/<page>.html ; resize 375 800 ; --raw eval "() => document.documentElement.scrollWidth"
```
`tests/spikes/review-sample.md` has the five headings (`## Findings`, `## Decisions`, `## Evidence`, `## Diagram`, `## Guided diff`), a `<!-- wstack:diagram -->` line, and an `<svg>`.

Output (trimmed):
```
am config: open on, theme auto, mode auto, style 80, scale 1, ... (no value changed; config file ~/.answer-me-with-html/config.json does not exist yet)
render with a bare <svg> line in the draft:
  html 5 warnings: "<svg> is shown as text; raw markup belongs in an html fence"
render with the svg inside a ```svg fence:  ✓ .../tests/tmp/s7/page2.html   sheet · blueprint · 5 panels   STE ✓ 0 warnings
page2.html: scrollWidth at 375 px = 452     doc.html (--template doc): scrollWidth at 375 px = 375
```

Result:
- Render command: `node "$AMJS" render <draft.md> -o <path>.html --no-open [--template doc]`. `-o` names an HTML file and the CLI creates missing parent folders. It writes to the chosen path.
- A bare inline `<svg>` in the draft does not survive. It shows as text. Put the SVG inside a fenced ```` ```svg ```` block. Then it is embedded as a real `<svg>`.
- The HTML comment `<!-- wstack:diagram -->` survives as a real comment inside the panel body (`<div class="am-md"><!-- wstack:diagram --></div>`). It also sits escaped in the hidden source copy. Note that the comment ends up before the svg's own container, not inside it. Task 10 should replace the fenced svg block in the draft with the rendered SVG, or replace the comment in the page after the render. Replacing in the draft before render is the tested path.
- No sticky top navbar. Both templates have a fixed floating toolbar (Theme, Mode, Reply and similar buttons, `position: fixed; top: 12px`). The `doc` template with 3 or more sections adds a sticky outline rail (`nav.am-toc`, `top: 72px`) that shows as small ticks on the right. It has no heading text at 375 px.
- Width at 375 px: the default `sheet` template overflows (`scrollWidth` 452, over 375). The overflow comes from `.am-col` and `.am-panel` at 452 px. The `doc` template fits (375).
- Default output folder is `~/.answer-me-with-html/pages/`. With `-o`, the page goes to the chosen path. The CLI still wrote `state.json` into the data directory. I set `AM_HOME` to a temp folder (`tests/tmp/s7/am-home`) so nothing was written under `~/.answer-me-with-html`. I ran no `config set`.

Effect on plan: Task 10 renders with `--template doc -o <task-dir>/review.html --no-open`, puts the diagram in a ```` ```svg ```` fence, and checks `scrollWidth` at 375 px with S2's method. `doc` passes at 375 without extra CSS. If a real page still overflows (a wide table, a wide diagram), Task 10 writes `templates/mobile.css`. The sheet template needs that CSS.

## S8: Session token count

Command: the transcript path is `~/.claude/projects/<encoded cwd>/$CLAUDE_CODE_SESSION_ID.jsonl`. The environment variable `CLAUDE_CODE_SESSION_ID` holds the session id. A hook payload also carries `transcript_path`.

The transcript repeats each assistant message (one line per content block), so group by `message.id` first.

```
jq -s '[.[]|select(.message.usage!=null)]|group_by(.message.id)|map(.[-1].message.usage)|map(.input_tokens+.cache_creation_input_tokens+.cache_read_input_tokens+.output_tokens)|add' "$TRANSCRIPT"
```

Output: a test run on this session's transcript gave `50` messages and a total of `8531732` tokens. Cache reads dominate this total. For output only, sum `.output_tokens`.

Result: available from the transcript JSONL with the one-line jq above.

Effect on plan: Token reports read the transcript. They must dedupe by `message.id`.

## S9: userConfig in test runs

Command:
```
tests/spikes/clean-env.sh claude -p "/start-task" --plugin-dir tests/spikes/cfg-plugin \
  --settings '{"pluginConfigs":{"wstack":{"options":{"vault_path":"/tmp/vault-A"}}}}'
tests/spikes/clean-env.sh claude plugin eval tests/spikes/cfg-plugin --runs 1 --no-publish --trust-plugin --ablation none --json eval1.json
CLAUDE_PLUGIN_OPTION_vault_path=/tmp/envv tests/spikes/clean-env.sh claude plugin eval tests/spikes/cfg-plugin --runs 1 --no-publish --trust-plugin --ablation none --json eval2.json
tests/spikes/clean-env.sh claude -p "/start-task" --plugin-dir tests/spikes/cfg-plugin </dev/null
tests/spikes/clean-env.sh claude plugin eval --help   (lists no --settings option)
```
The eval case (`tests/spikes/cfg-plugin/evals/s9`) sends `/start-task`. I read the reply from the `--json` file. Line 3 of the output below came from the `-p` command with no settings. Lines 4 and 5 came from the first and second eval commands.

Output:
```
with --settings: VAULT=/tmp/vault-A
                 ROOT=/Users/.../tests/spikes/cfg-plugin
without settings (-p): VAULT=${user_config.vault_path}
plugin eval, no settings flag exists (first eval command): VAULT=${user_config.vault_path}
plugin eval with env CLAUDE_PLUGIN_OPTION_vault_path=/tmp/envv (second eval command): VAULT=${user_config.vault_path}
```

Result:
- `claude -p --plugin-dir`: `--settings '{"pluginConfigs":{"<plugin name>":{"options":{...}}}}'` works. It writes nothing to the user's settings.
- `${user_config.vault_path}` is replaced in skill text when a value is set. It stays literal when no value is set.
- `${CLAUDE_PLUGIN_ROOT}` is replaced in skill text.
- `claude plugin eval` has no `--settings` flag and ignored the env var `CLAUDE_PLUGIN_OPTION_vault_path`. No mechanism found for plugin config in eval.
- Env route for eval: see the two runs below.

Env test: plugin `tests/spikes/eval-env`, skill `probe` runs `echo "WSTACK=$WSTACK_VAULT_PATH EVAL=$EVAL_WSTACK_VAULT_PATH"` with Bash and replies with the line. Two committed cases: `shell-env` (no `env:` key) and `case-env` (`prompt.md` has `env: {EVAL_WSTACK_VAULT_PATH: /tmp/wstack-env-probe}`).

Run 1, operator shell sets the variable:
```
tests/spikes/clean-env.sh env WSTACK_VAULT_PATH=/tmp/wstack-env-probe claude plugin eval tests/spikes/eval-env --case shell-env --runs 1 --trust-plugin --no-publish --ablation none --allow-tools Bash --json out.json
-> reply "WSTACK= EVAL=", score 0
```
Run 2, case `env:` key sets the variable:
```
tests/spikes/clean-env.sh claude plugin eval tests/spikes/eval-env --case case-env --runs 1 --trust-plugin --no-publish --ablation none --allow-tools Bash --json out.json
-> reply "WSTACK= EVAL=/tmp/wstack-env-probe", score 1
```
An earlier attempt to put `WSTACK_VAULT_PATH` in the case `env:` key failed with: `execution.env key "WSTACK_VAULT_PATH" is not allowed - only EVAL_* keys can be set from case.yaml`.

Result: `env-blocked` for a `WSTACK_*` variable set in the operator shell (run 1). The `EVAL_WSTACK_VAULT_PATH` name set in the case `env:` key reaches the eval child (run 2). I ran no `EVAL_WSTACK_TASKS_DIR` case.

Effect on plan: Eval cases set `EVAL_WSTACK_VAULT_PATH` in the case `env:` block. Skills read `WSTACK_VAULT_PATH` first, then `EVAL_WSTACK_VAULT_PATH`. For `WSTACK_TASKS_DIR`, the same `EVAL_WSTACK_TASKS_DIR` route is untested. The first eval that needs it must confirm it.

## S10: Bare skill name

Command: `tests/spikes/clean-env.sh claude -p "/start-task" --plugin-dir tests/spikes/cfg-plugin` and the same with `/wstack:start-task`.

Output: both printed the skill's lines.

Result: `bare-works`. I tested in `-p` mode only, not in an interactive session. A bare name can clash with another plugin's skill of the same name.

Effect on plan: Docs can show `/start-task`. The `wstack:` prefix stays valid.

## S11: Cloudflare Zero Trust free plan user limit

Command: WebFetch of cloudflare.com/plans/zero-trust-services, developers.cloudflare.com/cloudflare-one/account-limits, and a web search.

Output: the fetched Cloudflare pages state no user count. The search summary says Cloudflare's pricing page lists Zero Trust free for up to 50 users. The page `https://en-us.www.cloudflare.com/teams-pricing/` returned 403 to me, so I did not read it directly. Third-party sources disagree on what happens at user 51.

Result: 50 users. Source: https://www.cloudflare.com/plans/zero-trust-services/ (the pricing page, confirmed only through a search summary, not read directly). ASSUME: the limit is still 50 today. Confirm in the Cloudflare dashboard before relying on it.

Effect on plan: Spec section 17 item 7 reads "50 users (unconfirmed: from a search summary, the pricing page returned 403)".

## S12: Is the Artifact tool available in claude -p and in the eval sandbox?

Command: `claude -p "say ok" --output-format stream-json --verbose` (HERDR variables unset), then `jq` on the `init` event tool list. Then `claude -p "Call ToolSearch with query select:Artifact. Do nothing else."`. Then `bash tests/run-evals.sh --case 'mobile-*'` and a search of its kept trace.

Output: the `init` event lists 45 tools, `ToolSearch` among them and no `Artifact`. The ToolSearch call returned `No matching deferred tools found`. In the eval run (allowlist without Artifact) the session wrote `Artifact tool is not available, so spec.html was not published` into run-log.md and made no Artifact call.

Result: plain `claude -p` has no Artifact tool (one run). The `mobile-publish` case sets `allowed_tools` without `Artifact` and `ToolSearch`, so the eval run had no Artifact tool by its own configuration. I did not check whether the sandbox itself offers one, and I did not test an interactive session.

Effect on plan: The `mobile-publish` eval takes the `stop` line branch because its allowlist excludes `Artifact`. It cannot test a real publish. A real publish needs an interactive session with the Artifact tool.

## D-FM: Frontmatter format

Decision: every task file starts with frontmatter between two `---` lines. Each line is `key: value`. A line has no inline comment. A list value is one-line JSON, for example `stopped_for_user: []` and `targets: [{"target":"pr","url":"...","undo":"..."}]`.

Reason: this format is valid YAML, and jq parses it. Bash scripts read and write it with `scripts/lib/frontmatter.sh`, with no YAML library.

Effect on plan: the spec section 6.1 examples show `# ...` comments. The template files leave them out. Scripts reject nothing else, so a status change goes through `scripts/frontmatter-set.sh`, which accepts only the eight status values.

## D-NAV: Sticky top navbar and diagram render

Decision: `scripts/build-review-page.sh` adds the sticky top navbar after the render. It gives each section heading an `id`, inserts a `<nav class="wstack-nav">` after `<body>`, and inserts `templates/mobile.css` as a `<style>` before `</head>`. It then runs `check-page-width.sh` at 375 px on the final page.

Reason: answer-me-with-html has no sticky top navbar (decision S7), and `references/settings.md` of that plugin lists no setting that adds CSS or HTML. Spec section 10.1 requires the navbar.

Diagram render: `scripts/render-excalidraw.sh` opens `about:blank`. The module import of `@excalidraw/utils` 0.1.8 works there, so it needs no local server. It exits 1 for a broken scene and 2 for a network or browser failure. On exit 2 the build writes `Diagram not rendered: <reason>` in the Diagram section, prints a warning, and still builds the page. `WSTACK_EXCALIDRAW_BUNDLE_URL` points the bundle at another URL. Tests use it to simulate a network failure.

## D-DOCS: README diagrams and the R2 lifecycle command

Decision 1: `tests/test_docs.sh` does not compare file times of an `.excalidraw` file and its `.svg`. Git keeps no file times, so on a fresh clone the times are random. The test renders each `.excalidraw` to a temporary SVG with `scripts/render-excalidraw.sh` and checks for exit 0. It then checks that the committed `.svg` exists and holds every text label of its source. It reads the labels with `jq -r '.elements[] | select(.type=="text") | .text'`. If the render exits 2 (CDN or network down), the check prints `SKIP` with the cause and does not fail.

Decision 2: the test does not scan `docs/superpowers/` for the removed diagram tool. The design document and the plan there are historical and still name that tool. The test scans `README.md`, `CHANGELOG.md`, and `docs/` without `docs/spec.md` and `docs/superpowers/`.

Decision 3: the README names no company and no email address. Setup to-do 6 tells the user to check their company policy and to list work repositories in `local_evidence_only_repos`.

R2 lifecycle command (setup to-do 3). Found with `cf r2 buckets lifecycle update --help`, `cf schema r2 buckets lifecycle update`, and `cf docs search`. PATH had Node 26.13.1. I ran it with `--dry-run` only and never ran it for real:
```
cf r2 buckets lifecycle update my-bucket --rules '[{"id":"expire-evidence","enabled":true,"conditions":{"prefix":"evidence/"},"deleteObjectsTransition":{"condition":{"type":"Age","maxAge":2592000}}}]' --dry-run
```
Output:
```
{
  "command": "cf r2 buckets lifecycle update",
  "method": "PUT",
  "url": "https://api.cloudflare.com/client/v4/accounts/<account-id>/r2/buckets/my-bucket/lifecycle",
  "pathParams": { "bucket-name": "my-bucket" },
  "bodyKind": "json",
  "body": { "rules": [ { "id": "expire-evidence", "enabled": true, "conditions": { "prefix": "evidence/" },
    "deleteObjectsTransition": { "condition": { "type": "Age", "maxAge": 2592000 } } } ] }
}
```
`update` replaces all lifecycle rules of the bucket (`PUT .../lifecycle`). `maxAge` is in seconds: 2592000 is 30 days, the `evidence_retention_days` default. The shape of `maxAge` and `type: "Age"` comes from the Cloudflare API and I did not verify it against a live bucket. The dry run checks the request only.

Effect on plan: the user runs the command after approving the bucket change. Nothing in the plugin calls it.

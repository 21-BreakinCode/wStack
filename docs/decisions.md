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

Result: pending (tool not installed yet)

## S3: Excalidraw to SVG

Result: pending (tool not installed yet)

## S4: cf R2 object commands

Result: pending (tool not installed yet)

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
agent prompt: .result.agent.agent_status = "done"; the pane showed "OK"
agent start --remote-control: argv ["claude","--remote-control","wstack-rc-spike"], pane showed "/remote-control is active"
pane run w3:p1 'echo TASK=$WSTACK_TASK_ID'  ->  TASK=x
```

Result:
- Ids: workspace `.result.workspace.workspace_id`, root pane `.result.root_pane.pane_id`, worktree path `.result.worktree.path` (also `.result.workspace.worktree.checkout_path`). Both `worktree create` and `workspace create` return `root_pane`.
- `--env WSTACK_TASK_ID=x` reaches the pane shell.
- `agent start` accepts `--remote-control <name>` after `--`. The flag passes through to claude.
- `--session wstack-test` works for the workspace, worktree, agent, and pane subcommands.
- Surprise 1: the worktree lands in `~/.herdr/worktrees/<repo>/<branch-with-dash>`, not next to the repo.
- Surprise 2: in a folder claude has not trusted yet, `agent start` fails with `agent_not_ready: agent spike is blocked during startup`. The trust prompt is the cause. The agent name stays registered. Send `herdr pane send-keys <pane> Down Enter` to accept, then the agent works. Launch scripts must handle this first-run prompt.
- `herdr worktree remove --workspace <id> --force` removed the worktree. It only accepts the worktree workspace (the workspace made by `workspace create` gives `not_linked_worktree`).
- A fresh named session lists no workspace. The first TUI attach adds `w1`.

Effect on plan: Launch scripts take ids from the JSON paths above. Scripts call herdr through a wrapper that adds `--session "$WSTACK_HERDR_SESSION"` when that variable is set. Scripts must handle the trust prompt.

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

Result: pending (tool not installed yet)

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
tests/spikes/clean-env.sh claude plugin eval . --runs 1 --no-publish --trust-plugin   (inside tests/spikes/cfg-plugin)
```

Output:
```
with --settings: VAULT=/tmp/vault-A
                 ROOT=/Users/.../tests/spikes/cfg-plugin
without settings: VAULT=${user_config.vault_path}
plugin eval (no settings flag exists): VAULT=${user_config.vault_path}
plugin eval with env CLAUDE_PLUGIN_OPTION_vault_path=/tmp/envv: VAULT=${user_config.vault_path}
```

Result:
- `claude -p --plugin-dir`: `--settings '{"pluginConfigs":{"<plugin name>":{"options":{...}}}}'` works. It writes nothing to the user's settings.
- `${user_config.vault_path}` is replaced in skill text when a value is set. It stays literal when no value is set.
- `${CLAUDE_PLUGIN_ROOT}` is replaced in skill text.
- `claude plugin eval` has no `--settings` flag and ignored the env var `CLAUDE_PLUGIN_OPTION_vault_path`. No mechanism found for eval.

Effect on plan: Use the fallback for eval runs. Skills read `WSTACK_VAULT_PATH` and `WSTACK_TASKS_DIR` first, and tests set them. I did not test whether these variables reach the eval child process. Task authors must check that when they write the first eval.

## S10: Bare skill name

Command: `tests/spikes/clean-env.sh claude -p "/start-task" --plugin-dir tests/spikes/cfg-plugin` and the same with `/wstack:start-task`.

Output: both printed the skill's lines.

Result: `bare-works`. I tested in `-p` mode only, not in an interactive session. A bare name could clash with another plugin's skill of the same name.

Effect on plan: Docs can show `/start-task`. The `wstack:` prefix stays valid.

## S11: Cloudflare Zero Trust free plan user limit

Command: WebFetch of cloudflare.com/plans/zero-trust-services, developers.cloudflare.com/cloudflare-one/account-limits, and a web search.

Output: the fetched Cloudflare pages state no user count. The search summary says Cloudflare's pricing page lists Zero Trust free for up to 50 users. The page `https://en-us.www.cloudflare.com/teams-pricing/` returned 403 to me, so I did not read it directly. Third-party sources disagree on what happens at user 51.

Result: 50 users. Source: https://www.cloudflare.com/plans/zero-trust-services/ (the pricing page, confirmed only through a search summary, not read directly). ASSUME: the limit is still 50 today. Confirm in the Cloudflare dashboard before relying on it.

Effect on plan: Spec section 17 item 7 can say 50 users. A solo or small-team setup stays well under it.

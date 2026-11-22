# wStack

wStack is a Claude Code plugin. The repository root is the plugin root.

## Before every commit

Run `bash tests/run-all.sh`. It runs every `tests/test_*.sh` file at the top level of `tests/`. It skips `tests/spikes/`.

## Test rules

- This repo is often worked on from inside the main herdr session. Run every `claude -p` and every `claude plugin eval` with `env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID`.
- Herdr commands in tests target the named test session. Set `WSTACK_HERDR_SESSION=wstack-test`.
- Tests never write into `$HOME/Projects/LifeOS/`.
- Tests that touch `~/.wstack` set `HOME` to a temp directory.
- For a `claude -p` run, pass plugin config with `--settings '{"pluginConfigs":{"wstack":{"options":{...}}}}'`.
- `${user_config.*}` and `${CLAUDE_PLUGIN_ROOT}` are replaced in skill text. Skills name bundled files only as `${CLAUDE_PLUGIN_ROOT}/...`.
- `/start-task` works without the `wstack:` prefix in `claude -p` (decision S10, `bare-works`).
- `claude -p --plugin-dir .` loads no wStack skill until the `answer-me-with-html` plugin is installed. Claude Code reports a `dependency-unsatisfied` plugin error.

## Script rules

- Start every script with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Scripts must run on `/bin/bash` 3.2.
- Quote every path variable.
- Python scripts use only the standard library and run on Python 3.9.

## Skill rules

- `start-task`, `pause-task`, `run-retro`, `init-org`, `init-service`, `create-handover`, and `wrap-up-handovers` are user-invoked (`disable-model-invocation: true`).
- `build-review-page`, `capture-evidence`, and `deliver-task` are helper skills (`user-invocable: false`).

## Documents

- `docs/spec.md` is the spec.
- `docs/superpowers/specs/2026-11-18-wstack-design.md` is the design doc.
- `docs/decisions.md` holds decisions and spike results.

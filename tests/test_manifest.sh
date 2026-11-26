#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
plugin_json="$repo_root/.claude-plugin/plugin.json"
market_json="$repo_root/.claude-plugin/marketplace.json"

assert "plugin name" '[ "$(jq -r .name "$plugin_json")" = "wstack" ]'
assert "display name" '[ "$(jq -r .displayName "$plugin_json")" = "wStack" ]'
assert "version is 0.12.3 in both" '[ "$(jq -r .version "$plugin_json")" = "0.12.3" ] && [ "$(jq -r ".plugins[0].version" "$market_json")" = "0.12.3" ]'
assert "dependency" '[ "$(jq -r ".dependencies[0]" "$plugin_json")" = "answer-me-with-html@answer-me-with-html" ]'
assert "cross-marketplace allowlist" '[ "$(jq -c .allowCrossMarketplaceDependenciesOn "$market_json")" = "[\"answer-me-with-html\"]" ]'
assert "plugin source" '[ "$(jq -r ".plugins[0].source" "$market_json")" = "./" ]'
assert "userConfig keys" '[ "$(jq -r ".userConfig | keys | join(\",\")" "$plugin_json")" = "evidence_domain,evidence_retention_days,local_evidence_only_repos,pr_media_max_mb,r2_bucket,retry_limit,tasks_dir,vault_path" ]'
assert "no sensitive userConfig" '[ "$(jq "[.userConfig[] | select(.sensitive == true)] | length" "$plugin_json")" = "0" ]'
assert "claude plugin validate" '(cd "$repo_root" && claude plugin validate . >/dev/null 2>&1)'
finish

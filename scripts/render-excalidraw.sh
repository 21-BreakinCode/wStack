#!/usr/bin/env bash
# Usage: render-excalidraw.sh <scene.excalidraw> <out.svg>
# Renders the scene to SVG with @excalidraw/utils 0.1.8 from the jsDelivr CDN (decision S3).
# Exit 0 rendered, 1 input is not valid JSON or has no "elements" array, 2 render or network failed.
# Needs playwright-cli on PATH (Node 26 first). The page is about:blank, so no server is needed.
# WSTACK_EXCALIDRAW_BUNDLE_URL overrides the bundle URL. Tests use it to simulate a network failure.
set -euo pipefail

scene_file="${1:-}" svg_file="${2:-}"
[ -f "$scene_file" ] && [ -n "$svg_file" ] || { echo "render-excalidraw: usage: render-excalidraw.sh <scene.excalidraw> <out.svg>" >&2; exit 1; }

svg_file="$(cd "$(dirname "$svg_file")" && pwd)/$(basename "$svg_file")"
scene_json="$(jq -c . "$scene_file" 2>/dev/null)" || { echo "render-excalidraw: not valid JSON: $scene_file" >&2; exit 1; }
[ "$(jq -r '.elements | type' <<<"$scene_json")" = "array" ] || { echo "render-excalidraw: no elements array: $scene_file" >&2; exit 1; }
command -v playwright-cli >/dev/null 2>&1 || { echo "render-excalidraw: playwright-cli not found. install: npm i -g @playwright/cli@0.1.24" >&2; exit 2; }

bundle_url="${WSTACK_EXCALIDRAW_BUNDLE_URL:-https://cdn.jsdelivr.net/npm/@excalidraw/utils@0.1.8/dist/prod/index.js}"
session="wstack-excalidraw-$$"
# playwright-cli writes .playwright-cli/page-*.yml into its working folder. Run it in a throwaway folder.
scratch_dir="$(mktemp -d)"
cd "$scratch_dir"
trap 'playwright-cli -s "$session" close >/dev/null 2>&1 || true; rm -rf "$scratch_dir"' EXIT

code="async (page) => {
  await page.addScriptTag({ type: 'module', content: \"import('$bundle_url').then((U) => { window.__U = U; window.__ready = 'ok'; }).catch((e) => { window.__ready = 'failed: ' + e; });\" });
  await page.waitForFunction(() => window.__ready !== undefined, null, { timeout: 60000 });
  return await page.evaluate(async (scene) => {
    if (window.__ready !== 'ok') throw new Error('bundle import ' + window.__ready);
    const svg = await window.__U.exportScene({ type: 'svg', data: { elements: scene.elements, appState: scene.appState, files: scene.files } });
    return svg.outerHTML;
  }, $scene_json);
}"

browser_output="$(playwright-cli -s "$session" open about:blank 2>&1)" || { echo "render-excalidraw: could not open the browser: $browser_output" >&2; exit 2; }
raw_output="$(playwright-cli -s "$session" --raw run-code "$code" 2>&1)" || { echo "render-excalidraw: render failed: $raw_output" >&2; exit 2; }
svg="$(jq -r 'if type == "string" then . else empty end' <<<"$raw_output" 2>/dev/null)" || svg=""
case "$svg" in
  "<svg"*) printf '%s\n' "$svg" > "$svg_file" ;;
  *) echo "render-excalidraw: render failed: $raw_output" >&2; exit 2 ;;
esac

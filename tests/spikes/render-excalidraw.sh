#!/usr/bin/env bash
# Usage: render-excalidraw.sh <scene.excalidraw> <out.svg> <page url on a local http server>
# Renders the scene to SVG with @excalidraw/utils 0.1.8 from the jsDelivr CDN.
set -euo pipefail
scene_file="$1"; svg_file="$2"; page_url="$3"
scene_json="$(jq -c . "$scene_file")"
code="async (page) => {
  await page.addScriptTag({ type: 'module', content: \"import * as U from 'https://cdn.jsdelivr.net/npm/@excalidraw/utils@0.1.8/dist/prod/index.js'; window.__U = U; window.__ready = true;\" });
  await page.waitForFunction(() => window.__ready === true, null, { timeout: 60000 });
  return await page.evaluate(async (scene) => {
    const svg = await window.__U.exportScene({ type: 'svg', data: { elements: scene.elements, appState: scene.appState, files: scene.files } });
    return svg.outerHTML;
  }, $scene_json);
}"
playwright-cli -s excalidraw-spike open "$page_url" >/dev/null
trap 'playwright-cli -s excalidraw-spike close >/dev/null 2>&1 || true' EXIT
playwright-cli -s excalidraw-spike --raw run-code "$code" | jq -r . > "$svg_file"

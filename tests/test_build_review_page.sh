#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/_assert.sh"
work_root="$(mktemp -d)"
trap 'rm -rf "$work_root"' EXIT
build="$repo_root/scripts/build-review-page.sh"
fixtures="$repo_root/tests/fixtures/review"
export AM_HOME="$work_root/am-home"
export HOME="$work_root/home"
page_for() { echo "$HOME/.wstack/pages/$1/review.html"; }  # <case name>

make_task() {  # <name> <work type> <with diagram: yes|no>
  mkdir -p "$work_root/$1/vault task"
  cp "$fixtures/review.md" "$work_root/$1/vault task/review.md"
  printf -- '---\nwork_type: %s\n---\n' "$2" > "$work_root/$1/vault task/spec.md"
  [ "$3" = no ] || cp "$fixtures/diagram.excalidraw" "$work_root/$1/vault task/"
}
line_of() { grep -n "$2" "$1" | head -n 1 | cut -d: -f1; }

# Opens a built page at a width and prints the result of a JS function. Test-only server and session.
page_probe() {  # <page> <width> <js arrow function> [screenshot png]
  local page="$1" width="$2" js="$3" shot="${4:-}" port session server_pid result probe_origin="$PWD" probe_dir
  port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  session="wstack-test-probe-$$-$width"
  python3 -m http.server --bind 127.0.0.1 --directory "$(dirname "$page")" "$port" >/dev/null 2>&1 &
  server_pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fs -o /dev/null "http://127.0.0.1:$port/$(basename "$page")" && break; sleep 0.5; done
  probe_dir="$(mktemp -d)"; cd "$probe_dir"  # playwright-cli writes .playwright-cli/ into its folder
  playwright-cli -s "$session" open "http://127.0.0.1:$port/$(basename "$page")" >/dev/null 2>&1 || true
  playwright-cli -s "$session" resize "$width" 500 >/dev/null 2>&1 || true
  result="$(playwright-cli -s "$session" --raw eval "$js" 2>&1 || true)"
  [ -z "$shot" ] || playwright-cli -s "$session" screenshot --filename "$shot" >/dev/null 2>&1 || true
  playwright-cli -s "$session" close >/dev/null 2>&1 || true
  cd "$probe_origin"; rm -rf "$probe_dir"
  kill "$server_pid" 2>/dev/null || true
  echo "$result"
}
# JS: count nav links that are cut off at the right edge or whose target id is missing.
nav_problems_js='(width) => [...document.querySelectorAll(".wstack-nav a")].filter(a => a.getBoundingClientRect().right > width || !document.getElementById(a.getAttribute("href").slice(1))).length'
# JS: count toolbar buttons in view whose center point is covered by another layer. Reply must be in view and uncovered.
covered_js='() => { const inView = (r) => r.left >= 0 && r.right <= innerWidth; const topAt = (el) => { const r = el.getBoundingClientRect(); const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return hit === el || el.contains(hit); }; const reply = document.querySelector(".am-toolbar [data-am=reply]"); const replyBad = reply && inView(reply.getBoundingClientRect()) && topAt(reply) ? 0 : 1; return replyBad + [...document.querySelectorAll(".am-toolbar > *")].filter(el => { const r = el.getBoundingClientRect(); return r.width >= 4 && inView(r) && !topAt(el); }).length; }'

# JS: after each nav jump, count headings that sit above the toolbar's bottom edge or under another layer.
jump_problems_js='() => { document.documentElement.style.scrollBehavior = "auto"; const toolbar = document.querySelector(".am-toolbar"); return [...document.querySelectorAll(".wstack-nav a")].filter(a => { location.hash = a.getAttribute("href"); const heading = document.getElementById(a.getAttribute("href").slice(1)); const r = heading.getBoundingClientRect(); const hit = document.elementFromPoint(r.left + 4, r.top + r.height / 2); return r.top < toolbar.getBoundingClientRect().bottom || !(hit && (hit === heading || heading.contains(hit))); }).length; }'

# a broken diagram needs no browser
make_task broken code yes
echo '{}' > "$work_root/broken/vault task/diagram.excalidraw"
broken_exit=0
bash "$build" --task-dir "$work_root/broken/vault task" --work-dir "$work_root/broken/work" --page "$(page_for broken)" >/dev/null 2>&1 || broken_exit=$?
assert "broken diagram exits 1" '[ "$broken_exit" -eq 1 ]'
assert "broken diagram writes no page" '[ ! -e "$(page_for broken)" ]'
missing_page_exit=0
bash "$build" --task-dir "$work_root/broken/vault task" --work-dir "$work_root/broken/work" >/dev/null 2>&1 || missing_page_exit=$?
assert "missing --page exits 2" '[ "$missing_page_exit" -eq 2 ]'

amjs="${WSTACK_AMJS:-}"
if [ -z "$amjs" ]; then
  install_path="$(claude plugin list --json 2>/dev/null | jq -r '[.[] | select(.id == "answer-me-with-html@answer-me-with-html" and .enabled == true)] | first | .installPath // empty' 2>/dev/null || true)"
  [ -z "$install_path" ] || amjs="$install_path/answer-me-with-html/scripts/am.mjs"
fi
if ! command -v playwright-cli >/dev/null 2>&1 || [ ! -f "$amjs" ]; then
  echo "SKIP page cases: playwright-cli or answer-me-with-html not found"
  finish; exit
fi

if curl -fs -m 20 -r 0-0 -o /dev/null "https://cdn.jsdelivr.net/npm/@excalidraw/utils@0.1.8/dist/prod/index.js"; then
  make_task code code yes
  task="$work_root/code/vault task"
  code_exit=0
  bash "$build" --task-dir "$task" --work-dir "$work_root/code/work" --page "$(page_for code)" >/dev/null 2>&1 || code_exit=$?
  page="$(page_for code)"
  assert "build exits 0" '[ "$code_exit" -eq 0 ]'
  assert "review.html exists" '[ -s "$page" ]'
  assert "task folder has no review.html" '[ ! -e "$task/review.html" ]'
  order_ok=true
  previous=0
  for heading in Findings Decisions Evidence Diagram "Guided diff"; do
    current="$(line_of "$page" "<h2[^>]*>$heading")"
    if [ -z "$current" ] || [ "$current" -le "$previous" ]; then order_ok=false; fi
    previous="${current:-0}"
  done
  assert "five sections appear in order" '$order_ok'
  assert "css has position: sticky for the navbar" 'grep -q "position: sticky" "$page"'
  assert "navbar links to the sections" 'grep -q "<nav class=\"wstack-nav\"" "$page" && grep -q "href=\"#guided-diff\"" "$page"'
  assert "diagram section holds an inline svg" '[ "$(line_of "$page" "<svg style=\"width:100%")" -gt "$(line_of "$page" "<h2[^>]*>Diagram")" ] && [ "$(line_of "$page" "<svg style=\"width:100%")" -lt "$(line_of "$page" "<h2[^>]*>Guided diff")" ]'
  assert "svg is full width" 'grep -q "style=\"width:100%;height:auto\"" "$page"'
  assert "work dir has diagram.svg" '[ -s "$work_root/code/work/diagram.svg" ]'
  assert "vault folder has no svg" '[ -z "$(find "$task" -name "*.svg")" ]'
  fit_exit=0
  bash "$repo_root/scripts/check-page-width.sh" "$page" 375 >/dev/null 2>&1 || fit_exit=$?
  assert "page fits at 375" '[ "$fit_exit" -eq 0 ]'


  for width in 375 1280; do
    covered="$(page_probe "$page" "$width" "$covered_js" "$work_root/shot-$width.png")"
    assert "no layer covers a toolbar button at $width px" '[ "$covered" = "0" ]'
  done
  for width in 375 1280; do
    jump_problems="$(page_probe "$page" "$width" "$jump_problems_js")"
    assert "nav jumps land below the toolbar at $width px" '[ "$jump_problems" = "0" ]'
  done
  nav_problems="$(page_probe "$page" 375 "() => ($nav_problems_js)(375)")"
  assert "every nav link fits at 375 px and has a target id" '[ "$nav_problems" = "0" ]'
  if [ -n "${WSTACK_TEST_SCREENSHOT_DIR:-}" ]; then cp "$work_root"/shot-*.png "$WSTACK_TEST_SCREENSHOT_DIR/"; fi

  make_task blog blog yes
  bash "$build" --task-dir "$work_root/blog/vault task" --work-dir "$work_root/blog/work" --page "$(page_for blog)" >/dev/null 2>&1 || true
  blog_page="$(page_for blog)"
  blog_nav_problems="$(page_probe "$blog_page" 375 "() => ($nav_problems_js)(375)")"
  for width in 375 1280; do
    blog_jump_problems="$(page_probe "$blog_page" "$width" "$jump_problems_js")"
    assert "blog nav jumps land below the toolbar at $width px" '[ "$blog_jump_problems" = "0" ]'
  done
  assert "blog nav fits at 375 px and has target ids" '[ "$blog_nav_problems" = "0" ]'
  assert "blog task has Before and after as the fifth section" 'grep -q "<h2[^>]*>Before and after" "$blog_page" && ! grep -q "<h2[^>]*>Guided diff" "$blog_page"'
else
  echo "SKIP diagram cases: cdn.jsdelivr.net not reachable"
fi

# network failure: the page still builds and the Diagram section says why
make_task offline code yes
offline_exit=0
offline_output="$(WSTACK_EXCALIDRAW_BUNDLE_URL="http://127.0.0.1:1/none.js" bash "$build" --task-dir "$work_root/offline/vault task" --work-dir "$work_root/offline/work" --page "$(page_for offline)" 2>&1)" || offline_exit=$?
offline_page="$(page_for offline)"
assert "offline diagram still builds with exit 0" '[ "$offline_exit" -eq 0 ] && [ -s "$offline_page" ]'
assert "offline diagram section says it was not rendered" 'grep -q "Diagram not rendered:" "$offline_page"'
assert "offline diagram prints a warning" '[[ "$offline_output" == *"warning: diagram not rendered"* ]]'
assert "page title names the task" 'grep -q "<title>2026-01-01-sample review</title>" "$offline_page"'
finish

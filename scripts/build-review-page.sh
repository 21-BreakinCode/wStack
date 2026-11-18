#!/usr/bin/env bash
# Usage: build-review-page.sh --task-dir <abs> --work-dir <abs>
# Builds <task-dir>/review.html from <task-dir>/review.md. Working files go in <work-dir>, never in the vault.
# Exit 0 built and fits at 375 px, 1 broken diagram or page too wide, 2 infrastructure failure.
# A diagram that cannot render because of the network or the browser (render-excalidraw exit 2)
# becomes "Diagram not rendered: <reason>" in the page and a warning. The build still succeeds.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
plugin_root="$(dirname "$script_dir")"
source "$script_dir/lib/frontmatter.sh"
fail() { echo "build-review-page: $1" >&2; exit "${2:-2}"; }

task_dir="" work_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --task-dir|--work-dir) [ "$#" -ge 2 ] || fail "missing value for $1" ;;
  esac
  case "$1" in
    --task-dir) task_dir="$2"; shift 2 ;;
    --work-dir) work_dir="$2"; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[ -f "$task_dir/review.md" ] || fail "no review.md in task dir: $task_dir"
[ -n "$work_dir" ] || fail "usage: build-review-page.sh --task-dir <abs> --work-dir <abs>"
mkdir -p "$work_dir"

# The fifth section depends on the work type (spec 10.3).
work_type=""
[ ! -f "$task_dir/spec.md" ] || work_type="$(fm_get "$task_dir/spec.md" work_type)"
fifth_heading="Guided diff" fifth_label="Diff"
case "$work_type" in blog|video) fifth_heading="Before and after" fifth_label="Before/after" ;; esac
draft="$work_dir/review-draft.md"
sed "s/^## Guided diff\$/## $fifth_heading/" "$task_dir/review.md" > "$draft"

# Diagram: render, then replace the marker in the draft with a fenced svg block (the tested path of S7).
if [ -f "$task_dir/diagram.excalidraw" ]; then
  diagram_block="$work_dir/diagram-block.md"
  render_exit=0
  render_error="$(bash "$script_dir/render-excalidraw.sh" "$task_dir/diagram.excalidraw" "$work_dir/diagram.svg" 2>&1 >/dev/null)" || render_exit=$?
  case "$render_exit" in
    0)
      { echo '```svg'; sed 's/^<svg /<svg style="width:100%;height:auto" /' "$work_dir/diagram.svg"; echo '```'; } > "$diagram_block" ;;
    1) fail "diagram.excalidraw is broken, fix it: $render_error" 1 ;;
    *)
      reason="$(head -n 1 <<<"$render_error")"
      echo "build-review-page: warning: diagram not rendered. $reason" >&2
      echo "Diagram not rendered: ${reason#render-excalidraw: }" > "$diagram_block" ;;
  esac
  marked_draft="$work_dir/review-draft-diagram.md"
  awk -v block="$diagram_block" '
    index($0, "<!-- wstack:diagram -->") == 1 { while ((getline line < block) > 0) print line; next }
    { print }
  ' "$draft" > "$marked_draft"
  draft="$marked_draft"
fi

page="$work_dir/review-page.html"
render_exit=0
bash "$script_dir/render-page.sh" "$draft" "$page" || render_exit=$?
# 1 means too wide before the navbar. The navbar CSS can still change that, so only a render failure stops here.
[ "$render_exit" -ne 2 ] || exit 2

# answer-me-with-html has no sticky top navbar (decision S7). Add ids to the headings, a nav, and the CSS.
nav_file="$work_dir/nav.html"
sed_ids=()
{
  printf '<nav class="wstack-nav" aria-label="Sections">'
  for heading_and_label in Findings:Findings Decisions:Decisions Evidence:Evidence Diagram:Diagram "$fifth_heading:$fifth_label"; do
    heading="${heading_and_label%%:*}" label="${heading_and_label#*:}"
    anchor="$(tr '[:upper:] ' '[:lower:]-' <<<"$heading")"
    sed_ids+=(-e "s|<h2>$heading|<h2 id=\"$anchor\">$heading|")
    printf '<a href="#%s">%s</a>' "$anchor" "$label"
  done
  printf '</nav>\n'
} > "$nav_file"
{ echo '<style>'; cat "$plugin_root/templates/mobile.css"; echo '</style>'; } > "$work_dir/mobile-style.html"
sed "${sed_ids[@]}" "$page" | awk -v css="$work_dir/mobile-style.html" -v nav="$nav_file" '
  function emit(file,   line) { while ((getline line < file) > 0) print line; close(file) }
  !css_done && (at = index($0, "</head>")) { printf "%s", substr($0, 1, at - 1); emit(css); print substr($0, at); css_done = 1; next }
  !nav_done && (at = index($0, "<body>")) { printf "%s", substr($0, 1, at + 5); print ""; emit(nav); print substr($0, at + 6); nav_done = 1; next }
  { print }
' > "$task_dir/review.html"
grep -q 'wstack-nav' "$task_dir/review.html" || fail "could not inject the navbar into the page"

width_exit=0
bash "$script_dir/check-page-width.sh" "$task_dir/review.html" 375 || width_exit=$?
exit "$width_exit"

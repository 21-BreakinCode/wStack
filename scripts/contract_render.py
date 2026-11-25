#!/usr/bin/env python3
"""Render a contract (JSON on stdin) to a vault note and an HTML page.

Usage: contract_render.py <note path> <html path> <contract file name>
"""
import html
import json
import os
import re
import sys
from urllib.parse import quote

import contract_diagrams
import contract_diagrams_svg

SECTIONS = [
    ("gotchas", "Gotchas"),
    ("abilities", "Abilities"),
    ("interfaces", "Interfaces"),
    ("depends_on", "Depends on"),
    ("consumers", "Consumers"),
]
CARD_ORDER = [
    ("gotchas", "gotcha"), ("abilities", "ability"), ("interfaces", "interface"),
    ("depends_on", "dependency"), ("consumers", "consumer"),
    ("planned", "planned"), ("open_questions", "open question"),
]
CROSS_REPO = re.compile(r"^([^/@:]+/[^/@:]+)@([0-9a-f]+):(.+)$")
LINES = re.compile(r"^\d+(-\d+)?(\s*,\s*\d+(-\d+)?)*$")
HEADING_UNSAFE = re.compile(r"[#^|\[\]:%]")


def one_line(text):
    return " ".join(str(text).split())


def ref_url(ref, repo, commit):
    """GitHub link for a ref. Anchor uses the first range only."""
    cross = CROSS_REPO.match(ref)
    if cross:
        repo, commit, rest = cross.groups()
    else:
        rest = ref
    path, _, lines = rest.rpartition(":")
    if not path or not LINES.match(lines):
        path, lines = rest, ""
    url = "https://github.com/%s/blob/%s/%s" % (repo, commit, quote(path))
    first = lines.split(",")[0].strip()
    if first:
        start, _, end = first.partition("-")
        url += "#L%s" % start + ("-L%s" % end if end else "")
    return url


def plural(count, noun):
    return "%d %s%s" % (count, noun, "" if count == 1 else "s")


def heading_text(title):
    return one_line(HEADING_UNSAFE.sub(" ", title))


def md_text(text):
    text = one_line(text)
    return "\\" + text if text[:1] in "#>-" else text


def md_link_text(text):
    return re.sub(r"([\[\]])", r"\\\1", one_line(text))


def md_refs(refs, repo, commit):
    if not refs:
        return []
    lines = ["  > [!quote]- refs (%d)" % len(refs)]
    lines += ["  > - [%s](%s)" % (md_link_text(r), ref_url(r, repo, commit)) for r in refs]
    return lines


def md_plan_link(plan_id, plans_by_id):
    plan = plans_by_id.get(plan_id)
    if plan is None:
        return "  planned: plan item removed (%s)" % md_text(plan_id)
    return "  planned: [[#%s|%s]]" % (heading_text(plan["title"]), md_link_text(plan["title"]))


def md_item(item, repo, commit, plans_by_id):
    lines = ["- " + md_text(item.get("text", ""))]
    if item.get("app"):
        mapped = " at %s" % item["mapped_commit"] if item.get("mapped_commit") else ""
        lines.append("  mapped service: `%s`%s" % (one_line(item["app"]), one_line(mapped)))
    if item.get("planned"):
        lines.append(md_plan_link(item["planned"], plans_by_id))
    return lines + md_refs(item.get("refs") or [], repo, commit)


def render_note(data, contract_name, deep_dives):
    repo, commit = data.get("repo", ""), str(data.get("verified_commit") or "")
    sections = data.get("sections") or {}
    planned = data.get("planned") or []
    plans_by_id = {p.get("id"): p for p in planned}
    out = ["---", "tags: %s" % json.dumps(data.get("tags") or []), "---",
           "Generated from `%s`. Any edits are lost on the next render." % contract_name, "",
           "# %s" % one_line(data.get("app_name", "")), "",
           one_line(data.get("summary", "")), "",
           "Verified at `%s` on %s. Base branch: `%s`." % (
               commit, one_line(data.get("verified_at") or "unknown time"), one_line(data.get("base_branch", ""))),
           ""]
    diagram_lines = contract_diagrams.note_lines(data.get("diagrams") or {}, deep_dives)
    out += diagram_lines
    for key, title in SECTIONS:
        out += ["## " + title, ""]
        if key == "interfaces" and data.get("openapi"):
            path = data["openapi"]
            out += ["OpenAPI: [%s](%s)" % (md_link_text(path), ref_url(path, repo, commit)), ""]
        for item in (sections.get(key) or {}).get("items") or []:
            out += md_item(item, repo, commit, plans_by_id)
        out.append("")
    out += ["## Planned", ""]
    for plan in planned:
        out += ["### " + heading_text(plan.get("title", "")), "", md_text(plan.get("why", "")), ""]
        out += [line[2:] for line in md_refs(plan.get("refs") or [], repo, commit)] + [""]
    open_questions = (sections.get("open_questions") or {}).get("items") or []
    if open_questions:
        out += ["## Open questions", ""]
        for item in open_questions:
            out += md_item(item, repo, commit, plans_by_id)
        out.append("")
    out += ["## Team docs", ""]
    for name, block in (("team_docs", sections.get("team_docs") or {}),) + tuple(
            (key, sections.get(key) or {}) for key in ("abilities", "interfaces", "depends_on")):
        sources = block.get("sources") or []
        if sources:
            out += ["> [!note]- %s sources (%d)" % (name, len(sources))]
            out += ["> - `%s`" % one_line(s).replace("`", "'") for s in sources]
            out.append("")
    return "\n".join(out).rstrip("\n") + "\n"


CSS = """
:root { --bg: #fff; --fg: #1d2330; --muted: #5b6475; --card: #f3f5f9; --line: #d9deea; --link: #1a56c4; }
@media (prefers-color-scheme: dark) { :root { --bg: #14181f; --fg: #e6e9f0; --muted: #9aa3b5; --card: #1e242e; --line: #343c4a; --link: #7aa7ff; } }
* { box-sizing: border-box; }
body { margin: 0; padding: 16px; background: var(--bg); color: var(--fg); font: 16px/1.5 system-ui, sans-serif; overflow-wrap: anywhere; }
main { max-width: 760px; margin: 0 auto; }
h1 { font-size: 1.5rem; margin: 0 0 8px; }
h2 { font-size: 1.15rem; margin: 28px 0 8px; border-bottom: 1px solid var(--line); padding-bottom: 4px; }
h3 { font-size: 1rem; margin: 16px 0 4px; }
a { color: var(--link); }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 12px; margin: 12px 0; }
.counts { display: flex; flex-wrap: wrap; gap: 6px 12px; margin: 8px 0 0; padding: 0; list-style: none; }
.muted { color: var(--muted); }
ul.items { padding-left: 20px; }
ul.items li { margin: 8px 0; }
details { margin: 4px 0; }
summary { cursor: pointer; color: var(--muted); }
code { overflow-wrap: anywhere; }
.diagram { overflow-x: auto; margin: 12px 0; }
.diagram figcaption { font-weight: 600; margin: 0 0 6px; }
.diagram svg { display: block; max-width: none; }
.diagram text { font: 13px system-ui, sans-serif; fill: var(--fg); }
.diagram .lbl { paint-order: stroke; stroke: var(--bg); stroke-width: 4px; stroke-linejoin: round; }
.diagram .layer-name { font-weight: 600; }
.diagram .node, .diagram .pill { fill: var(--card); stroke: var(--line); stroke-width: 1.5; }
.diagram .layer { fill: var(--card); fill-opacity: .5; stroke: var(--line); stroke-width: 1.5; }
.diagram .svc { fill: none; stroke: var(--link); stroke-width: 1.5; }
.diagram .edge { fill: none; stroke: var(--muted); stroke-width: 1.5; }
.diagram .impl { stroke-dasharray: 5 4; }
.diagram .life { stroke: var(--line); stroke-width: 1.5; stroke-dasharray: 4 4; }
.diagram .head, .diagram .start { fill: var(--link); }
.badge { margin-left: 6px; padding: 0 6px; border: 1px solid var(--line); border-radius: 999px; color: var(--muted); font-size: .8rem; }
"""


def esc(text):
    return html.escape(str(text))


def html_refs(refs, repo, commit):
    if not refs:
        return ""
    links = "".join('<li><a href="%s">%s</a></li>' % (esc(ref_url(r, repo, commit)), esc(r)) for r in refs)
    return "<details><summary>refs (%d)</summary><ul>%s</ul></details>" % (len(refs), links)


def html_item(item, repo, commit, plans_by_id):
    parts = [esc(item.get("text", ""))]
    if item.get("app"):
        parts.append('<div class="muted">mapped service: <code>%s</code>%s</div>' % (
            esc(item["app"]), " at <code>%s</code>" % esc(item["mapped_commit"]) if item.get("mapped_commit") else ""))
    plan_id = item.get("planned")
    if plan_id:
        plan = plans_by_id.get(plan_id)
        parts.append('<div class="muted">planned: %s</div>' % (
            '<a href="#plan-%s">%s</a>' % (esc(quote(plan_id)), esc(plan.get("title", ""))) if plan
            else "plan item removed (%s)" % esc(plan_id)))
    parts.append(html_refs(item.get("refs") or [], repo, commit))
    return "<li>%s</li>" % "".join(parts)


def render_html(data, deep_dives):
    repo, commit = data.get("repo", ""), str(data.get("verified_commit") or "")
    sections = data.get("sections") or {}
    planned = data.get("planned") or []
    plans_by_id = {p.get("id"): p for p in planned}

    def items_of(key):
        return (sections.get(key) or {}).get("items") or []

    counts = {key: len(items_of(key)) for key, _ in CARD_ORDER}
    counts["planned"] = len(planned)
    count_html = "".join("<li>%s</li>" % plural(counts[key], noun) for key, noun in CARD_ORDER)
    body = [
        "<h1>%s</h1>" % esc(data.get("app_name", "")),
        "<p>%s</p>" % esc(data.get("summary", "")),
        '<div class="card"><div class="muted">verified <code>%s</code> at %s on branch <code>%s</code></div>'
        '<ul class="counts">%s</ul></div>' % (
            esc(commit), esc(data.get("verified_at") or "unknown time"), esc(data.get("base_branch", "")), count_html),
    ]
    diagram_section = contract_diagrams_svg.html_section(data.get("diagrams") or {}, deep_dives)
    if diagram_section:
        body.append(diagram_section)
    for key, title in SECTIONS + [("planned", "Planned"), ("open_questions", "Open questions")]:
        if key == "open_questions" and not items_of(key):
            continue
        body.append("<h2>%s</h2>" % title)
        if key == "interfaces" and data.get("openapi"):
            body.append('<p>OpenAPI: <a href="%s">%s</a></p>' % (
                esc(ref_url(data["openapi"], repo, commit)), esc(data["openapi"])))
        if key == "planned":
            for plan in planned:
                body.append('<h3 id="plan-%s">%s</h3><p>%s</p>%s' % (
                    esc(quote(str(plan.get("id", "")))), esc(plan.get("title", "")), esc(plan.get("why", "")),
                    html_refs(plan.get("refs") or [], repo, commit)))
            continue
        items = "".join(html_item(i, repo, commit, plans_by_id) for i in items_of(key))
        body.append('<ul class="items">%s</ul>' % items)
    body.append("<h2>Team docs</h2>")
    for name in ("team_docs", "abilities", "interfaces", "depends_on"):
        sources = (sections.get(name) or {}).get("sources") or []
        if sources:
            body.append("<details><summary>%s sources (%d)</summary><ul>%s</ul></details>" % (
                esc(name), len(sources), "".join("<li><code>%s</code></li>" % esc(s) for s in sources)))
    return ('<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            "<title>%s contract</title><style>%s</style></head><body><main>%s</main></body></html>\n") % (
        esc(data.get("app_name", "")), CSS, "\n".join(body))


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: contract_render.py <note path> <html path> <contract file name>")
    note_path, html_path, contract_name = sys.argv[1:]
    data = json.load(sys.stdin)
    if not isinstance(data, dict):
        sys.exit("contract is not a mapping")
    deep_dives = contract_diagrams.read_deep_dives(
        os.path.dirname(os.path.abspath(note_path)), data.get("diagrams") or {})
    with open(note_path, "w", encoding="utf-8") as note:
        note.write(render_note(data, contract_name, deep_dives))
    with open(html_path, "w", encoding="utf-8") as page:
        page.write(render_html(data, deep_dives))


if __name__ == "__main__":
    main()

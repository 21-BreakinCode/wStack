#!/usr/bin/env python3
"""Subjects, shape hashes, deep dive state, and the note section of contract diagrams.

Usage: contract_diagrams.py hash <subject>      (contract JSON on stdin)
       contract_diagrams.py subject <subject>   (contract JSON on stdin)
"""
import collections
import glob
import hashlib
import html
import json
import os
import re
import sys
import unicodedata
from urllib.parse import quote

MAX_LABEL = 32
NOTE_COLUMNS = 40
META_TAG = re.compile(r"<meta\b[^>]*>", re.I)
META_NAME = re.compile(r"\bname\s*=\s*\"(wstack-[a-z-]+)\"", re.I)
META_CONTENT = re.compile(r"\bcontent\s*=\s*\"([^\"]*)\"", re.I)
HEADING_UNSAFE = re.compile(r"[#^|\[\]:%]")


def subjects(diagrams):
    found = collections.OrderedDict()
    if diagrams.get("flow"):
        found["flow"] = diagrams["flow"]
    for sequence in diagrams.get("sequences") or []:
        found["sequence:%s" % sequence["id"]] = sequence
    for lifecycle in diagrams.get("states") or []:
        found["states:%s" % lifecycle["id"]] = lifecycle
    if diagrams.get("architecture"):
        found["architecture"] = diagrams["architecture"]
    return found


def subject_slug(subject):
    return subject.replace(":", "-")


def without_layout_only_keys(value):
    """Drop refs, and a sibling flag that is false, so neither changes the shape hash."""
    if isinstance(value, dict):
        return {k: without_layout_only_keys(v) for k, v in value.items()
                if k != "refs" and not (k == "sibling" and v is False)}
    if isinstance(value, list):
        return [without_layout_only_keys(v) for v in value]
    return value


def shape_hash(value):
    text = json.dumps(without_layout_only_keys(value), sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def state_columns(transitions, start):
    """Column of each state: its breadth-first distance from start. States start cannot reach share a last column."""
    column = {start: 0} if start is not None else {}
    queue = collections.deque(column)
    while queue:
        state = queue.popleft()
        for t in transitions:
            if t["from"] == state and t["to"] not in column:
                column[t["to"]] = column[state] + 1
                queue.append(t["to"])
    last = max(column.values()) + 1 if column else 0
    for t in transitions:
        for key in ("from", "to"):
            column.setdefault(t[key], last)
    return column


def state_start(lifecycle):
    initial = lifecycle.get("initial")
    names = sequence_participants(lifecycle.get("transitions") or [])
    return initial if initial in names else None


def state_order(lifecycle):
    transitions = lifecycle.get("transitions") or []
    names = sequence_participants(transitions)
    column = state_columns(transitions, state_start(lifecycle) or (names[0] if names else None))
    return sorted(names, key=lambda name: column[name])


def state_key(lifecycle):
    """Transitions grouped by source state in column order, each with its number (position in this key, from 1)."""
    transitions = lifecycle.get("transitions") or []
    grouped = [t for name in state_order(lifecycle) for t in transitions if t["from"] == name]
    return [dict(t, number=i + 1) for i, t in enumerate(grouped)]


def flow_overview(flow):
    parts = [p["id"] for p in flow.get("parts") or []]
    caller_ids = {c["id"] for c in flow.get("callers") or []}
    dependency_ids = {d["id"] for d in flow.get("dependencies") or []}
    edges = flow.get("edges") or []

    def unique(pairs):
        return list(dict.fromkeys(pairs))

    reached = {e["to"] for e in edges if e["from"] in caller_ids}
    return {
        "parts": parts,
        "callers": len(caller_ids),
        "dependencies": len(dependency_ids),
        "caller_targets": [p for p in parts if p in reached],
        "links": unique((e["from"], e["to"]) for e in edges if e["from"] in parts and e["to"] in parts),
        "callbacks": unique((e["from"], e["to"]) for e in edges if e["from"] in dependency_ids and e["to"] in parts),
    }


def part_cards(flow):
    labels = {n["id"]: n.get("label") or n["id"]
              for kind in ("parts", "callers", "dependencies") for n in flow.get(kind) or []}
    edges = flow.get("edges") or []
    return [{
        "id": part["id"],
        "label": labels[part["id"]],
        "called_by": [(labels.get(e["from"], e["from"]), e.get("label") or "") for e in edges if e["to"] == part["id"]],
        "calls": [(labels.get(e["to"], e["to"]), e.get("label") or "") for e in edges if e["from"] == part["id"]],
    } for part in flow.get("parts") or []]


def note_text(text):
    """Text for a Markdown line outside a code block: one line, with `<` as `&lt;` so Markdown keeps it."""
    return " ".join(str(text).split()).replace("<", "&lt;")


def key_line(source, target, label):
    return "%s → %s: %s" % (source, target, label) if label else "%s → %s" % (source, target)


def display_width(text):
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in text)


def pad(text, width, fill=" "):
    return text + fill * max(0, width - display_width(text))


def short(text, notes=None, width=MAX_LABEL):
    """Cut text to width columns. With a notes dict, a cut label ends in …[n] and its full text is kept in notes."""
    text = " ".join(str(text).split())
    if display_width(text) <= width:
        return text
    marker = "…" if notes is None else "…[%d]" % notes.setdefault(text, len(notes) + 1)
    kept = ""
    for ch in text:
        if display_width(kept + ch) + display_width(marker) > width:
            break
        kept += ch
    return kept + marker


def wrap_by_width(text, width, indent):
    """Wrap by display width, at a space when one fits. Continuation lines start with indent spaces."""
    lines, rest, limit = [], text, width
    while display_width(rest) > limit:
        cut = used = 0
        for ch in rest:
            if used + display_width(ch) > limit:
                break
            used += display_width(ch)
            cut += 1
        space = rest.rfind(" ", 1, cut + 1)
        cut = space if space > 0 else cut
        lines.append(" " * (width - limit) + rest[:cut].rstrip())
        rest, limit = rest[cut:].lstrip(), width - indent
    return lines + [" " * (width - limit) + rest]


def with_footnotes(lines, notes):
    if not notes:
        return lines
    footnotes = []
    for full, number in notes.items():
        footnotes += wrap_by_width("[%d] %s" % (number, full), NOTE_COLUMNS, 4)
    return lines + ["", "labels:"] + footnotes


def read_deep_dives(contract_folder, diagrams):
    present = subjects(diagrams)
    result = []
    for path in sorted(glob.glob(os.path.join(contract_folder, "diagrams", "*.html"))):
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        stamp = {}
        for tag in META_TAG.findall(text):
            name, content = META_NAME.search(tag), META_CONTENT.search(tag)
            if name and content:
                stamp[name.group(1)] = html.unescape(content.group(1))
        subject, stamped_hash = stamp.get("wstack-subject"), stamp.get("wstack-subject-hash")
        if not subject or not stamped_hash:
            state = "not stamped"
        elif subject not in present:
            state = "subject removed"
        elif shape_hash(present[subject]) != stamped_hash:
            state = "stale"
        else:
            state = "fresh"
        result.append({"path": os.path.abspath(path), "name": os.path.basename(path),
                       "subject": subject or None, "state": state})
    return result


def sequence_participants(steps):
    names = []
    for step in steps:
        for key in ("from", "to"):
            if step[key] not in names:
                names.append(step[key])
    return names


def note_flow(flow):
    notes = {}
    overview = flow_overview(flow)
    cards = part_cards(flow)
    labels = {n["id"]: n.get("label") or n["id"]
              for kind in ("parts", "callers", "dependencies") for n in flow.get(kind) or []}
    inner = NOTE_COLUMNS - 4
    rows = []
    for card in cards:
        marker = " ◀ callers" if card["id"] in overview["caller_targets"] else ""
        rows.append(short(card["label"], notes, inner - display_width(marker)) + marker)
        rows += ["  ─▶ " + short(labels[target], notes, inner - 5)
                 for source, target in overview["links"] if source == card["id"]]
        rows += ["  ◀─ " + short(labels[source], notes, inner - 5)
                 for source, target in overview["callbacks"] if target == card["id"]]
    box = ["┌ parts " + "─" * (NOTE_COLUMNS - 9) + "┐"]
    box += ["│ " + pad(row, inner) + " │" for row in rows]
    box += ["└" + "─" * (NOTE_COLUMNS - 2) + "┘"]
    callers, dependencies = overview["callers"], overview["dependencies"]
    drawing = []
    if callers:
        drawing += ["%d %s" % (callers, "caller" if callers == 1 else "callers"), "  ▼"]
    drawing += box
    if dependencies:
        drawing += ["  ▼", "%d %s" % (dependencies, "dependency" if dependencies == 1 else "dependencies")]
    lines = ["```text"] + with_footnotes(drawing, notes) + ["```", ""]
    for card in cards:
        lines += ["**%s**" % note_text(card["label"]), ""]
        for heading, entries in (("called by", card["called_by"]), ("calls", card["calls"])):
            if entries:
                lines += ["- %s:" % heading] + ["  - " + (": ".join(map(note_text, e)) if e[1] else note_text(e[0]))
                                                 for e in entries]
        lines.append("")
    return lines[:-1]


def note_sequence(sequence):
    return ["%d. %s" % (number, key_line(note_text(step["from"]), note_text(step["to"]),
                                         note_text(step.get("label") or "")))
            for number, step in enumerate(sequence.get("steps") or [], 1)]


def note_states(lifecycle):
    lines = []
    start = state_start(lifecycle)
    if start:
        lines += ["Start: %s" % note_text(start), ""]
    for state in state_order(lifecycle):
        outgoing = [t for t in state_key(lifecycle) if t["from"] == state]
        if not outgoing:
            continue
        lines += ["**%s**" % note_text(state), ""]
        lines += ["%d. → %s" % (t["number"], ": ".join(filter(None, (note_text(t["to"]),
                                                                       note_text(t.get("label") or "")))))
                  for t in outgoing]
        lines.append("")
    return lines[:-1]


def note_architecture(architecture):
    notes = {}
    layers = architecture.get("layers") or []
    nested = [layer for layer in layers if not layer.get("sibling")]
    trees = []

    def component_rows(components, indent, has_nested_layer):
        rows = []
        for i, component in enumerate(components):
            last = i == len(components) - 1 and not has_nested_layer
            label = short(component.get("label") or component["id"], notes, NOTE_COLUMNS - indent - 3)
            rows.append(" " * indent + ("└─ " if last else "├─ ") + label)
        return rows

    nested_rows = []
    for depth, layer in enumerate(nested):
        name_indent = max(0, 3 * depth - 3)
        name = short(layer["name"], notes, NOTE_COLUMNS - name_indent - (3 if depth else 0))
        nested_rows.append(" " * name_indent + ("└─ " if depth else "") + name)
        nested_rows += component_rows(layer.get("components") or [], 3 * depth, depth < len(nested) - 1)
    if nested_rows:
        trees.append(nested_rows)
    for layer in (layer for layer in layers if layer.get("sibling")):
        title = short("%s (beside the nested layers)" % layer["name"], notes, NOTE_COLUMNS)
        trees.append([title] + component_rows(layer.get("components") or [], 0, False))

    drawing = [row for i, tree in enumerate(trees) for row in ([""] if i else []) + tree]
    lines = ["```text"] + with_footnotes(drawing, notes) + ["```"]
    labels = {c["id"]: note_text(c.get("label") or c["id"]) for layer in layers for c in layer.get("components") or []}
    implements = architecture.get("implements") or []
    if implements:
        lines += ["", "Implements:", ""]
        lines += ["- %s ─▶ %s" % (labels.get(i["adapter"], i["adapter"]), labels.get(i["port"], i["port"]))
                  for i in implements]
    return lines


def heading_text(text):
    return " ".join(HEADING_UNSAFE.sub(" ", str(text)).split())


def note_lines(diagrams, deep_dives):
    present = subjects(diagrams)
    if not present and not deep_dives:
        return []
    out = ["## Diagrams", ""]
    for subject, value in present.items():
        kind, _, _ = subject.partition(":")
        title = heading_text(value.get("title") or value.get("id", "")) if kind != "flow" else ""
        if kind == "flow":
            out += ["### Component flow", ""] + note_flow(value)
        elif kind == "sequence":
            out += ["### Sequence: %s" % title, ""] + note_sequence(value)
        elif kind == "states":
            out += ["### States: %s" % title, ""] + note_states(value)
        else:
            out += ["### Architecture (%s)" % heading_text(value.get("style", "")), ""] + note_architecture(value)
        out.append("")
    if deep_dives:
        out += ["### Deep dives", ""]
        for dive in deep_dives:
            mark = "" if dive["state"] == "fresh" else " (%s)" % dive["state"]
            out.append("- [%s](diagrams/%s)%s" % (dive["name"], quote(dive["name"]), mark))
        out.append("")
    return out


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("hash", "subject"):
        sys.exit("usage: contract_diagrams.py hash|subject <subject>")
    command, wanted = sys.argv[1:]
    present = subjects((json.load(sys.stdin) or {}).get("diagrams") or {})
    if wanted not in present:
        sys.stderr.write("no subject: %s\nsubjects: %s\n" % (wanted, ", ".join(present)))
        sys.exit(1)
    print(shape_hash(present[wanted]) if command == "hash" else json.dumps(present[wanted], indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

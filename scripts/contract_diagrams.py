#!/usr/bin/env python3
"""Subjects, shape hashes, deep dive state, ASCII drawings, and the note section of contract diagrams.

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
    """Transitions grouped by source state in column order, each with its number (YAML index + 1)."""
    transitions = lifecycle.get("transitions") or []
    numbered = [dict(t, number=i + 1) for i, t in enumerate(transitions)]
    return [t for name in state_order(lifecycle) for t in numbered if t["from"] == name]


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


def with_footnotes(drawing, notes):
    if not notes:
        return drawing
    return "\n".join([drawing, "", "labels:"] + ["[%d] %s" % (n, full) for full, n in notes.items()])


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


def edge_arrow(label, forward, notes):
    body = "──%s──" % short(label, notes) if label else "──"
    return body + "▶" if forward else "◀" + body


def ascii_flow(flow):
    notes = {}
    parts = flow.get("parts") or []
    callers = flow.get("callers") or []
    dependencies = flow.get("dependencies") or []
    names = {n["id"]: short(n.get("label") or n["id"]) for n in parts + callers + dependencies}
    caller_ids = {c["id"] for c in callers}
    dependency_ids = {d["id"] for d in dependencies}
    part_ids = [p["id"] for p in parts]
    left_by_part = {pid: [] for pid in part_ids}
    right_by_part = {pid: [] for pid in part_ids}
    inside_rows = []
    for edge in flow.get("edges") or []:
        source, target, label = edge["from"], edge["to"], edge.get("label")
        outer_is_caller = source in caller_ids or target in caller_ids
        if outer_is_caller or source in dependency_ids or target in dependency_ids:
            outer_ids = caller_ids if outer_is_caller else dependency_ids
            outer, other = (source, target) if source in outer_ids else (target, source)
            if not part_ids:
                continue
            owner = other if other in left_by_part else part_ids[0]
            if outer_is_caller:
                left_by_part[owner].append((names[outer], edge_arrow(label, source == outer, notes), source == outer))
            else:
                right_by_part[owner].append("%s %s" % (edge_arrow(label, target == outer, notes), names[outer]))
        else:
            middle = " ── %s ──▶ " % short(label, notes) if label else " ──▶ "
            inside_rows.append("inside: %s%s%s" % (names[source], middle, names[target]))
    left_width = max([display_width(n) + 1 + display_width(b)
                      for rows in left_by_part.values() for n, b, _ in rows] + [0])
    inner = max([display_width(names[pid]) for pid in part_ids] + [1])
    box_lines = [("┌" + "─" * (inner + 2) + "┐", "", "")]
    for pid in part_ids:
        left, right = left_by_part[pid], right_by_part[pid]
        for row in range(max(1, len(left), len(right))):
            label = names[pid] if row == 0 else ""
            left_text = ""
            if row < len(left):
                name, body, forward = left[row]
                extra = "─" * (left_width - display_width(name) - 1 - display_width(body))
                body = body[:-1] + extra + body[-1] if forward else body + extra
                left_text = "%s %s" % (name, body)
            box_lines.append(("│ " + pad(label, inner) + " │", left_text, right[row] if row < len(right) else ""))
    box_lines.append(("└" + "─" * (inner + 2) + "┘", "", ""))
    lines = [(pad(left, left_width) + " " + box + " " + right).rstrip() for box, left, right in box_lines]
    return with_footnotes("\n".join(lines + inside_rows), notes)


def sequence_participants(steps):
    names = []
    for step in steps:
        for key in ("from", "to"):
            if step[key] not in names:
                names.append(step[key])
    return names


def ascii_sequence(sequence):
    notes = {}
    steps = sequence.get("steps") or []
    names = sequence_participants(steps)
    if not names:
        return ""
    widths = [display_width(n) for n in names]
    gaps = [(widths[i] + widths[i + 1] + 1) // 2 + 2 for i in range(len(names) - 1)]
    spans = []
    for step in steps:
        low, high = sorted((names.index(step["from"]), names.index(step["to"])))
        label_width = display_width(short(step.get("label", ""), notes))
        if low == high and high + 1 < len(names):
            spans.append((low, high + 1, label_width + 6))
        elif low != high:
            spans.append((low, high, label_width + 5))
    for low, high, need in sorted(spans, key=lambda s: s[1] - s[0]):
        deficit = need - sum(gaps[low:high])
        if deficit > 0:
            gaps[high - 1] += deficit
    centers = [widths[0] // 2]
    for gap in gaps:
        centers.append(centers[-1] + gap)

    rows = []

    def put(row, col, text):
        cells = rows[row]
        for ch in text:
            while len(cells) <= col:
                cells.append(" ")
            cells[col] = ch
            col += 1
            if display_width(ch) == 2:
                while len(cells) <= col:
                    cells.append(" ")
                cells[col] = ""
                col += 1

    def new_row():
        rows.append([])
        for center in centers:
            put(len(rows) - 1, center, "│")
        return len(rows) - 1

    rows.append([])
    for name, center, width in zip(names, centers, widths):
        put(0, center - width // 2, name)
    for step in steps:
        source, target = names.index(step["from"]), names.index(step["to"])
        label = short(step.get("label", ""), notes)
        row = new_row()
        if source == target:
            put(row, centers[source], "│──┐ " + label)
            put(new_row(), centers[source], "│◀─┘")
            continue
        low, high = min(source, target), max(source, target)
        room = centers[high] - centers[low] - 1
        if source < target:
            body = pad("──" + label, room - 1, "─") + "▶"
        else:
            body = "◀" + pad("──" + label, room - 1, "─")
        put(row, centers[low] + 1, body)
    return with_footnotes("\n".join("".join(cells).rstrip() for cells in rows), notes)


def ascii_states(lifecycle):
    notes = {}
    transitions = lifecycle.get("transitions") or []
    from_width = max([display_width(t["from"]) for t in transitions] + [0])
    label_width = max([display_width(short(t.get("label", ""), notes)) for t in transitions] + [0])
    lines = ["initial: %s" % lifecycle.get("initial", "")]
    for t in transitions:
        lines.append("%s ──%s──▶ %s" % (pad(t["from"], from_width), pad(short(t.get("label", ""), notes), label_width, "─"), t["to"]))
    return with_footnotes("\n".join(lines), notes)


def box(title, inner_lines):
    inner = max([display_width(title) + 2] + [display_width(l) for l in inner_lines])
    top = "┌─ %s " % title
    lines = [top + "─" * (inner + 2 - display_width(top) + 1) + "┐"]
    lines += ["│ " + pad(l, inner) + " │" for l in inner_lines]
    return lines + ["└" + "─" * (inner + 2) + "┘"]


def ascii_architecture(architecture):
    layers = architecture.get("layers") or []
    labels = {c["id"]: short(c.get("label") or c["id"]) for layer in layers for c in layer.get("components") or []}
    boxes = lambda group: [labels[c["id"]] for c in group.get("components") or []]
    lines = []
    for layer in reversed([l for l in layers if not l.get("sibling")]):
        lines = box(layer["name"], boxes(layer) + lines)
    for layer in [l for l in layers if l.get("sibling")]:
        beside = box(layer["name"], boxes(layer))
        left_width = max([display_width(l) for l in lines] + [0])
        gap = " " if lines else ""
        rows = range(max(len(lines), len(beside)))
        lines = [(pad(lines[r] if r < len(lines) else "", left_width) + gap + (beside[r] if r < len(beside) else "")).rstrip()
                 for r in rows]
    ports = ["%s <- %s" % (labels.get(i["port"], i["port"]), labels.get(i["adapter"], i["adapter"]))
             for i in architecture.get("implements") or []]
    if ports:
        lines.append("ports: " + ", ".join(ports))
    return "\n".join(lines)


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
            out.append("### Component flow")
            drawing = ascii_flow(value)
        elif kind == "sequence":
            out.append("### Sequence: %s" % title)
            drawing = ascii_sequence(value)
        elif kind == "states":
            out.append("### States: %s" % title)
            drawing = ascii_states(value)
        else:
            out.append("### Architecture (%s)" % heading_text(value.get("style", "")))
            drawing = ascii_architecture(value)
        out += ["", "```text", drawing, "```", ""]
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

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


def without_refs(value):
    if isinstance(value, dict):
        return {k: without_refs(v) for k, v in value.items() if k != "refs"}
    if isinstance(value, list):
        return [without_refs(v) for v in value]
    return value


def shape_hash(value):
    text = json.dumps(without_refs(value), sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def display_width(text):
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in text)


def pad(text, width, fill=" "):
    return text + fill * max(0, width - display_width(text))


def short(text):
    text = " ".join(str(text).split())
    return text if len(text) <= MAX_LABEL else text[:MAX_LABEL - 1] + "…"


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


def edge_arrow(label, forward):
    body = "──%s──" % short(label) if label else "──"
    return body + "▶" if forward else "◀" + body


def ascii_flow(flow):
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
                left_by_part[owner].append((names[outer], edge_arrow(label, source == outer), source == outer))
            else:
                right_by_part[owner].append("%s %s" % (edge_arrow(label, target == outer), names[outer]))
        else:
            middle = " ── %s ──▶ " % short(label) if label else " ──▶ "
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
    return "\n".join(lines + inside_rows)


def sequence_participants(steps):
    names = []
    for step in steps:
        for key in ("from", "to"):
            if step[key] not in names:
                names.append(step[key])
    return names


def ascii_sequence(sequence):
    steps = sequence.get("steps") or []
    names = sequence_participants(steps)
    if not names:
        return ""
    widths = [display_width(n) for n in names]
    gaps = [(widths[i] + widths[i + 1] + 1) // 2 + 2 for i in range(len(names) - 1)]
    spans = []
    for step in steps:
        low, high = sorted((names.index(step["from"]), names.index(step["to"])))
        label_width = display_width(short(step.get("label", "")))
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
        label = short(step.get("label", ""))
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
    return "\n".join("".join(cells).rstrip() for cells in rows)


def ascii_states(lifecycle):
    transitions = lifecycle.get("transitions") or []
    from_width = max([display_width(t["from"]) for t in transitions] + [0])
    label_width = max([display_width(short(t.get("label", ""))) for t in transitions] + [0])
    lines = ["initial: %s" % lifecycle.get("initial", "")]
    for t in transitions:
        lines.append("%s ──%s──▶ %s" % (pad(t["from"], from_width), pad(short(t.get("label", "")), label_width, "─"), t["to"]))
    return "\n".join(lines)


def box(title, inner_lines):
    inner = max([display_width(title) + 2] + [display_width(l) for l in inner_lines])
    top = "┌─ %s " % title
    lines = [top + "─" * (inner + 2 - display_width(top) + 1) + "┐"]
    lines += ["│ " + pad(l, inner) + " │" for l in inner_lines]
    return lines + ["└" + "─" * (inner + 2) + "┘"]


def ascii_architecture(architecture):
    layers = architecture.get("layers") or []
    labels = {c["id"]: short(c.get("label") or c["id"]) for layer in layers for c in layer.get("components") or []}
    lines = []
    for layer in reversed(layers):
        own = [labels[c["id"]] for c in layer.get("components") or []]
        lines = box(layer["name"], own + lines)
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

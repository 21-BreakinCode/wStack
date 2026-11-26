# Diagram Fixes Implementation Plan

**Goal:** Fix the four diagram problems that the media-center run on 0.10.0 found. Ship as wStack 0.11.0.

**Source:** the media-center run report of 2026-11-26. The user picked all four fixes: SVG states routing, the ASCII label cut, a sibling layer, and a deep dive merge hint. The user asked for the build and the release without more questions, so the calls below are the controller's.

## Decisions

- ASCII labels: a label longer than 32 characters still gets cut, so the diagrams stay narrow. A cut label ends in `…[n]`, and a `labels:` list under the drawing gives each full label once: `[n] <full label>`. Nothing is lost, and the width does not grow.
- Sibling layer: an architecture layer can carry `sibling: true`. It is a layer that sits beside the nested layers, for example workers that can import every layer. Both views draw it next to the nested boxes, not around them.
- SVG states: back and cross arrows get separate lanes below the row, with a different depth for each arrow. Labels sit at the lowest point of their arrow, and labels never overlap each other or a box.
- Deep dive hint: several parts can call one dependency. Then the Draw steps let diagram-design draw one arrow from the service zone to that dependency, with a sublabel that names the parts. It can also merge many callers of one part into one node with a count. This is a skill text change only. The rule "add nothing that the JSON does not hold" stays.

## Global constraints

- bash 3.2 for scripts, Python 3.9 standard library, yq 4.30.8 or later. Quote every path. Tests never write into `$HOME/Projects/LifeOS/`.
- No company-internal names in code or tests.
- A contract with no `diagrams` key renders as before. A contract without `sibling` renders as in 0.10.1.
- The shape hash covers every key except `refs`, so `sibling: true` changes the hash of `architecture`. That is correct: it changes the drawing.

## Tasks

1. ASCII label footnotes in `scripts/contract_diagrams.py`, for the flow and the sequences. The states list and the architecture boxes have no arrow labels to cut. Tests in `tests/contract/test_contract_diagrams.py`.
2. Sibling layer: the validation rule (`sibling` is a boolean), ASCII and SVG drawing, `execute.md` and `agents/reviewer.md` text. Tests in the validate, diagrams, and SVG test files.
3. SVG states routing in `scripts/contract_diagrams_svg.py`, tested with a fixture that has the shape of the media-center lifecycle: 4 states, 8 transitions, 4 of them back or cross arrows, labels up to 40 characters.
4. Skill text for the deep dive hint in `skills/draw-contract/SKILL.md`, plus README, `docs/spec.md`, and a CHANGELOG entry `## 0.11.0`.

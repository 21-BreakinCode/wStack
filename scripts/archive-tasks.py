#!/usr/bin/env python3
"""Move finished tasks into <tasks_dir>/_archive/<week>/ with the Obsidian CLI, so Obsidian updates links.

Exit 0: every named task was handled. Exit 1: bad input. Exit 3: the pre-check failed, nothing moved.
Exit 4: a move back failed, the run stopped.
"""
import argparse
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "handover"))
from obsidian_cli import ObsidianCliError, run_cli  # noqa: E402

FINISHED_STATUSES = ("delivered", "cancelled")


def read_status(spec_path):
    with open(spec_path, encoding="utf-8") as spec:
        lines = spec.read().splitlines()
    if not lines or lines[0].strip() != "---":
        return ""
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line.startswith("status:"):
            return line[len("status:"):].strip()
    return ""


def cli_move(from_rel, to_rel):
    output = run_cli("move", "path=" + from_rel, "to=" + to_rel)
    if not output.startswith("Moved:"):
        raise ObsidianCliError(output or "empty output from obsidian move")


def precheck_failure(vault):
    app_json = os.path.join(vault, ".obsidian", "app.json")
    try:
        with open(app_json, encoding="utf-8") as app_file:
            always_update = json.load(app_file).get("alwaysUpdateLinks")
    except (OSError, ValueError) as unreadable:
        return "cannot read %s: %s" % (app_json, unreadable)
    if always_update is not True:
        return "alwaysUpdateLinks is not true in %s, so links would break" % app_json
    try:
        open_vault = run_cli("vault", "info=path")
    except ObsidianCliError as cli_error:
        return "Obsidian is not running or not reachable: %s" % cli_error
    if os.path.realpath(open_vault) != os.path.realpath(vault):
        return "Obsidian has another vault open: %s" % open_vault
    return None


def list_task_files(task_folder):
    found = []
    for folder, _, names in os.walk(task_folder):
        for name in names:
            found.append(os.path.relpath(os.path.join(folder, name), task_folder))
    return sorted(found)


def remove_empty_folders(root):
    for folder, _, _ in os.walk(root, topdown=False):
        try:
            os.rmdir(folder)
        except OSError:
            pass


def archive_task(vault, tasks_dir, week, task_id):
    """Return (message, back_failure_text). back_failure_text is not None only when a move back failed."""
    task_folder = os.path.join(vault, tasks_dir, task_id)
    spec_path = os.path.join(task_folder, "spec.md")
    if not os.path.isfile(spec_path):
        return "not moved %s: no spec.md at the top level of %s" % (task_id, tasks_dir), None
    status = read_status(spec_path)
    if status not in FINISHED_STATUSES:
        return "not moved %s: status %s" % (task_id, status or "missing"), None
    dest_rel = "/".join([tasks_dir, "_archive", week, task_id])
    dest_folder = os.path.join(vault, dest_rel)
    if os.path.exists(dest_folder):
        return "not moved %s: destination exists %s" % (task_id, dest_rel), None

    files = list_task_files(task_folder)
    for inner in sorted({os.path.dirname(name) for name in files}):
        os.makedirs(os.path.join(dest_folder, inner), exist_ok=True)
    time.sleep(float(os.environ.get("WSTACK_ARCHIVE_WAIT", "2")))

    moved = []
    for name in files:
        try:
            cli_move("/".join([tasks_dir, task_id, name]), "/".join([dest_rel, name]))
        except ObsidianCliError as move_error:
            failure = "%s: %s" % (name, move_error)
            break
        moved.append(name)
    else:
        remove_empty_folders(task_folder)
        return "moved %s -> %s" % (task_id, dest_rel), None

    for name in reversed(moved):
        try:
            cli_move("/".join([dest_rel, name]), "/".join([tasks_dir, task_id, name]))
        except ObsidianCliError:
            in_old = [n for n in files if os.path.exists(os.path.join(task_folder, n))]
            in_archive = [n for n in files if os.path.exists(os.path.join(dest_folder, n))]
            lines = ["move back failed for %s, run stopped" % task_id, "left in old folder:"]
            lines += ["  %s/%s/%s" % (tasks_dir, task_id, n) for n in in_old]
            lines.append("left in archive:")
            lines += ["  %s/%s" % (dest_rel, n) for n in in_archive]
            return "\n".join(lines), True
    remove_empty_folders(dest_folder)
    return "not moved %s: %s" % (task_id, failure), None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--vault", required=True)
    parser.add_argument("--tasks-dir", required=True)
    parser.add_argument("--week", required=True)
    parser.add_argument("task_ids", nargs="+")
    args = parser.parse_args()
    if not os.path.isabs(args.vault) or not os.path.isdir(args.vault):
        sys.exit("archive-tasks: --vault must be an existing absolute folder")
    if not re.fullmatch(r"\d{4}-W\d{2}", args.week):
        sys.exit("archive-tasks: --week must look like 2026-W49")
    if os.path.isabs(args.tasks_dir) or ".." in args.tasks_dir.split("/"):
        sys.exit("archive-tasks: --tasks-dir must be relative to the vault")
    tasks_dir = args.tasks_dir.strip("/")
    for task_id in args.task_ids:
        if "/" in task_id or task_id in ("", ".", "..", "_archive"):
            sys.exit("archive-tasks: bad task id: %s" % task_id)

    failure = precheck_failure(args.vault)
    if failure:
        print("archive-tasks: " + failure, file=sys.stderr)
        sys.exit(3)

    for task_id in args.task_ids:
        message, back_failed = archive_task(args.vault, tasks_dir, args.week, task_id)
        print(message)
        if back_failed:
            sys.exit(4)


if __name__ == "__main__":
    main()

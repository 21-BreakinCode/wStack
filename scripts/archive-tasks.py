#!/usr/bin/env python3
"""Move finished tasks into <tasks_dir>/_archive/<week>/ with the Obsidian CLI, so Obsidian updates links.

Exit 0: every named task was handled. Exit 1: bad input. Exit 3: the pre-check failed, nothing moved.
Exit 4: the run stopped. A task can sit in two folders, or SIGTERM, SIGINT, or an unexpected error came during the moves.
"""
import argparse
import json
import os
import re
import signal
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "handover"))
from obsidian_cli import ObsidianCliError, run_cli  # noqa: E402

FINISHED_STATUSES = ("delivered", "cancelled")
STOP_SIGNALS = (signal.SIGTERM, signal.SIGINT)
inside_moves = False  # a stop signal raises Stopped only while the moves of a task run
held_stop_signals = []  # at other times the signal waits here, so a move back and its report finish


class Stopped(BaseException):
    pass


def on_stop_signal(signum, _frame):
    name = signal.Signals(signum).name
    if inside_moves:
        raise Stopped(name)
    held_stop_signals.append(name)


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


def is_unindexed(parent, name):
    return name.startswith(".") or os.path.islink(os.path.join(parent, name))


def list_task_entries(task_folder):
    """Return (notes, raw). Notes move with the CLI. Raw entries (dot names, symlinks, file names with no dot) move with os.rename."""
    notes, raw = [], []
    for folder, dir_names, file_names in os.walk(task_folder):
        for name in list(dir_names):
            if is_unindexed(folder, name):
                dir_names.remove(name)
                raw.append(os.path.relpath(os.path.join(folder, name), task_folder))
        for name in file_names:
            target = raw if is_unindexed(folder, name) or "." not in name else notes  # the CLI reads a to= with no dot as a folder
            target.append(os.path.relpath(os.path.join(folder, name), task_folder))
    return sorted(notes), sorted(raw)


def left_entries(folder):
    """Return every file and symlink under folder. Return the folder itself if only empty folders remain."""
    found = []
    for current, dir_names, file_names in os.walk(folder):
        for name in list(dir_names):
            if os.path.islink(os.path.join(current, name)):
                dir_names.remove(name)
                found.append(os.path.join(current, name))
        found.extend(os.path.join(current, name) for name in file_names)
    return sorted(found) or [folder]


def remove_empty_folders(root):
    for folder, _, _ in os.walk(root, topdown=False):
        try:
            os.rmdir(folder)
        except OSError:
            pass


def move_entry(kind, vault, from_rel, to_rel):
    if kind == "raw":
        try:
            os.rename(os.path.join(vault, from_rel), os.path.join(vault, to_rel))
        except OSError as rename_error:
            raise ObsidianCliError(str(rename_error))
        return
    cli_move(from_rel, to_rel)


def split_report(vault, task_id, reason, old_folder, dest_folder):
    lines = ["%s for %s, run stopped" % (reason, task_id), "left in old folder:"]
    lines += ["  " + os.path.relpath(path, vault) for path in left_entries(old_folder)] if os.path.exists(old_folder) else []
    lines.append("left in archive:")
    lines += ["  " + os.path.relpath(path, vault) for path in left_entries(dest_folder)] if os.path.exists(dest_folder) else []
    return "\n".join(lines)


def archive_task(vault, tasks_dir, week, task_id):
    """Return (message, stop). stop is True when the run must stop: the task can sit in two folders, or the moves were stopped."""
    task_folder = os.path.join(vault, tasks_dir, task_id)
    spec_path = os.path.join(task_folder, "spec.md")
    if not os.path.isfile(spec_path):
        return "not moved %s: no spec.md at the top level of %s" % (task_id, tasks_dir), False
    status = read_status(spec_path)
    if status not in FINISHED_STATUSES:
        return "not moved %s: status %s" % (task_id, status or "missing"), False
    dest_rel = "/".join([tasks_dir, "_archive", week, task_id])
    dest_folder = os.path.join(vault, dest_rel)
    if os.path.exists(dest_folder):
        return "not moved %s: destination exists %s" % (task_id, dest_rel), False

    notes, raw = list_task_entries(task_folder)
    global inside_moves
    moved, failure, stop_reason = [], None, None
    inside_moves = True
    try:
        for inner in sorted({os.path.dirname(name) for name in notes + raw}):
            os.makedirs(os.path.join(dest_folder, inner), exist_ok=True)
        time.sleep(float(os.environ.get("WSTACK_ARCHIVE_WAIT", "2")))
        for kind, name in [("note", name) for name in notes] + [("raw", name) for name in raw]:
            try:
                move_entry(kind, vault, "/".join([tasks_dir, task_id, name]), "/".join([dest_rel, name]))
            except ObsidianCliError as move_error:
                failure = "%s: %s" % (name, move_error)
                break
            moved.append((kind, name))
    except BaseException as abort:  # a kill, an interrupt, or an unexpected error: move back, report, stop the run
        inside_moves = False
        what = str(abort) if isinstance(abort, Stopped) else "an unexpected error, %s: %s" % (type(abort).__name__, abort)
        failure = stop_reason = "stopped by %s during the moves" % what
    inside_moves = False

    if failure is None:
        remove_empty_folders(task_folder)
        if os.path.exists(task_folder):
            return split_report(vault, task_id, "source folder not empty after the move", task_folder, dest_folder), True
        return "moved %s -> %s" % (task_id, dest_rel), False

    for kind, name in reversed(moved):
        try:
            move_entry(kind, vault, "/".join([dest_rel, name]), "/".join([tasks_dir, task_id, name]))
        except Exception:
            return split_report(vault, task_id, "move back failed", task_folder, dest_folder), True
    remove_empty_folders(dest_folder)
    for empty_parent in (os.path.dirname(dest_folder), os.path.join(vault, tasks_dir, "_archive")):  # the week folder, then _archive
        try:
            os.rmdir(empty_parent)
        except OSError:
            pass
    if os.path.exists(dest_folder):
        return split_report(vault, task_id, "archive folder not empty after the move back", task_folder, dest_folder), True
    if stop_reason:
        return split_report(vault, task_id, stop_reason, task_folder, dest_folder), True
    return "not moved %s: %s" % (task_id, failure), False


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
    if not tasks_dir:
        sys.exit("archive-tasks: --tasks-dir must name a folder inside the vault")
    for task_id in args.task_ids:
        if "/" in task_id or task_id in ("", ".", "..", "_archive"):
            sys.exit("archive-tasks: bad task id: %s" % task_id)

    failure = precheck_failure(args.vault)
    if failure:
        print("archive-tasks: " + failure, file=sys.stderr)
        sys.exit(3)

    for stop_signal in STOP_SIGNALS:
        signal.signal(stop_signal, on_stop_signal)
    for task_id in args.task_ids:
        if held_stop_signals:
            print("run stopped by %s before %s" % (held_stop_signals[0], task_id), flush=True)
            sys.exit(4)
        message, stop = archive_task(args.vault, tasks_dir, args.week, task_id)
        print(message, flush=True)
        if stop:
            sys.exit(4)


if __name__ == "__main__":
    main()

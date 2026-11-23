"""Call the `obsidian` CLI. It exits 0 even on failure, so the output text decides."""
import os
import subprocess

CLI_TIMEOUT_SECONDS = 45
CLI_ERROR_PREFIX = "Error:"


class ObsidianCliError(RuntimeError):
    pass


def parse_cli_output(stdout: str) -> str:
    output = stdout.strip()
    if output.startswith(CLI_ERROR_PREFIX):
        raise ObsidianCliError(output)
    return output


def run_cli(*args: str) -> str:
    try:
        completed = subprocess.run([os.environ.get("WSTACK_OBSIDIAN_BIN", "obsidian"), *args], capture_output=True, text=True,
                                   timeout=CLI_TIMEOUT_SECONDS)
    except FileNotFoundError as missing_cli:
        raise ObsidianCliError("`obsidian` CLI not found on PATH") from missing_cli
    except subprocess.TimeoutExpired as timeout:
        raise ObsidianCliError(f"`obsidian {args[0]}` timed out after {CLI_TIMEOUT_SECONDS}s") from timeout
    if completed.returncode != 0:
        raise ObsidianCliError(completed.stderr.strip() or f"`obsidian {args[0]}` exited {completed.returncode}")
    return parse_cli_output(completed.stdout)

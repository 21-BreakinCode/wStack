---
name: capture-evidence
description: Use only inside a wStack task session, to capture and publish evidence.
user-invocable: false
---

# Evidence

Record one evidence set for each check in the spec's verification plan. Do this during Verify.

## Working folder

Save all files in `/tmp/wstack-evidence/<task_id>/`. Run `mkdir -p` on it and on its `raw/` folder first. Never save media in the Obsidian vault.

Name each file after its check, for example `check-1` or `check-2-flow`.

Capture raw screenshots and videos into `/tmp/wstack-evidence/<task_id>/raw/`. `compress-media.sh` exits 1 when its output path equals its input path, so never compress a file into its own folder.

## Capture by check kind

### API check

1. Run the request with `curl -v` and pipe the log through the redactor.

   ```bash
   curl -v "$url" 2>&1 | bash "${CLAUDE_PLUGIN_ROOT}/scripts/redact-log.sh" /dev/stdin "/tmp/wstack-evidence/<task_id>/check-1.log"
   ```

2. Open the saved log. Confirm no token, cookie, or key remains. If one remains, delete the log and stop.

The text log is the main evidence. The user reads the exact data from it.

### Web check

1. Pick a free port: `port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"`. Serve a local page with `python3 -m http.server --bind 127.0.0.1 "$port"` in the build folder. Run it in the background. When the check ends, stop it. Playwright CLI blocks `file://` URLs, so never open a file path directly.
2. Open the page: `playwright-cli -s <slug> open <url>`.
3. When the plan asks for phone width, run `playwright-cli -s <slug> resize 375 800`.
4. Start the video: `playwright-cli -s <slug> video-start /tmp/wstack-evidence/<task_id>/raw/<name>.webm`.
5. Take the screenshot: `playwright-cli -s <slug> screenshot --filename=/tmp/wstack-evidence/<task_id>/raw/<name>.webp`.
6. Stop the video: `playwright-cli -s <slug> video-stop`.
7. Close the session: `playwright-cli -s <slug> close`.

Use the task slug for `<slug>`, so parallel tasks do not share a browser. To read the page width, run `playwright-cli -s <slug> --raw eval "() => document.documentElement.scrollWidth"`. It prints the bare number.

`video-start` needs the Playwright ffmpeg build. If it fails with "Executable doesn't exist ... ffmpeg", tell the user to run `playwright-cli install-browser ffmpeg`. Do not run it yourself.

### Terminal check

Record the session with VHS. Save the recording as `.webm` or `.mp4` in the `raw/` folder. Never save it as `.gif`, because `compress-media.sh` rejects GIF files.

## Compress

Make one compressed copy of each image and video. Compress from `raw/` into the working folder.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/compress-media.sh" --target r2 <input> /tmp/wstack-evidence/<task_id>
```

The command prints the output path. Images become WebP. Videos become H.265 MP4.

In Deliver, `pr-attach.sh` makes the GitHub copies from the top-level files of the working folder and attaches them to the pull request. Text logs go in the pull request body as text.

## Record in review.md

List every evidence file under `## Evidence` in `review.md`. Use one line for each file:

```
- <check> → <file> → pass|fail
```

Every check has at least one line. A failed check keeps its line with `fail`.

Done when each check in the verification plan has a file in the working folder and a line in `review.md`.

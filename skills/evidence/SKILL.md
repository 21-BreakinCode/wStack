---
name: evidence
description: Use only inside a wStack task session, to capture and publish evidence.
user-invocable: false
---

# Evidence

Record one evidence set for each check in the spec's verification plan. Do this during Verify.

## Working folder

Save all files in `/tmp/wstack-evidence/<task_id>/`. Run `mkdir -p` on it and on its `raw/` and `gh/` folders first. Never save media in the Obsidian vault.

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

1. Serve a local page with `python3 -m http.server --bind 127.0.0.1 <port>` in the build folder. Run it in the background and stop it when the check ends. Playwright CLI blocks `file://` URLs, so never open a file path directly.
2. Open the page: `playwright-cli -s <slug> open <url>`.
3. When the plan asks for phone width, run `playwright-cli -s <slug> resize 375 800`.
4. Start the video: `playwright-cli -s <slug> video-start /tmp/wstack-evidence/<task_id>/raw/<name>.webm`.
5. Take the screenshot: `playwright-cli -s <slug> screenshot --filename=/tmp/wstack-evidence/<task_id>/raw/<name>.webp`.
6. Stop the video: `playwright-cli -s <slug> video-stop`.
7. Close the session: `playwright-cli -s <slug> close`.

Use the task slug for `<slug>`, so parallel tasks do not share a browser. To read the page width, run `playwright-cli -s <slug> --raw eval "() => document.documentElement.scrollWidth"`. It prints the bare number.

`video-start` needs the Playwright ffmpeg build. If it fails with "Executable doesn't exist ... ffmpeg", tell the user to run `playwright-cli install-browser ffmpeg`. Do not run it yourself.

### Terminal check

Record the session with VHS. Save the recording as `.gif` or `.webm` in the `raw/` folder.

## Compress

Make two copies of each image and video. Compress from `raw/`. Put the R2 copies in the working folder and the GitHub copies in `gh/`.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/compress-media.sh" --target r2 <input> /tmp/wstack-evidence/<task_id>
bash "${CLAUDE_PLUGIN_ROOT}/scripts/compress-media.sh" --target gh --max-mb <pr_media_max_mb> <input> /tmp/wstack-evidence/<task_id>/gh
```

Each command prints the output path. Images become WebP for R2 and JPEG for GitHub. Videos become H.265 MP4 for R2 and H.264 MP4 for GitHub.

If `compress-media.sh` exits 1 with "cannot fit", shorten the recording and run it again.

Task 13 attaches the `gh/` files to the pull request. Text logs go in the pull request body as text.

## Record in review.md

List every evidence file under `## Evidence` in `review.md`. Use one line for each file:

```
- <check> → <file> → pass|fail
```

Every check has at least one line. A failed check keeps its line with `fail`.

Done when each check in the verification plan has a file in the working folder and a line in `review.md`.

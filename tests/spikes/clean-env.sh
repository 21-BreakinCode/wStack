#!/bin/bash
# Run a command without the herdr variables so the spike never touches the real herdr session.
exec env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID "$@"

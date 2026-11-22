#!/usr/bin/env bash
set -euo pipefail
if [[ "$RUNNER_OS" == Linux ]]; then
  /usr/bin/mobile-release-kit-desktop >"$RUNNER_TEMP/mrk-app.log" 2>&1 &
else
  open "$MRK_APP"
fi

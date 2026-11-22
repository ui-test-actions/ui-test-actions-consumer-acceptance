#!/usr/bin/env bash
set -euo pipefail
if [[ "$RUNNER_OS" == Linux ]]; then
  pgrep -f '^/usr/bin/mobile-release-kit-desktop( |$)'
else
  pgrep -f '[/]Applications/.*[Rr]elease.*\.app/Contents/MacOS/'
fi

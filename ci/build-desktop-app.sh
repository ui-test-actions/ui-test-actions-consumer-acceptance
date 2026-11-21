#!/usr/bin/env bash
set -euo pipefail
if [[ "$RUNNER_OS" == Linux ]]; then
  sudo apt-get -o DPkg::Lock::Timeout=40 install -y --no-install-recommends \
    python3-tk xvfb xauth xdotool xclip openbox wmctrl python3-pyatspi at-spi2-core dbus-x11
fi

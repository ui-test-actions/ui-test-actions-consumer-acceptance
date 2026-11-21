#!/usr/bin/env bash
set -euo pipefail
target="${1:?}"
staging="$RUNNER_TEMP/mobile-lan-sample"
if [[ "$target" == android ]]; then
  adb -s "$LAN_DEVICE" install -r "$staging/sample.apk"
  adb -s "$LAN_DEVICE" shell input keyevent KEYCODE_WAKEUP
  adb -s "$LAN_DEVICE" shell wm dismiss-keyguard
  adb -s "$LAN_DEVICE" shell am start -W -n "$LAN_APP_ID/.MainActivity"
else
  xcrun simctl install "$LAN_DEVICE" "$staging/p2pkit-sample.app"
  if ! xcrun simctl launch "$LAN_DEVICE" "$LAN_APP_ID"; then
    python3 - "$LAN_DEVICE" <<'PY'
import subprocess
import sys

try:
    subprocess.run(["xcrun", "simctl", "spawn", sys.argv[1], "log", "show",
                    "--last", "2m", "--style", "compact",
                    "--predicate", 'process == "SpringBoard" AND eventMessage CONTAINS "dev.p2pkit.sample"'],
                   timeout=24)
except subprocess.TimeoutExpired:
    print("The Simulator did not return SpringBoard launch diagnostics within 24 seconds.")
PY
    exit 1
  fi
  if [[ "${LAN_IOS_BACKEND:-visible}" != axe ]]; then exit 0; fi
  python3 - "$LAN_DEVICE" "$staging/preflight.png" "$LAN_AXE" <<'PY'
import json
from pathlib import Path
import subprocess
import sys
import time

device, destination, axe = sys.argv[1:]
for attempt in range(3):
    try:
        subprocess.run(["xcrun", "simctl", "io", device, "screenshot", "--type=png", destination],
                       check=True, timeout=25)
        if Path(destination).read_bytes().startswith(b"\x89PNG\r\n\x1a\n"):
            break
    except (subprocess.SubprocessError, OSError) as error:
        print(f"Simulator framebuffer not yet available: {type(error).__name__}", flush=True)
    if attempt < 2:
        time.sleep(3)
else:
    sys.exit("No valid Simulator framebuffer after the P2pKit app launched")
for attempt in range(3):
    try:
        tree = json.loads(subprocess.check_output([axe, "describe-ui", "--udid", device],
                                                  timeout=18, stderr=subprocess.DEVNULL))
        if tree and tree[0].get("children") and 'start' in json.dumps(tree).casefold():
            print("The native P2pKit accessibility tree is ready.")
            break
    except (subprocess.SubprocessError, OSError, ValueError):
        pass
    if attempt < 2:
        time.sleep(3)
else:
    sys.exit("No ready native accessibility tree after the P2pKit app launched")
PY
fi

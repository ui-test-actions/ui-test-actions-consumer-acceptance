#!/usr/bin/env bash
set -euo pipefail
stage="$RUNNER_TEMP/mobile-lan-file-inputs"
mkdir -p "$stage"
python - "$stage" <<'PY'
from hashlib import sha256
from pathlib import Path
import sys

stage = Path(sys.argv[1])
pattern = bytes((index * 13 + 5) % 256 for index in range(256))
for name, size in (("qa-small.bin", 256), ("qa-medium.bin", 2 * 1024 * 1024),
                   ("qa-large.bin", 49 * 1024 * 1024)):
    path = stage / name
    with path.open("wb") as stream:
        chunk = pattern * (min(size, 1024 * 1024) // len(pattern))
        for _ in range(size // len(chunk)):
            stream.write(chunk)
    with path.open("rb") as stream:
        print(f"{sha256(stream.read()).hexdigest()}  {name} ({size} bytes)")
PY
adb -s emulator-5554 shell mkdir -p /sdcard/Download
adb -s emulator-5554 push "$stage/qa-small.bin" "$stage/qa-medium.bin" "$stage/qa-large.bin" /sdcard/Download/

#!/usr/bin/env bash
set -euo pipefail
mode="${1:?}"
out="$RUNNER_TEMP/mobile-lan-preflight"
if [[ "$mode" == seed ]]; then
  stage="$(mktemp -d "$RUNNER_TEMP/picker-inputs.XXXXXX")"
  python3 - "$stage" <<'PY'
from pathlib import Path
import sys
for index in range(10):
    (Path(sys.argv[1]) / f"qa-picker-{index:02d}.bin").write_bytes(
        bytes((byte * 13 + 5 + index) % 256 for byte in range(256)))
PY
  adb -s emulator-5554 push "$stage/"*.bin /sdcard/Download/
  exit
fi
raw="$(mktemp -d "$RUNNER_TEMP/picker-observations.XXXXXX")"
trap 'rm -rf -- "$raw"' EXIT
if [[ "$mode" == android ]]; then
  adb -s "$LAN_DEVICE" logcat -d -v epoch -s p2pkit:I ActivityManager:I |
    grep -E 'file-picker|room background policy|[fF]reez.*dev\.p2pkit\.sample\.android' > "$out/picker-logcat.txt" || true
  adb -s "$LAN_DEVICE" exec-out run-as "$LAN_APP_ID" cat no_backup/test-diagnostics/diagnostic-events.jsonl     > "$raw/events.jsonl"
  incoming="/storage/emulated/0/Android/data/$LAN_APP_ID/files/p2pkit-incoming"
  mapfile -t files < <(adb -s "$LAN_DEVICE" shell -T run-as "$LAN_APP_ID" find "$incoming" -name 'ios-test-5-MiB-*.bin' | tr -d '\r')
  if [[ "${#files[@]}" == 1 ]]; then
    adb -s "$LAN_DEVICE" shell -T run-as "$LAN_APP_ID" cat "${files[0]}" > "$raw/ios-reverse.bin"
  fi
else
  test "$mode" == ios
  package="$RUNNER_TEMP/mobile-lan-sample"
  cp "$package/SOURCE_COMMIT" "$package/SHA256SUMS" "$out/"
  container="$(xcrun simctl get_app_container "$LAN_DEVICE" "$LAN_APP_ID" data)"
  cp "$container/Library/Application Support/P2pKitTestDiagnostics/events.jsonl" "$raw/events.jsonl"
  for path in "$container/Documents/P2pKitInbox"/qa-{picker-*,small}.bin; do
    [[ -f "$path" && ! -L "$path" ]] || continue
    cp "$path" "$raw/"
  done
fi
python3 - "$mode" "$raw" "$out" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import sys

mode, raw, out = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
names = {'connection.state.changed', 'connection.authentication.succeeded', 'protocol.secure_v2.negotiated',
         'transfer.offer.received', 'transfer.offer.accepted', 'transfer.completed', 'transfer.failed',
         'transfer.durable.committed', 'file.selected', 'file.receiver.sha256', 'application.backgrounded'}
events = [event for line in (raw / 'events.jsonl').read_text().splitlines()
          if (event := json.loads(line)).get('eventName') in names]
safe_keys = {'timestamp', 'eventName', 'previousState', 'currentState', 'payloadSizeBytes', 'direction', 'outcome'}
(out / 'picker-app-events.json').write_text(json.dumps(
    [{key: value for key, value in event.items() if key in safe_keys} for event in events], indent=2) + '\n')

def compare(name, expected):
    file = raw / name
    data = file.read_bytes() if file.is_file() else b''
    return {'name': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'exact': data == expected}

if mode == 'ios' and os.environ.get('PICKER_RECHECK') == 'true':
    receipts = [compare('qa-small.bin', bytes((byte * 13 + 5) % 256 for byte in range(256)))]
elif mode == 'ios':
    receipts = [compare(f'qa-picker-{index:02d}.bin', bytes((byte * 13 + 5 + index) % 256 for byte in range(256)))
                for index in range(10)]
else:
    pattern = bytes((byte * 31 + 7) % 256 for byte in range(256))
    receipts = [compare('ios-reverse.bin', pattern * (5 * 1024 * 1024 // len(pattern)))]
(out / 'picker-content.json').write_text(json.dumps(receipts, indent=2) + '\n')
assert all(receipt['exact'] for receipt in receipts), 'Native application output missing or incorrect'
PY

#!/usr/bin/env bash
set -euo pipefail

target="${1:?}"
result="$RUNNER_TEMP/mobile-lan-preflight/app-events.json"
source="$RUNNER_TEMP/mobile-lan/diagnostic-events.jsonl"
umask 077
trap 'rm -f "$source"' EXIT
if [[ "$target" == android ]]; then
  adb -s "$LAN_DEVICE" exec-out run-as "$LAN_APP_ID" cat no_backup/test-diagnostics/diagnostic-events.jsonl > "$source"
else
  container=$(xcrun simctl get_app_container "$LAN_DEVICE" "$LAN_APP_ID" data)
  cp "$container/Library/Application Support/P2pKitTestDiagnostics/events.jsonl" "$source"
fi
python3 - "$source" "$result" <<'PY'
from collections import Counter
from pathlib import Path
import json
import sys

selected = {"peer.discovered", "peer.lost", "connection.authentication.succeeded",
            "connection.authentication.failed", "connection.state.changed", "protocol.negotiated",
            "transfer.completed", "transfer.failed", "transfer.durable.committed"}
states = {"Connected", "Disconnected", "authenticated", "secure-v2", "Completed", "Failed"}
counts = Counter()
observed = []
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    event = json.loads(line)
    name = event.get("eventName")
    if name in selected:
        counts[name] += 1
        state = event.get("currentState")
        if state in states:
            observed.append({"event": name, "state": state})
Path(sys.argv[2]).write_text(json.dumps({"event_counts": counts, "observed": observed}, indent=2) + "\n",
                             encoding="utf-8")
PY
chmod a+r "$result"

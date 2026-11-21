#!/usr/bin/env bash
set -euo pipefail

# One dedicated Ubuntu job owns this session and the connector below.
deadline=$((SECONDS + 180))
while (( SECONDS < deadline )); do
    shopt -s nullglob
    connections=("$RUNNER_TEMP"/ui-session-*/connection.json)
    if (( ${#connections[@]} == 1 )); then
        break
    fi
    sleep 1
done
if (( ${#connections[@]} != 1 )); then
    exit 1
fi

# Leave time for the independent observer to download the artifact and connect.
sleep 55
connectors=()
for process in /proc/[0-9]*; do
    executable=$(readlink "$process/exe") || continue
    case "$executable" in
        /tmp/live-ui-*/cloudflared|"$RUNNER_TEMP"/live-ui-*/cloudflared)
            parent=$(awk '/^PPid:/ {print $2}' "$process/status") || continue
            if grep -aqF '/session.py' "/proc/$parent/cmdline"; then
                connectors+=("${process##*/}")
            fi
            ;;
    esac
done
if (( ${#connectors[@]} != 1 )); then
    exit 1
fi
kill -TERM "${connectors[0]}"

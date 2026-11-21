#!/usr/bin/env bash
set -euo pipefail

test "$(uname -m)" = arm64
out="${RUNNER_TEMP:?}/mobile-lan-preflight"
mkdir -p "$out"
uname -m > "$out/architecture.txt"
xcodebuild -version | tee "$out/xcode.txt"
sysctl -n kern.hv_support || true
xcrun simctl list devices available -j > "$out/simulators.json"
device=$(python3 -c 'import json,sys
devices = json.load(open(sys.argv[1]))["devices"]
print(next(d["udid"] for key in sorted(devices,reverse=True) if ".iOS-" in key
           for d in devices[key] if d["name"].startswith("iPhone")))' "$out/simulators.json")
printf '%s\n' "$device" > "$out/device"
xcrun simctl bootstatus "$device" -b
sudo ifconfig feth80 create
trap 'sudo ifconfig feth80 destroy || true; sudo ifconfig feth81 destroy || true; xcrun simctl shutdown "$device" || true' EXIT
sudo ifconfig feth81 create
sudo ifconfig feth80 peer feth81
sudo ifconfig feth80 inet 192.168.137.2 netmask 255.255.255.0 up
sudo ifconfig feth81 up
ifconfig feth80 > "$out/feth.txt"
xcrun simctl spawn "$device" launchctl list > "$out/simulator-processes.txt"
cat "$out/feth.txt"
if [[ "${LAN_KEEP:-0}" == 1 ]]; then trap - EXIT; fi

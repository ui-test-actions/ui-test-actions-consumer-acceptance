#!/usr/bin/env bash
set -euo pipefail

sdk="${ANDROID_HOME:?}"
image='system-images;android-35;google_apis;x86_64'
out="${RUNNER_TEMP:?}/mobile-lan-preflight"
mkdir -p "$out"
apt_options=(-o Acquire::Retries=3 -o Acquire::http::Timeout=20 -o APT::Update::Error-Mode=any)
packages=(dnsmasq-base libpulse0 libxcb-cursor0)
if ! sudo apt-get "${apt_options[@]}" update || ! sudo apt-get "${apt_options[@]}" install -y "${packages[@]}"; then
  sudo apt-get "${apt_options[@]}" update
  sudo apt-get "${apt_options[@]}" install -y "${packages[@]}"
fi
sudo chmod a+rw /dev/kvm
"$sdk/cmdline-tools/latest/bin/sdkmanager" 'platform-tools' "$image"
export PATH="$sdk/platform-tools:$PATH"
printf '%s\n' "$sdk/platform-tools" >> "$GITHUB_PATH"
export ANDROID_USER_HOME="$HOME/.android"
export ANDROID_AVD_HOME="$RUNNER_TEMP/ui-lan-avds"
mkdir -p "$ANDROID_USER_HOME" "$ANDROID_AVD_HOME"
echo no | "$sdk/cmdline-tools/latest/bin/avdmanager" create avd --force --name ui-lan --package "$image" --path "$ANDROID_AVD_HOME/ui-lan.avd"
"$sdk/emulator/emulator" -list-avds | grep -Fx ui-lan
"$sdk/emulator/emulator" -version
sudo ip tuntap add dev uilan0 mode tap user "$(id -un)"
trap 'sudo ip link del uilan0 2>/dev/null || true' EXIT
sudo ip address add 192.168.137.1/24 dev uilan0
sudo ip link set uilan0 up
sudo dnsmasq --conf-file=/dev/null --port=0 --interface=uilan0 --bind-interfaces \
  --dhcp-range=192.168.137.10,192.168.137.10,255.255.255.0,5m --leasefile-ro \
  --pid-file="$out/dnsmasq.pid" --log-dhcp --log-facility="$out/dhcp.log"
sudo chmod a+r "$out/dhcp.log"
trap 'sudo kill "$(cat "$out/dnsmasq.pid")" 2>/dev/null || true; sudo ip link del uilan0 2>/dev/null || true' EXIT
adb start-server
"$sdk/emulator/emulator" -avd ui-lan -port 5554 -no-window -no-audio -no-snapshot -no-boot-anim \
  -gpu swiftshader_indirect -feature -WiFiPacketStream -wifi-tap uilan0 > "$out/emulator.log" 2>&1 &
emulator_pid=$!
timeout 300 bash -c 'until [[ "$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d "\r")" == 1 ]]; do kill -0 "$1" || exit 1; sleep 2; done' bash "$emulator_pid" ||
  { tail -100 "$out/emulator.log"; exit 1; }
# A freshly booted guest can report boot completion before the phone service exists.
if ! timeout 45 bash -c '
  until adb -s emulator-5554 shell svc wifi enable && adb -s emulator-5554 shell svc data disable; do
    sleep 2
  done
' > "$out/guest-services.txt" 2>&1; then
  cat "$out/guest-services.txt" >&2
  exit 1
fi
for _ in {1..20}; do
  adb -s emulator-5554 shell ip -4 address > "$out/guest-address.txt"
  if grep -Eq 'inet 192\.168\.137\.(1[0-9]|20)/24' "$out/guest-address.txt"; then break; fi
  sleep 2
done
adb -s emulator-5554 shell dumpsys connectivity > "$out/connectivity.txt"
cat "$out/guest-address.txt"
grep -Eq 'inet 192\.168\.137\.(1[0-9]|20)/24' "$out/guest-address.txt"
for _ in {1..15}; do
  if adb -s emulator-5554 shell ping -I wlan0 -c 1 -W 2 192.168.137.1 > "$out/local-ping.txt" 2>&1; then
    break
  fi
  sleep 2
done
cat "$out/local-ping.txt"
grep -Eq '1 (packets )?received' "$out/local-ping.txt"
adb -s emulator-5554 shell dumpsys connectivity > "$out/connectivity.txt"
if [[ "${LAN_KEEP:-0}" == 1 ]]; then
  trap - EXIT
else
  adb -s emulator-5554 emu kill
fi

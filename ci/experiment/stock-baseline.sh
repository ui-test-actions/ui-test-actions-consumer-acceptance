#!/usr/bin/env bash
# Stock Google Play emulator baseline for the integrity experiment.
# Usage: stock-baseline.sh boot|collect
set -euo pipefail
trap 'status=$?; echo "EXPERIMENT_FAILURE phase=${phase:-unknown} line=${LINENO} status=${status}" | tee -a evidence/stock/failure.txt 2>/dev/null || true' ERR

phase="${1:?usage: stock-baseline.sh boot|collect}"
sdk="${ANDROID_HOME:?ANDROID_HOME must point to the Android SDK}"
tools="$sdk/cmdline-tools/latest/bin"
image='system-images;android-35;google_apis_playstore;x86_64'
avd='integrity-stock'
serial='emulator-5554'
port='5554'
evidence='evidence/stock'
avd_home="${RUNNER_TEMP}/integrity-avds"
mkdir -p "$evidence" "$avd_home" "$HOME/.android"

export ANDROID_USER_HOME="$HOME/.android"
export ANDROID_AVD_HOME="$avd_home"
export PATH="$sdk/platform-tools:$sdk/emulator:$PATH"

collect() {
    local suffix="${1:-initial}"
    {
        echo "collect_phase=$suffix"
        echo "collected_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "serial=$serial"
        echo "system_image=$image"
        echo "avd_name=$avd"
        echo "emulator_flags=-no-window -no-audio -no-snapshot -no-boot-anim -gpu swiftshader_indirect -accel on -memory 4096 -cores 4 -wipe-data"
        echo "adb_version=$(adb version | head -1)"
        sed -n 's/^Pkg.Revision=/emulator_revision=/p' "$sdk/emulator/source.properties" 2>/dev/null || true
        sed -n 's/^Pkg.Revision=/image_revision=/p' "$sdk/$image/source.properties" 2>/dev/null || true
        for prop in sys.boot_completed ro.build.version.release ro.build.version.sdk \
            ro.product.cpu.abi ro.product.cpu.abilist ro.build.fingerprint ro.build.type \
            ro.build.tags ro.build.version.security_patch ro.build.version.incremental \
            ro.product.model ro.product.device ro.product.manufacturer ro.hardware \
            ro.kernel.qemu ro.boot.qemu ro.product.first_api_level ro.debuggable \
            ro.secure ro.boot.verifiedbootstate ro.boot.flash.locked; do
            printf '%s=%s\n' "$prop" "$(timeout 20 adb -s "$serial" shell getprop "$prop" 2>/dev/null | tr -d '\r')"
        done
        printf 'adb_shell_identity=%s\n' "$(timeout 20 adb -s "$serial" shell id 2>/dev/null | tr -d '\r')"
        printf 'adb_shell_uid=%s\n' "$(timeout 20 adb -s "$serial" shell id -u 2>/dev/null | tr -d '\r')"
        printf 'user_setup_complete=%s\n' "$(timeout 20 adb -s "$serial" shell settings get secure user_setup_complete 2>/dev/null | tr -d '\r')"
        printf 'device_provisioned=%s\n' "$(timeout 20 adb -s "$serial" shell settings get global device_provisioned 2>/dev/null | tr -d '\r')"
        printf 'play_store_version_name=%s\n' "$(timeout 20 adb -s "$serial" shell dumpsys package com.android.vending 2>/dev/null | grep -m1 'versionName=' | tr -d '\r' | sed 's/^ *//')"
        printf 'play_store_version_code=%s\n' "$(timeout 20 adb -s "$serial" shell dumpsys package com.android.vending 2>/dev/null | grep -m1 'versionCode=' | tr -d '\r' | sed 's/^ *//')"
        printf 'gms_version_name=%s\n' "$(timeout 20 adb -s "$serial" shell dumpsys package com.google.android.gms 2>/dev/null | grep -m1 'versionName=' | tr -d '\r' | sed 's/^ *//')"
        printf 'gms_version_code=%s\n' "$(timeout 20 adb -s "$serial" shell dumpsys package com.google.android.gms 2>/dev/null | grep -m1 'versionCode=' | tr -d '\r' | sed 's/^ *//')"
        echo '--- pm path ---'
        timeout 20 adb -s "$serial" shell pm path com.google.android.gms 2>/dev/null || true
        timeout 20 adb -s "$serial" shell pm path com.android.vending 2>/dev/null || true
        echo '--- launcher packages ---'
        timeout 20 adb -s "$serial" shell pm list packages 2>/dev/null | grep -Ei 'launcher|nexus' || true
        echo '--- display ---'
        timeout 20 adb -s "$serial" shell wm size 2>/dev/null || true
        timeout 20 adb -s "$serial" shell wm density 2>/dev/null || true
        echo '--- avd config ---'
        grep -E '^(hw\.(ramSize|cpu\.ncore|lcd\.(width|height|density))|disk\.dataPartition\.size|PlayStore\.enabled|tag\.id|image\.sysdir|abi\.type)' \
            "$avd_home/$avd.avd/config.ini" 2>/dev/null || true
    } | tee -a "$evidence/configuration.txt"
}

if [[ "$phase" == 'collect' ]]; then
    collect final || true
    timeout 30 adb -s "$serial" logcat -d -v threadtime > "$evidence/logcat.txt" 2>/dev/null || true
    timeout 20 adb -s "$serial" shell dumpsys package com.android.vending > "$evidence/play-store-dumpsys.txt" 2>/dev/null || true
    timeout 20 adb -s "$serial" shell dumpsys package com.google.android.gms > "$evidence/gms-dumpsys.txt" 2>/dev/null || true
    timeout 20 adb -s "$serial" shell pm list packages > "$evidence/packages.txt" 2>/dev/null || true
    timeout 20 adb -s "$serial" exec-out screencap -p > "$evidence/adb-post-session.png" 2>/dev/null || true
    timeout 10 adb -s "$serial" emu kill 2>/dev/null || true
    exit 0
fi

# --- boot phase ---
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends libpulse0
sudo chmod a+rw /dev/kvm

yes | "$tools/sdkmanager" --licenses >/dev/null 2>&1 || true
"$tools/sdkmanager" --install emulator "$image" 'platforms;android-35' 'build-tools;35.0.0' 'platform-tools' >/dev/null
"$tools/sdkmanager" --list_installed > "$evidence/sdk-versions.txt" 2>&1 || true
{
    echo "=== emulator source.properties ==="
    cat "$sdk/emulator/source.properties"
    echo "=== image source.properties ==="
    cat "$sdk/$image/source.properties"
    echo "=== emulator -version ==="
    "$sdk/emulator/emulator" -version 2>&1 || true
    echo "=== adb version ==="
    adb version 2>&1 || true
    echo "=== accel-check ==="
    "$sdk/emulator/emulator" -accel-check 2>&1 || true
    echo "=== kvm ==="
    ls -l /dev/kvm
} | tee -a "$evidence/sdk-versions.txt"

echo no | "$tools/avdmanager" create avd --force --name "$avd" --package "$image" \
    --path "$avd_home/$avd.avd" --device pixel_6 > "$evidence/avd-create.log" 2>&1 ||
    echo no | "$tools/avdmanager" create avd --force --name "$avd" --package "$image" \
        --path "$avd_home/$avd.avd" >> "$evidence/avd-create.log" 2>&1
config="$avd_home/$avd.avd/config.ini"
for key in hw.ramSize hw.cpu.ncore hw.lcd.width hw.lcd.height hw.lcd.density disk.dataPartition.size; do
    sed -i "/^${key}=/d" "$config"
done
{
    echo 'hw.ramSize=4096'
    echo 'hw.cpu.ncore=4'
    echo 'hw.lcd.width=1080'
    echo 'hw.lcd.height=1920'
    echo 'hw.lcd.density=420'
    echo 'disk.dataPartition.size=6G'
} >> "$config"
grep -E '^(hw\.|disk\.|PlayStore|tag\.|image\.|abi\.)' "$config" > "$evidence/avd-config.txt"

"$sdk/emulator/emulator" -list-avds

# Cold, clean boot of the stock Play image. -no-snapshot prevents reuse of any
# snapshot state, including one that might have been created accidentally.
"$sdk/emulator/emulator" -avd "$avd" -port "$port" -no-window -no-audio -no-snapshot \
    -no-boot-anim -gpu swiftshader_indirect -accel on -memory 4096 -cores 4 -wipe-data \
    > "$evidence/emulator.log" 2>&1 &
emulator_pid=$!
echo "$emulator_pid" > "$evidence/emulator.pid"

booted=false
for _ in $(seq 1 240); do
    if ! kill -0 "$emulator_pid" 2>/dev/null; then
        echo "Emulator exited before boot; tail of log:" >&2
        tail -200 "$evidence/emulator.log" >&2 || true
        exit 1
    fi
    if [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == '1' ]]; then
        booted=true
        break
    fi
    sleep 2
done
if [[ "$booted" != true ]]; then
    echo "Emulator did not report sys.boot_completed=1 within 480 seconds" >&2
    tail -200 "$evidence/emulator.log" >&2 || true
    exit 1
fi

adb -s "$serial" wait-for-device
adb -s "$serial" shell input keyevent KEYCODE_WAKEUP || true
adb -s "$serial" shell wm dismiss-keyguard || true
adb -s "$serial" shell input keyevent KEYCODE_HOME || true
for _ in $(seq 1 60); do
    if adb -s "$serial" shell dumpsys activity activities 2>/dev/null | grep -Eq 'topResumedActivity=.*(launcher|Launcher)'; then
        break
    fi
    sleep 2
done
adb -s "$serial" shell input keyevent KEYCODE_HOME || true
sleep 3

collect initial || true
adb -s "$serial" wait-for-device || true
timeout 30 adb -s "$serial" exec-out screencap -p > "$evidence/adb-home.png" || true
printf 'FIXTURE_APK=%s\n' "${RUNNER_TEMP}/integrity-fixture/fixture.apk" >> "$GITHUB_ENV"
printf 'STOCK_SERIAL=%s\n' "$serial" >> "$GITHUB_ENV"
echo "stock_boot=complete"

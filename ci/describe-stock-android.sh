#!/usr/bin/env bash
set -euo pipefail
device=(adb -s emulator-5554)
{
    printf 'system_image=%s\n' "$1"
    printf 'runner_arch=%s\n' "$(uname -m)"
    sed -n 's/^Pkg.Revision=/emulator_revision=/p' "$ANDROID_HOME/emulator/source.properties"
    sed -n 's/^Pkg.Revision=/image_revision=/p' "$ANDROID_HOME/system-images/android-35/google_apis_playstore/x86_64/source.properties"
    for prop in sys.boot_completed ro.build.version.release ro.build.version.sdk ro.product.cpu.abi ro.build.type ro.build.tags ro.build.version.security_patch; do
        printf '%s=%s\n' "$prop" "$("${device[@]}" shell getprop "$prop" | tr -d '\r')"
    done
    printf 'adb_shell_uid=%s\n' "$("${device[@]}" shell id -u | tr -d '\r')"
    "${device[@]}" shell wm size
    "${device[@]}" shell wm density
    "${device[@]}" shell pm list packages com.android.vending
    awk -F= '$1 ~ /^(hw\.cpu\.ncore|hw\.ramSize|hw\.lcd\.density|hw\.lcd\.width|hw\.lcd\.height|tag\.id|PlayStore\.enabled)$/ {print}' "$2"
    printf 'emulator_flags=-no-window -no-audio -no-snapshot -no-boot-anim -gpu swiftshader_indirect\n'
} | tee "$RUNNER_TEMP/stock-android-configuration.txt"

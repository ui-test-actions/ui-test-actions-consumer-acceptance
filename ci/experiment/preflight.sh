#!/usr/bin/env bash
# Runner and Android SDK preflight for the integrity/root experiment.
# Read-only with respect to the runner except for installing the emulator's
# documented runtime library (libpulse0) when it is missing.
set -euo pipefail

out="${1:-evidence/runner}"
mkdir -p "$out"

{
    echo "=== operating system ==="
    cat /etc/os-release
    uname -a
    lsb_release -a 2>/dev/null || true
    echo
    echo "=== architecture and CPUs ==="
    uname -m
    nproc
    lscpu | sed -n '1,30p'
    echo
    echo "=== memory ==="
    free -h
    echo
    echo "=== disk ==="
    df -h /
    df -h "$RUNNER_TEMP" 2>/dev/null || true
    echo
    echo "=== virtualization ==="
    ls -l /dev/kvm || true
    if [[ -r /dev/kvm && -w /dev/kvm ]]; then
        echo "kvm_read_write=yes"
    else
        echo "kvm_read_write=no"
    fi
    grep -E -c '(vmx|svm)' /proc/cpuinfo || true
} | tee "$out/configuration.txt"

{
    echo "ANDROID_HOME=${ANDROID_HOME:-}"
    echo "ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-}"
    echo "RUNNER_OS=${RUNNER_OS:-}"
    echo "ImageOS=${ImageOS:-}"
    echo "ImageVersion=${ImageVersion:-}"
    ls -la "${ANDROID_HOME:-/usr/local/lib/android/sdk}" 2>/dev/null || true
    echo
    echo "=== sdkmanager ==="
    "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --version 2>&1 || true
    echo
    echo "=== adb ==="
    "${ANDROID_HOME}/platform-tools/adb" version 2>&1 || adb version 2>&1 || true
    echo
    echo "=== emulator source.properties ==="
    cat "${ANDROID_HOME}/emulator/source.properties" 2>/dev/null || true
    echo
    echo "=== installed SDK packages ==="
    "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --list_installed 2>&1 || true
    echo
    echo "=== available android-35 and android-34 system images ==="
    "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --list 2>&1 |
        grep -E 'system-images;android-(35|34);(google_apis|google_apis_playstore|aosp_atd);x86_64' || true
} | tee "$out/sdk-versions.txt"

{
    echo "=== emulator -version (before libpulse check) ==="
    timeout 30 "${ANDROID_HOME}/emulator/emulator" -version 2>&1 || echo "emulator_version_exit=$?"
    echo
    echo "=== missing shared libraries ==="
    ldd "${ANDROID_HOME}/emulator/emulator" 2>&1 | grep -E 'not found' || echo "none"
    echo
    echo "=== libpulse presence ==="
    ldconfig -p 2>/dev/null | grep -E 'libpulse\.so' || echo "libpulse_absent"
} | tee "$out/acceleration.txt"

if ! ldconfig -p 2>/dev/null | grep -q 'libpulse\.so\.0'; then
    echo "libpulse0 is missing; installing the documented emulator runtime dependency." | tee -a "$out/acceleration.txt"
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends libpulse0
    {
        echo "=== libpulse presence after install ==="
        ldconfig -p | grep -E 'libpulse\.so' || echo "libpulse_still_absent"
        echo "=== emulator -version (after libpulse install) ==="
        timeout 30 "${ANDROID_HOME}/emulator/emulator" -version 2>&1 || echo "emulator_version_exit=$?"
    } | tee -a "$out/acceleration.txt"
fi

{
    echo "=== emulator accel-check ==="
    timeout 30 "${ANDROID_HOME}/emulator/emulator" -accel-check 2>&1 || echo "accel_check_exit=$?"
} | tee "$out/acceleration.txt"

# The emulator creates its AVD home lazily. Record the resolved locations so
# the boot logs can be compared across jobs.
{
    echo "ANDROID_USER_HOME=${ANDROID_USER_HOME:-$HOME/.android}"
    echo "ANDROID_AVD_HOME=${ANDROID_AVD_HOME:-unset}"
    ls -la "${ANDROID_USER_HOME:-$HOME/.android}" 2>/dev/null || true
} | tee "$out/sdk-versions.txt" -a

echo "preflight_written=$out"

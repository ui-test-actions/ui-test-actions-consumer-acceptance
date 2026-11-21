#!/usr/bin/env bash
# Disposable AOSP rootAVD + Magisk validation for the integrity experiment.
# Usage: root-magisk.sh setup|patch|verify|module|reboot|collect
set -euo pipefail
trap 'status=$?; echo "EXPERIMENT_FAILURE phase=${phase:-unknown} line=${LINENO} status=${status}" | tee -a evidence/root/failure.txt 2>/dev/null || true' ERR

phase="${1:?usage: root-magisk.sh setup|patch|verify|module|reboot|collect}"
sdk="${ANDROID_HOME:?ANDROID_HOME must point to the Android SDK}"
tools="$sdk/cmdline-tools/latest/bin"
image='system-images;android-35;google_apis;x86_64'
image_dir="$sdk/${image//;//}"
avd='integrity-root'
serial='emulator-5554'
port='5554'
evidence='evidence/root'
avd_home="${RUNNER_TEMP}/integrity-root-avds"
rootavd_dir="${GITHUB_WORKSPACE}/rootAVD"
rootavd_commit='613caa44371f85e1a461bc030e07ddc2d71afe32'
magisk_version='v31.1'
magisk_sha256='89cefac0a318afa39fb3880c45c87b036c05bc1ebf02a7a715b7f8d7c26ac6e7'
ramdisk="$image_dir/ramdisk.img"
mkdir -p "$evidence" "$avd_home" "$HOME/.android"
export ANDROID_USER_HOME="$HOME/.android"
export ANDROID_AVD_HOME="$avd_home"
export PATH="$sdk/platform-tools:$sdk/emulator:$PATH"

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$evidence/run.log"; }

wait_boot() {
    local pid="$1" limit="${2:-300}"
    for _ in $(seq 1 "$limit"); do
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            log "emulator process exited before boot"
            tail -120 "$evidence/emulator.log" >> "$evidence/run.log" || true
            return 1
        fi
        if [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == '1' ]]; then
            adb -s "$serial" wait-for-device
            adb -s "$serial" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
            adb -s "$serial" shell wm dismiss-keyguard >/dev/null 2>&1 || true
            adb -s "$serial" shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
            sleep 8
            return 0
        fi
        sleep 2
    done
    log "emulator did not report sys.boot_completed=1 within $((limit * 2)) seconds"
    tail -120 "$evidence/emulator.log" >> "$evidence/run.log" || true
    return 1
}

launch_emulator() {
    local wipe="${1:-no}" tag="${2:-boot}"
    if adb -s "$serial" get-state >/dev/null 2>&1; then
        adb -s "$serial" emu kill >/dev/null 2>&1 || true
    fi
    for _ in $(seq 1 30); do
        if ! pgrep -f "emulator.*-avd $avd" >/dev/null 2>&1; then break; fi
        sleep 1
    done
    local args=(-avd "$avd" -port "$port" -no-window -no-audio -no-snapshot
        -no-boot-anim -gpu swiftshader_indirect -accel on -memory 4096 -cores 4)
    if [[ "$wipe" == 'yes' ]]; then args+=(-wipe-data); fi
    "$sdk/emulator/emulator" "${args[@]}" > "$evidence/emulator-$tag.log" 2>&1 &
    local pid=$!
    echo "$pid" > "$evidence/emulator-$tag.pid"
    log "launched emulator tag=$tag wipe=$wipe pid=$pid"
    wait_boot "$pid" 300
}

collect_props() {
    local suffix="$1"
    {
        echo "collect_phase=$suffix"
        echo "collected_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "system_image=$image"
        echo "avd_name=$avd"
        echo "rootavd_commit=$rootavd_commit"
        echo "magisk_requested=$magisk_version"
        echo "magisk_apk_sha256=$magisk_sha256"
        sed -n 's/^Pkg.Revision=/emulator_revision=/p' "$sdk/emulator/source.properties" 2>/dev/null || true
        sed -n 's/^Pkg.Revision=/image_revision=/p' "$image_dir/source.properties" 2>/dev/null || true
        for prop in sys.boot_completed ro.build.version.release ro.build.version.sdk \
            ro.product.cpu.abi ro.product.cpu.abilist ro.build.fingerprint ro.build.type \
            ro.build.tags ro.build.version.security_patch ro.product.model ro.product.device \
            ro.product.manufacturer ro.hardware ro.kernel.qemu ro.boot.qemu ro.debuggable \
            ro.secure ro.boot.verifiedbootstate ro.boot.flash.locked ro.crypto.state; do
            printf '%s=%s\n' "$prop" "$(timeout 20 adb -s "$serial" shell getprop "$prop" 2>/dev/null | tr -d '\r')"
        done
        printf 'adb_shell_identity=%s\n' "$(timeout 20 adb -s "$serial" shell id 2>/dev/null | tr -d '\r')"
        printf 'adb_shell_uid=%s\n' "$(timeout 20 adb -s "$serial" shell id -u 2>/dev/null | tr -d '\r')"
        echo '--- display ---'
        timeout 20 adb -s "$serial" shell wm size 2>/dev/null || true
        timeout 20 adb -s "$serial" shell wm density 2>/dev/null || true
        echo '--- magisk packages ---'
        timeout 20 adb -s "$serial" shell pm list packages 2>/dev/null | grep -i magisk || true
        echo '--- network interfaces ---'
        timeout 20 adb -s "$serial" shell ip addr 2>/dev/null || true
        echo '--- avd config ---'
        grep -E '^(hw\.(ramSize|cpu\.ncore|lcd\.(width|height|density))|disk\.dataPartition\.size|PlayStore\.enabled|tag\.id|image\.sysdir|abi\.type)' \
            "$avd_home/$avd.avd/config.ini" 2>/dev/null || true
    } | tee -a "$evidence/configuration.txt"
}

magisk_binary() {
    for candidate in magisk /debug_ramdisk/magisk /system/bin/magisk /sbin/magisk; do
        if adb -s "$serial" shell "test -x $candidate" >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

verify_root() {
    local output="$1"
    {
        echo "verified_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "adb_shell_id=$(adb -s "$serial" shell id 2>/dev/null | tr -d '\r')"
        echo "adb_shell_uid=$(adb -s "$serial" shell id -u 2>/dev/null | tr -d '\r')"
        local magisk
        magisk="$(magisk_binary || true)"
        echo "magisk_binary=${magisk:-not_found}"
        if [[ -n "$magisk" ]]; then
            echo "magisk_version=$(adb -s "$serial" shell "$magisk -v" 2>/dev/null | tr -d '\r')"
            echo "magisk_path=$(adb -s "$serial" shell "$magisk --path" 2>/dev/null | tr -d '\r')"
        fi
        echo '--- su -c id (timeout 20s) ---'
        local su_output su_status
        set +e
        su_output="$(timeout 20 adb -s "$serial" shell 'su -c id' 2>&1 | tr -d '\r')"
        su_status=$?
        set -e
        echo "$su_output"
        echo "su_exit=$su_status"
        if grep -q 'uid=0' <<<"$su_output"; then
            echo "magisk_root=verified"
        else
            echo "magisk_root=pending"
        fi
        echo '--- /data/adb/magisk ---'
        adb -s "$serial" shell 'ls -la /data/adb/magisk 2>/dev/null | head -20' 2>/dev/null || true
        echo '--- /data/adb/modules ---'
        adb -s "$serial" shell 'ls -la /data/adb/modules 2>/dev/null' 2>/dev/null || true
    } | tee "$output"
}

if [[ "$phase" == 'setup' ]]; then
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
        cat "$image_dir/source.properties"
        echo "=== emulator -version ==="
        "$sdk/emulator/emulator" -version 2>&1 || true
        echo "=== adb version ==="
        adb version 2>&1 || true
        echo "=== accel-check ==="
        "$sdk/emulator/emulator" -accel-check 2>&1 || true
        echo "=== kvm ==="
        ls -l /dev/kvm
    } | tee -a "$evidence/sdk-versions.txt"

    rm -rf "$rootavd_dir"
    git init -q "$rootavd_dir"
    git -C "$rootavd_dir" remote add origin https://gitlab.com/newbit/rootAVD.git
    git -C "$rootavd_dir" fetch -q --depth 1 origin "$rootavd_commit"
    git -C "$rootavd_dir" checkout -q FETCH_HEAD
    actual_commit="$(git -C "$rootavd_dir" rev-parse HEAD)"
    {
        echo "repository=https://gitlab.com/newbit/rootAVD"
        echo "requested_commit=$rootavd_commit"
        echo "actual_commit=$actual_commit"
        echo "commit_date=$(git -C "$rootavd_dir" show -s --format=%cI HEAD)"
    } | tee "$evidence/rootavd-version.txt"

    mkdir -p "$RUNNER_TEMP/magisk-stage"
    curl -fsSL -o "$RUNNER_TEMP/magisk-stage/Magisk-$magisk_version.apk" \
        "https://github.com/topjohnwu/Magisk/releases/download/$magisk_version/Magisk-$magisk_version.apk"
    actual_sha="$(sha256sum "$RUNNER_TEMP/magisk-stage/Magisk-$magisk_version.apk" | awk '{print $1}')"
    {
        echo "repository=https://github.com/topjohnwu/Magisk"
        echo "release=$magisk_version"
        echo "asset=Magisk-$magisk_version.apk"
        echo "expected_sha256=$magisk_sha256"
        echo "actual_sha256=$actual_sha"
        echo "size_bytes=$(stat -c%s "$RUNNER_TEMP/magisk-stage/Magisk-$magisk_version.apk")"
    } | tee "$evidence/magisk-version.txt"
    if [[ "$actual_sha" != "$magisk_sha256" ]]; then
        echo "Magisk SHA-256 mismatch; refusing to stage an unverified root manager." >&2
        exit 1
    fi
    cp "$RUNNER_TEMP/magisk-stage/Magisk-$magisk_version.apk" "$rootavd_dir/Magisk.zip"

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

    launch_emulator yes setup
    collect_props setup

    {
        echo "ramdisk_path=$ramdisk"
        echo "ramdisk_sha256_before=$(sha256sum "$ramdisk" | awk '{print $1}')"
        echo "ramdisk_size_before=$(stat -c%s "$ramdisk")"
        echo "ramdisk_file_type=$(file -b "$ramdisk")"
    } | tee "$evidence/ramdisk-hashes.txt"
    cp "$ramdisk" "$RUNNER_TEMP/ramdisk.original"

    (cd "$rootavd_dir" && bash ./rootAVD.sh ListAllAVDs) > "$evidence/rootavd-list-avds.txt" 2>&1 || true
    adb -s "$serial" exec-out screencap -p > "$evidence/adb-baseline.png" || true
    log "setup complete"
    exit 0
fi

if [[ "$phase" == 'patch' ]]; then
    rm -f "$evidence/patch.log"
    log "starting patch phase"

    # Isolate the guest from outbound IP traffic. ADB itself is a host-side
    # transport and is not affected. adb root is available because the AOSP
    # google_apis image is a userdebug build; unroot restores the ordinary shell.
    adb -s "$serial" root > "$evidence/network-isolation.txt" 2>&1 || true
    adb -s "$serial" wait-for-device
    {
        echo "root_adb_uid=$(adb -s "$serial" shell id -u 2>/dev/null | tr -d '\r')"
        echo '--- ip addr before isolation ---'
        adb -s "$serial" shell ip addr 2>/dev/null || true
    } >> "$evidence/network-isolation.txt"
    adb -s "$serial" shell 'ip link set wlan0 down 2>/dev/null; ip link set eth0 down 2>/dev/null; svc wifi disable 2>/dev/null; svc data disable 2>/dev/null; settings put global airplane_mode_on 1 2>/dev/null; am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true 2>/dev/null; iptables -I OUTPUT 1 -o lo -j ACCEPT 2>/dev/null; iptables -I OUTPUT 2 -j REJECT 2>/dev/null; true' >> "$evidence/network-isolation.txt" 2>&1 || true
    adb -s "$serial" unroot >> "$evidence/network-isolation.txt" 2>&1 || true
    adb -s "$serial" wait-for-device
    sleep 3
    {
        echo "post_unroot_shell_uid=$(adb -s "$serial" shell id -u 2>/dev/null | tr -d '\r')"
        echo '--- ip addr after isolation ---'
        adb -s "$serial" shell ip addr 2>/dev/null || true
        echo '--- ping 8.8.8.8 ---'
        if adb -s "$serial" shell 'ping -c 1 -W 2 8.8.8.8' >/dev/null 2>&1; then
            echo 'network_isolated=no'
        else
            echo 'network_isolated=yes'
        fi
        echo '--- http probe ---'
        if adb -s "$serial" shell 'toybox wget -T 3 -O /dev/null http://example.com' >/dev/null 2>&1; then
            echo 'http_isolated=no'
        else
            echo 'http_isolated=yes'
        fi
    } | tee -a "$evidence/network-isolation.txt"

    guest=/data/local/tmp/rootavd
    adb -s "$serial" shell "rm -rf $guest && mkdir -p $guest"
    adb -s "$serial" push "$rootavd_dir/rootAVD.sh" "$guest/rootAVD.sh" >/dev/null
    adb -s "$serial" push "$rootavd_dir/Magisk.zip" "$guest/Magisk.zip" >/dev/null
    adb -s "$serial" push "$ramdisk" "$guest/ramdisk.img" >/dev/null

    set +e
    adb -s "$serial" shell "cd $guest && MAGISKVERCHOOSEN=true sh rootAVD.sh ramdisk.img" 2>&1 | tee "$evidence/patch.log"
    patch_status=${PIPESTATUS[0]}
    set -e
    echo "rootavd_patch_exit=$patch_status" | tee -a "$evidence/patch.log"
    if [[ "$patch_status" -ne 0 ]]; then
        log "rootAVD patch command failed with exit $patch_status"
    fi

    adb -s "$serial" pull "$guest/ramdiskpatched4AVD.img" "$RUNNER_TEMP/ramdisk.patched" >> "$evidence/patch.log" 2>&1 || true
    adb -s "$serial" pull "$guest/Magisk.apk" "$RUNNER_TEMP/Magisk-pulled.apk" >> "$evidence/patch.log" 2>&1 || true
    for extra in ramdisk.cpio config magisk_menu.txt magisk_versions.txt magisk_dl_links.txt; do
        adb -s "$serial" pull "$guest/$extra" "$evidence/guest-$extra" >> "$evidence/patch.log" 2>&1 || true
    done

    if [[ ! -s "$RUNNER_TEMP/ramdisk.patched" ]]; then
        log "no patched ramdisk was produced; stopping before boot"
        exit 1
    fi

    {
        echo "ramdisk_sha256_original=$(sha256sum "$RUNNER_TEMP/ramdisk.original" | awk '{print $1}')"
        echo "ramdisk_sha256_patched=$(sha256sum "$RUNNER_TEMP/ramdisk.patched" | awk '{print $1}')"
        echo "ramdisk_size_original=$(stat -c%s "$RUNNER_TEMP/ramdisk.original")"
        echo "ramdisk_size_patched=$(stat -c%s "$RUNNER_TEMP/ramdisk.patched")"
        echo "ramdisk_patched_file_type=$(file -b "$RUNNER_TEMP/ramdisk.patched")"
        echo "magisk_apk_sha256=$(sha256sum "$RUNNER_TEMP/Magisk-pulled.apk" 2>/dev/null | awk '{print $1}')"
        echo "magisk_apk_size=$(stat -c%s "$RUNNER_TEMP/Magisk-pulled.apk" 2>/dev/null || echo missing)"
    } | tee -a "$evidence/ramdisk-hashes.txt"

    # Prove the original image can be restored, then leave the patched image in
    # place for the cold-boot validation.
    cp "$RUNNER_TEMP/ramdisk.original" "$ramdisk"
    restored_sha="$(sha256sum "$ramdisk" | awk '{print $1}')"
    echo "ramdisk_sha256_after_restore=$restored_sha" | tee -a "$evidence/ramdisk-hashes.txt"
    if [[ "$restored_sha" != "$(grep -m1 '^ramdisk_sha256_before=' "$evidence/ramdisk-hashes.txt" | cut -d= -f2)" ]]; then
        log "restore verification failed"
        exit 1
    fi
    cp "$RUNNER_TEMP/ramdisk.patched" "$ramdisk"
    echo "ramdisk_sha256_reinstalled=$(sha256sum "$ramdisk" | awk '{print $1}')" | tee -a "$evidence/ramdisk-hashes.txt"

    if [[ -s "$RUNNER_TEMP/Magisk-pulled.apk" ]]; then
        adb -s "$serial" install -r "$RUNNER_TEMP/Magisk-pulled.apk" > "$evidence/magisk-install.txt" 2>&1 || true
        cat "$evidence/magisk-install.txt"
    fi

    adb -s "$serial" shell "rm -rf $guest" >/dev/null 2>&1 || true
    adb -s "$serial" emu kill >/dev/null 2>&1 || true
    log "patch phase complete"
    exit 0
fi

if [[ "$phase" == 'verify' ]]; then
    launch_emulator no verify1
    collect_props after-patch-boot
    verify_root "$evidence/root-verification.txt"
    adb -s "$serial" logcat -d -v threadtime 2>/dev/null | grep -iE 'magisk|root|su' | tail -200 > "$evidence/magisk-logcat.txt" || true
    adb -s "$serial" exec-out screencap -p > "$evidence/adb-magisk-boot.png" || true
    log "verify phase complete"
    exit 0
fi

if [[ "$phase" == 'grant' ]]; then
    # Only used if the interactive Magisk prompt could not be granted during
    # the UI session. This writes the normal Magisk allow policy for the shell
    # UID; su still runs through Magisk, not through adbd.
    current="$(timeout 20 adb -s "$serial" shell 'su -c id' 2>&1 | tr -d '\r' || true)"
    if grep -q 'uid=0' <<<"$current"; then
        echo "grant_phase=already_verified" | tee "$evidence/grant.txt"
        echo "$current" | tee -a "$evidence/grant.txt"
        exit 0
    fi
    adb -s "$serial" root > "$evidence/grant.txt" 2>&1 || true
    adb -s "$serial" wait-for-device
    magisk="$(magisk_binary || echo magisk)"
    set +e
    timeout 30 adb -s "$serial" shell "$magisk --sqlite \"INSERT OR REPLACE INTO policies (uid,policy,until,logging,notification) VALUES (2000,1,0,1,1);\"" >> "$evidence/grant.txt" 2>&1
    sqlite_status=$?
    set -e
    echo "grant_sqlite_exit=$sqlite_status" | tee -a "$evidence/grant.txt"
    adb -s "$serial" unroot >> "$evidence/grant.txt" 2>&1 || true
    adb -s "$serial" wait-for-device
    sleep 2
    set +e
    timeout 20 adb -s "$serial" shell 'su -c id' 2>&1 | tee -a "$evidence/grant.txt"
    set -e
    log "grant phase complete"
    exit 0
fi

if [[ "$phase" == 'module' ]]; then
    module_dir="$RUNNER_TEMP/inert-module"
    rm -rf "$module_dir"
    mkdir -p "$module_dir/META-INF/com/google/android"
    cat > "$module_dir/module.prop" <<'EOF'
id=integrity-inert-test
name=Inert boot marker
version=1.0
versionCode=1
author=integrity-experiment
description=Writes a timestamp to /data/local/tmp at post-fs-data; changes no security state.
EOF
    cat > "$module_dir/post-fs-data.sh" <<'EOF'
#!/system/bin/sh
mkdir -p /data/local/tmp
{
  date -u +%Y-%m-%dT%H:%M:%SZ
  echo "inert_module_uid=$(id -u)"
} > /data/adb/inert-module-ran
cp /data/adb/inert-module-ran /data/local/tmp/inert-module-ran 2>/dev/null
EOF
    chmod +x "$module_dir/post-fs-data.sh"
    (cd "$module_dir" && python3 -m zipfile -c "$RUNNER_TEMP/inert-module.zip" module.prop post-fs-data.sh)
    adb -s "$serial" push "$RUNNER_TEMP/inert-module.zip" /data/local/tmp/inert-module.zip >/dev/null
    magisk="$(magisk_binary || echo magisk)"
    set +e
    timeout 60 adb -s "$serial" shell "su -c '$magisk --install-module /data/local/tmp/inert-module.zip'" > "$evidence/module-install.txt" 2>&1
    status=$?
    set -e
    echo "module_install_exit=$status" | tee -a "$evidence/module-install.txt"
    adb -s "$serial" shell 'ls -la /data/adb/modules 2>/dev/null; cat /data/adb/modules/integrity-inert-test/module.prop 2>/dev/null' > "$evidence/module-installed.txt" 2>&1 || true
    cat "$evidence/module-installed.txt"
    log "module phase complete"
    exit 0
fi

if [[ "$phase" == 'reboot' ]]; then
    launch_emulator no verify2
    collect_props after-second-cold-boot
    verify_root "$evidence/reboot-verification.txt"
    {
        echo "inert_module_marker_path=/data/adb/inert-module-ran"
        if adb -s "$serial" shell 'test -s /data/adb/inert-module-ran' >/dev/null 2>&1; then
            echo "inert_module_marker=present"
            adb -s "$serial" shell 'cat /data/adb/inert-module-ran' 2>/dev/null | tr -d '\r'
        elif adb -s "$serial" shell 'test -s /data/local/tmp/inert-module-ran' >/dev/null 2>&1; then
            echo "inert_module_marker=present"
            adb -s "$serial" shell 'cat /data/local/tmp/inert-module-ran' 2>/dev/null | tr -d '\r'
        else
            echo "inert_module_marker=absent"
        fi
        echo '--- modules list ---'
        adb -s "$serial" shell 'ls /data/adb/modules' 2>/dev/null || true
    } | tee -a "$evidence/reboot-verification.txt"
    adb -s "$serial" logcat -d -b crash -v threadtime > "$evidence/crash-log.txt" 2>/dev/null || true
    adb -s "$serial" logcat -d -v threadtime 2>/dev/null | grep -iE 'magisk|inert|module' | tail -300 > "$evidence/magisk-logcat.txt" || true
    adb -s "$serial" exec-out screencap -p > "$evidence/adb-after-reboot.png" || true
    log "reboot phase complete"
    exit 0
fi

if [[ "$phase" == 'collect' ]]; then
    {
        echo "collected_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "rootavd_commit=$(git -C "$rootavd_dir" rev-parse HEAD 2>/dev/null || echo missing)"
        echo "magisk_apk_sha256=$(sha256sum "$rootavd_dir/Magisk.zip" 2>/dev/null | awk '{print $1}' || echo missing)"
    } >> "$evidence/rootavd-version.txt"
    timeout 30 adb -s "$serial" logcat -d -b crash -v threadtime > "$evidence/crash-log.txt" 2>/dev/null || true
    timeout 20 adb -s "$serial" exec-out screencap -p > "$evidence/adb-final.png" 2>/dev/null || true
    timeout 10 adb -s "$serial" emu kill >/dev/null 2>&1 || true
    log "collect complete"
    exit 0
fi

echo "unknown phase: $phase" >&2
exit 2

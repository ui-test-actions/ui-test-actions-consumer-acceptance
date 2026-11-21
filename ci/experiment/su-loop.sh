#!/usr/bin/env bash
# Bounded, harmless su attempts so an interactive Magisk grant can complete
# while the UI session is open. Stops as soon as a uid=0 response is observed.
# The AOSP google_apis image also ships toybox /system/xbin/su, so probe the
# explicit Magisk-capable paths instead of relying on PATH.
set -u
evidence="${1:?provide the evidence directory}"
serial='emulator-5554'
mkdir -p "$evidence"
for attempt in $(seq 1 120); do
    for candidate in /system/bin/su /debug_ramdisk/su; do
        output="$(timeout 4 adb -s "$serial" shell "$candidate -c id" 2>&1 | tr -d '\r' || true)"
        printf '%s attempt=%s candidate=%s output=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$attempt" "$candidate" "$output" >> "$evidence/su-attempts.txt"
        if grep -q 'uid=0' <<<"$output"; then
            printf '%s\n' "$candidate" > "$evidence/su-command.txt"
            printf '%s attempt=%s candidate=%s result=success\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$attempt" "$candidate" >> "$evidence/su-attempts.txt"
            exit 0
        fi
    done
    sleep 3
done
printf '%s result=no_uid0_within_budget\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$evidence/su-attempts.txt"
exit 1

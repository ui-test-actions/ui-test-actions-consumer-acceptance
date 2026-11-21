#!/usr/bin/env bash
# Bounded, harmless su attempts so an interactive Magisk grant can complete
# while the UI session is open. Stops as soon as a uid=0 response is observed.
set -u
evidence="${1:?provide the evidence directory}"
serial='emulator-5554'
mkdir -p "$evidence"
for attempt in $(seq 1 120); do
    output="$(timeout 4 adb -s "$serial" shell 'su -c id' 2>&1 | tr -d '\r' || true)"
    printf '%s attempt=%s output=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$attempt" "$output" >> "$evidence/su-attempts.txt"
    if grep -q 'uid=0' <<<"$output"; then
        printf '%s attempt=%s result=success\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$attempt" >> "$evidence/su-attempts.txt"
        exit 0
    fi
    sleep 3
done
printf '%s result=no_uid0_within_budget\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$evidence/su-attempts.txt"
exit 1

#!/usr/bin/env bash
set -euo pipefail
umask 077
work="$RUNNER_TEMP/transport-proof"

fetch() {
    local name="$1" directory="$2"
    local selector=--name
    if [[ "$name" == *'*'* ]]; then selector=--pattern; fi
    for ((attempt=0; attempt<50; attempt++)); do
        if gh run download "$GITHUB_RUN_ID" -R "$GITHUB_REPOSITORY" "$selector" "$name" -D "$directory" 2>/dev/null; then
            return
        fi
        sleep 4
    done
    printf 'Timed out waiting for the workflow artifact %s\n' "$name" >&2
    return 1
}

step="$1" role="$2"
case "$step" in
    identity)
        mkdir -p "$work/identity" "$work/relay"
        wg genkey > "$work/identity.key"
        wg pubkey < "$work/identity.key" > "$work/identity/public-key"
        if [[ "$role" == peer ]]; then
            openssl rand -hex 32 > "$work/token"
            tr -d '\n' < "$work/token" | sha256sum | cut -c 1-64 > "$work/identity/token-digest"
        fi
        ;;
    link)
        if [[ "$role" == host ]]; then other=peer; address=1; remote=2; listen=51871;
        else other=host; address=2; remote=1; listen=51872; fi
        fetch "wg-identity-$other-$GITHUB_RUN_ATTEMPT" "$work/remote"
        remote_key="$(cat "$work/remote/public-key")"
        [[ "$remote_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]
        sudo ip link add ui-wg type wireguard
        sudo wg set ui-wg listen-port "$listen" private-key "$work/identity.key" peer "$remote_key" allowed-ips "10.204.0.$remote/32"
        rm -f "$work/identity.key"
        sudo ip addr add "10.204.0.$address/30" dev ui-wg
        sudo ip link set ui-wg up
        if [[ "$role" == host ]]; then
            digest="$(cat "$work/remote/token-digest")"
            [[ "$digest" =~ ^[0-9a-f]{64}$ ]]
            printf 'digest=%s\n' "$digest" >> "$GITHUB_OUTPUT"
            python verification/transports/wireguard-relay.py host "$work/relay" > "$work/relay.log" 2>&1 &
        else
            fetch "wg-relay-$GITHUB_RUN_ATTEMPT" "$work/relay"
            python verification/transports/wireguard-relay.py peer "$work/relay" > "$work/relay.log" 2>&1 &
            sudo wg set ui-wg peer "$remote_key" endpoint 127.0.0.1:51873 persistent-keepalive 3
        fi
        printf '%s\n' "$!" > "$work/relay.pid"
        if [[ "$role" == host ]]; then
            for ((second=0; second<180; second++)); do
                [[ -s "$work/relay/origin" ]] && exit 0
                kill -0 "$(cat "$work/relay.pid")" || break
                sleep 1
            done
            cat "$work/relay.log" >&2
            exit 1
        fi
        ;;
    observe)
        fetch "ui-session-host-$GITHUB_RUN_ATTEMPT-*" "$work/connection"
        sudo ping -n -c 2 -w 15 10.204.0.1
        sudo --preserve-env=RUNNER_TEMP "$(command -v python)" verification/transports/check.py cross "$work" \
            --connection "$(find "$work/connection" -name connection.json -print -quit)"
        ;;
    cleanup)
        if [[ -f "$work/relay.pid" ]]; then kill "$(cat "$work/relay.pid")" 2>/dev/null || true; fi
        sudo ip link del ui-wg 2>/dev/null || true
        rm -f "$work/token" "$work/identity.key"
        ;;
esac

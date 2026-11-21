#!/usr/bin/env bash
# An isolated WireGuard peer with its own network stack on a hosted Linux runner.
set -euo pipefail
if [[ "$1" == 'down' ]]; then
    sudo ip netns del ui-peer 2>/dev/null || true
    sudo ip link del ui-wg 2>/dev/null || true
    sudo ip link del ui-underlay 2>/dev/null || true
    exit 0
fi
umask 077
work="$(mktemp -d "${RUNNER_TEMP}/wireguard-proof-XXXXXX")"
trap 'rm -f "$work/server" "$work/client"; rmdir "$work"' EXIT
wg genkey > "$work/server"
wg genkey > "$work/client"
server="$(wg pubkey < "$work/server")"
client="$(wg pubkey < "$work/client")"
sudo ip netns add ui-peer
sudo ip link add ui-underlay type veth peer name ui-peer-link
sudo ip link set ui-peer-link netns ui-peer
sudo ip addr add 192.0.2.1/30 dev ui-underlay
sudo ip link set ui-underlay up
sudo ip -n ui-peer link set lo up
sudo ip -n ui-peer addr add 192.0.2.2/30 dev ui-peer-link
sudo ip -n ui-peer link set ui-peer-link up
sudo ip link add ui-wg type wireguard
sudo ip -n ui-peer link add ui-wg type wireguard
sudo wg set ui-wg listen-port 51871 private-key "$work/server" peer "$client" allowed-ips 10.204.0.2/32
sudo ip netns exec ui-peer wg set ui-wg listen-port 51872 private-key "$work/client" peer "$server" allowed-ips 10.204.0.1/32 endpoint 192.0.2.1:51871
sudo ip addr add 10.204.0.1/30 dev ui-wg
sudo ip -n ui-peer addr add 10.204.0.2/30 dev ui-wg
sudo ip link set ui-wg up
sudo ip -n ui-peer link set ui-wg up
sudo ip netns exec ui-peer ping -n -c 1 -w 5 10.204.0.1 >/dev/null

"""Prove transport authentication, UI change and lifecycle through the regular client."""

import argparse
from base64 import b64decode
from hashlib import sha256
import json
from pathlib import Path
import socket
import subprocess
import sys
import time
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from agent import Client, ClientError
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from probe_fixture import AFTER_COLOR, BEFORE_COLOR, TEST_TEXT, require_color, screenshot


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def connection(directory, runner_temp):
    stop = time.monotonic() + 420
    while time.monotonic() < stop:
        for candidate in runner_temp.glob("ui-session-*/connection.json"):
            if (directory / "controls.json").exists():
                return read(candidate), read(directory / "controls.json")
        time.sleep(.3)
    raise RuntimeError("The consumer action did not publish a connection file within seven minutes.")


def denied(client, status):
    try:
        client.fetch("/v1/session", retries=0)
    except ClientError as error:
        if error.status == status:
            return error.status
        raise
    raise RuntimeError("An invalid request was accepted.")


def observe(config, token_file, controls, output, access_file=None):
    client = Client(config, token_file, access_file)
    session = client.identify()
    for bad_token in ("", "0" * 64):
        unauthorized = Client(config, token_file, access_file)
        if bad_token:
            unauthorized.headers["Authorization"] = "Bearer " + bad_token
        else:
            unauthorized.headers.pop("Authorization")
        denied(unauthorized, 401)
    if config["transport"] == "local":
        wrong_host = Client(config, token_file)
        wrong_host.headers["Host"] = "untrusted.invalid"
        denied(wrong_host, 421)
    if config["transport"] == "private":
        # The server certificate is not in the system trust store.
        unpinned = Client({"url": config["url"]}, token_file)
        try:
            unpinned.fetch("/v1/session", retries=0)
        except ClientError as error:
            if error.status is not None:
                raise RuntimeError("The connection reached an unpinned HTTP endpoint.") from None
        else:
            raise RuntimeError("Private endpoint accepted a client with the wrong trust configuration.")
    before = screenshot(client)
    before.crop(controls["crop"]).save(output / "before.png")
    first = require_color(before, controls["sample"], BEFORE_COLOR)
    commands = [
        {"command": "pointer.click", "params": dict(zip(("x", "y"), controls["entry"]))},
        {"command": "text.insert", "params": {"text": TEST_TEXT, "replace": True}},
        {"command": "pointer.click", "params": dict(zip(("x", "y"), controls["apply"]))},
    ]
    response = client.batch(commands, "transport-journey")
    if response.get("completed") != len(commands):
        raise RuntimeError(f"Fixture action failed: {response}")
    deadline = time.monotonic() + 8
    while True:
        after = screenshot(client)
        after.crop(controls["crop"]).save(output / "after.png")
        try:
            changed = require_color(after, controls["sample"], AFTER_COLOR)
            break
        except AssertionError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(.25)
    reconnected = Client(config, token_file, access_file)
    if reconnected.identify()["id"] != session["id"]:
        raise RuntimeError("Fresh client did not reconnect to the same session.")
    require_color(screenshot(reconnected), controls["sample"], AFTER_COLOR)
    if reconnected.batch(commands, "transport-journey") != response:
        raise RuntimeError("Retrying the same request ID did not return the cached response.")
    return {
        "transport": config["transport"], "target": session["target"],
        "initial_seconds_remaining": session["seconds_remaining"],
        "before_pixel": first, "after_pixel": changed, "anonymous_http": 401, "wrong_bearer_http": 401,
        "reconnected": True, "replayed_request_equal": True,
        "unpinned_tls_rejected": config["transport"] == "private",
        "wrong_host_http": 421 if config["transport"] == "local" else None,
        "image_sha256": {name: sha256((output / name).read_bytes()).hexdigest() for name in ("before.png", "after.png")},
    }


def expiry(config, token_file):
    client = Client(config, token_file)
    live = client.identify()["seconds_remaining"]
    deadline = time.monotonic() + live + 35
    while time.monotonic() < deadline:
        time.sleep(min(2, max(.25, live - 1)))
        try:
            live = client.identify()["seconds_remaining"] if live > 4 else read_live(client)
        except ClientError as error:
            if live > 12 or error.status not in {None, 410, 502, 503, 530}:
                raise
            return {"last_live_seconds_remaining": live, "expired_http": error.status, "expired": True}
    raise RuntimeError("The endpoint stayed live beyond its lease.")


def read_live(client):
    return json.loads(client.fetch("/v1/session", retries=0))["seconds_remaining"]


def remote_controls(client):
    contents = client.command("files.read", {"name": "controls.json"})
    return json.loads(b64decode(contents["result"]["base64"], validate=True))


def network_reconnect(config, token_file):
    client = Client(config, token_file)
    initial = client.identify()
    origin = urlsplit(client.origin)
    rule = ["OUTPUT", "-o", "ui-wg", "-p", "tcp", "--dport", str(origin.port), "-j", "REJECT"]
    subprocess.run(["iptables", "-I", *rule], check=True)
    try:
        try:
            with socket.create_connection((origin.hostname, origin.port), timeout=2):
                raise RuntimeError("The interruption did not block the private UI endpoint.")
        except OSError:
            pass
    finally:
        subprocess.run(["iptables", "-D", *rule], check=True)
    restored = Client(config, token_file).identify()
    if restored["id"] != initial["id"]:
        raise RuntimeError("The restored network reached a different session.")
    return {"traffic_blocked": True, "same_session_after_recovery": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["quick", "private", "local", "fallback", "cross"])
    parser.add_argument("work", type=Path)
    parser.add_argument("--connection", type=Path)
    args = parser.parse_args()
    output = args.work / "public"
    output.mkdir(exist_ok=True)
    token_file = args.work / "token"
    if args.mode == "cross":
        config = read(args.connection)
        if config["transport"] != "private":
            raise RuntimeError("Expected a private endpoint on the other hosted runner.")
        controls = remote_controls(Client(config, token_file))
    else:
        config, controls = connection(args.work, args.work.parent)
        expected = {"quick": "cloudflare-quick", "private": "private", "local": "local", "fallback": "local"}
        if config["transport"] != expected[args.mode]:
            raise RuntimeError("The consumer action published an unexpected transport.")
    report = observe(config, token_file, controls, output)
    if args.mode == "cross":
        report["network_interruption"] = network_reconnect(config, token_file)
    if args.mode != "cross":
        if read(args.work / "app-state.json") != [TEST_TEXT]:
            raise RuntimeError("The app did not receive the exact Unicode text once.")
        report["app_verified_exact_unicode_once"] = True
    if args.mode in {"private", "cross"}:
        transfer = subprocess.check_output(["wg", "show", "ui-wg", "transfer"], text=True).split()
        report["wireguard_bytes_received"], report["wireguard_bytes_sent"] = map(int, transfer[1:3])
        if min(report["wireguard_bytes_received"], report["wireguard_bytes_sent"]) == 0:
            raise RuntimeError("The isolated WireGuard peer did not exchange traffic.")
    report["separate_hosted_peer"] = args.mode == "cross"
    report.update(expiry(config, token_file))
    (output / "result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

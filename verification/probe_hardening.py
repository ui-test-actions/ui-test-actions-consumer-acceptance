"""Observe a published Action session from a separate client with private local tokens."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from datetime import datetime, timezone
from http.client import HTTPSConnection, IncompleteRead
import json
from pathlib import Path
from threading import Event
import time
from urllib.parse import urlsplit
from uuid import uuid4

from probe_fixture import AFTER_COLOR, BEFORE_COLOR, Client, ClientError, exercise, require_color, screenshot
from probe_lifetime import IOS_MACOS_26, LAYOUTS, click


def record(directory, name, value):
    (directory / (name + ".json")).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"check": name, **value}, ensure_ascii=False), flush=True)


def http(client, method, path, payload=None, headers=None):
    origin = urlsplit(client.origin)
    with closing(HTTPSConnection(origin.hostname, origin.port, timeout=12)) as connection:
        connection.request(method, path, body=None if payload is None else json.dumps(payload),
                           headers=client.headers if headers is None else headers)
        response = connection.getresponse()
        data = response.read(524288)
        try:
            result = json.loads(data)
        except ValueError:
            result = {}
        return response.status, result


def eventually(observe, predicate, label, seconds=35):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            value = observe()
            if predicate(value):
                return value
        except ClientError as error:
            if error.status not in (429, 502, 503, 504):
                raise
        time.sleep(.35)
    raise RuntimeError("Timed out observing " + label)


def action(client, name, args=None, request_id=None):
    return client.command(name, args or {}, request_id)["result"]


def error_outcome(client, name, args, request_id):
    try:
        action(client, name, args, request_id)
    except ClientError as error:
        details = (error.payload or {}).get("error", {})
        return error.status, details.get("code") if isinstance(details, dict) else None
    raise AssertionError("An already used request ID was admitted unexpectedly.")


def auth_and_load(client, config, token, out):
    identifier = client.identify()["id"]
    checks = {}
    for label, headers in (
        ("anonymous", {}),
        ("wrong_bearer", {**client.headers, "Authorization": "Bearer " + "0" * 64}),
        ("wrong_session", {**client.headers, "X-UI-Session-ID": "another-session"}),
    ):
        checks[label] = http(client, "GET", "/v1/session", headers=headers)[0]
    assert checks == {"anonymous": 401, "wrong_bearer": 401, "wrong_session": 409}

    def read_group(_):
        observer = Client(config, token)
        return [observer.identify()["id"] for _ in range(12)]

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = [value for group in pool.map(read_group, range(8)) for value in group]
    assert len(results) == 96 and set(results) == {identifier}
    record(out, "authentication-and-parallel-reads", {**checks, "clients": 8, "same_session_reads": len(results)})


def wait_lock_contention(client, point, out):
    x, y = point
    region = {"x": x, "y": y, "width": 1, "height": 1}
    baseline = action(client, "visual.sample", {"region": region})["baseline"]
    scheduled = Event()

    def wait_for_change():
        scheduled.set()
        return error_outcome(client, "visual.wait", {"baseline": baseline, "timeout_ms": 9500},
                             "held-visual-observation")

    with ThreadPoolExecutor(max_workers=8) as pool:
        waiter = pool.submit(wait_for_change)
        assert scheduled.wait(2)
        end = time.monotonic() + 5
        while time.monotonic() < end:
            status, _ = http(client, "POST", "/v2/action", {"command": "performance.observations"})
            if status == 429:
                break
            time.sleep(.15)
        else:
            raise AssertionError("The wait did not hold the driver's operation lock.")
        stages = [pool.submit(http, client, "POST", "/v1/input", {"action": "click", "x": x, "y": y})
                  for _ in range(6)]
        stages += [pool.submit(http, client, "GET", "/v1/session")]
        statuses = [f.result()[0] for f in stages]
        assert statuses == [429] * 6 + [200], statuses
        assert waiter.result() == (408, "condition_timeout")
    record(out, "driver-contention", {"legacy_busy": statuses[:-1], "metadata_http": statuses[-1],
                                       "wait": "condition_timeout"})


def replay_and_lost_write(client, out):
    prefix = uuid4().hex
    old_id = prefix + "-old"
    old = {"text": "قديم ١٢٣ — old 🧪"}
    current = {"text": "الحالي ٤٥٦ — current 🌍"}
    first = action(client, "clipboard.set", old, old_id)
    assert action(client, "clipboard.set", old, old_id) == first
    for index in range(96):
        action(client, "performance.observations", request_id=f"{prefix}-{index}")
    action(client, "clipboard.set", current)
    assert error_outcome(client, "clipboard.set", old, old_id) == (409, "replay_unavailable")
    assert error_outcome(client, "clipboard.set", current, old_id) == (409, "request_conflict")
    assert action(client, "clipboard.get")["text"] == current["text"]

    identifier = prefix + "-lost"
    payload = {"text": "استرداد الاتصال ٧٨٩ — reconnected"}
    opener = client.opener

    class DropResponse:
        def open(self, request, **options):
            # The real hosted endpoint acknowledged the HTTPS request. Discard
            # that reply at the transport boundary so the caller sees a loss.
            with opener.open(request, **options):
                raise IncompleteRead(b"", 1)

    client.opener = DropResponse()
    try:
        assert error_outcome(client, "clipboard.set", payload, identifier) == (None, "action_outcome_unknown")
    finally:
        client.opener = opener
    observed = eventually(lambda: action(client, "clipboard.get")["text"],
                          lambda result: result == payload["text"], "the abandoned write")
    action(client, "clipboard.set", current)
    action(client, "clipboard.set", payload, identifier)
    assert action(client, "clipboard.get")["text"] == current["text"]
    record(out, "duplicate-and-lost-response", {
        "cached_duplicate_equal": True, "intervening_observations": 96, "old_same_payload_status": 409,
        "old_conflicting_payload_status": 409, "abandoned_write_observed": observed,
        "fault": "dropped hosted HTTPS response at the client's transport boundary",
        "same_id_retry_preserved_subsequent_clipboard": True,
    })


def native_crash(client, target, layout, out, *, trigger=True):
    desktop = target in ("linux", "windows", "macos")
    identifier = "crash-fixture" if desktop else "dev.uitest.fixture"
    app = {"id": identifier}
    if trigger and desktop:
        assert action(client, "app.launch", app)["running"]
    elif trigger:
        action(client, "app.deeplink", {"url": "ui-test-fixture://fail-crash", **(app if target == "android" else {})})

    def app_exited():
        return action(client, "app.status" if desktop else "app.metrics", app)

    if desktop:
        exited = eventually(app_exited, lambda result: result.get("exit_code") == 17, "desktop exit 17")
    else:
        exited = eventually(app_exited, lambda result: result.get("running") is False, "mobile process exit")

    screenshot(client).crop(layout.crop).save(out / "native-after-crash.png")
    action(client, "app.launch", app)

    def ready_frame():
        frame = screenshot(client)
        try:
            require_color(frame, layout.sample, BEFORE_COLOR)
        except AssertionError:
            return None
        return frame

    ready = eventually(ready_frame, lambda result: result is not None, "fresh fixture after relaunch")
    ready.crop(layout.crop).save(out / "native-relaunched.png")
    applied = client.batch([click(layout.apply)], uuid4().hex)
    assert applied["completed"] == 1
    frame = screenshot(client)
    require_color(frame, layout.sample, AFTER_COLOR)
    frame.crop(layout.crop).save(out / "native-recovered-action.png")
    if desktop:
        action(client, "app.close", app)
    record(out, "native-crash-recovery", {"process_after_crash": exited, "relaunch_screen_verified": True,
                                           "post_relaunch_native_action_verified": True})


def native_freeze(client, layout, out):
    app = {"id": "freeze-fixture"}
    assert action(client, "app.launch", app)["running"]

    def ready():
        frame = screenshot(client)
        return frame if frame.getpixel(layout.sample) == BEFORE_COLOR else None

    eventually(ready, bool, "the fresh freeze fixture").crop(layout.crop).save(out / "before.png")
    assert client.batch([click(layout.apply)], uuid4().hex)["completed"] == 1
    observed = eventually(lambda: action(client, "diagnostics.events", {"source": "fixture"}),
                          lambda reply: any(event["event"] == "process.frozen" for event in reply["events"]),
                          "the fixture entering its blocked UI callback")
    frozen = screenshot(client)
    assert frozen.getpixel(layout.sample) != AFTER_COLOR
    frozen.crop(layout.crop).save(out / "frozen.png")
    assert action(client, "app.status", app)["running"]
    assert action(client, "app.restart", app)["running"]
    eventually(ready, bool, "the frozen app to relaunch")
    assert client.batch([click(layout.apply)], uuid4().hex)["completed"] == 1
    frame = eventually(lambda: screenshot(client),
                       lambda frame: frame.getpixel(layout.sample) == AFTER_COLOR, "post-restart Apply")
    frame.crop(layout.crop).save(out / "recovered.png")
    assert not action(client, "app.close", app)["running"]
    record(out, "native-freeze-recovery", {"blocked_callback_observed": True, "process_remained_live": True,
                                           "restarted_and_responded": True, "owned_process_closed": True,
                                           "observed_events": len(observed["events"])})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("connection", type=Path)
    parser.add_argument("--token-file", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--case", choices=("full", "resume", "replay", "crash", "recovery", "freeze"), default="full")
    args = parser.parse_args()
    config = json.loads(args.connection.read_text())
    args.output.mkdir(mode=0o700, parents=True, exist_ok=True)
    client = Client(config, args.token_file)
    target = client.identify()["target"]
    layout = IOS_MACOS_26 if target == "ios" else LAYOUTS[target]
    if args.case == "full":
        exercise(config, args.token_file, args.output, layout.entry, layout.apply, layout.sample,
                 layout.crop, layout.dismiss, fixture_text="Stress · العربية ١٢٣ 👩🏽‍💻")
        auth_and_load(client, config, args.token_file, args.output)
        wait_lock_contention(client, layout.sample, args.output)
    if args.case in ("full", "resume", "replay"):
        replay_and_lost_write(client, args.output)
    if args.case == "freeze":
        native_freeze(client, layout, args.output)
    elif args.case != "replay":
        native_crash(client, target, layout, args.output, trigger=args.case != "recovery")
    record(args.output, "complete", {"target": target, "case": args.case,
                                     "at": datetime.now(timezone.utc).isoformat()})


if __name__ == "__main__":
    main()

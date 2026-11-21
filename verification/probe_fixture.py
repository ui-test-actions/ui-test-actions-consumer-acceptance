"""Verify a hosted consumer fixture from a separate machine, saving safe evidence."""

import argparse
from datetime import datetime, timezone
from io import BytesIO
import json
from pathlib import Path
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from uuid import uuid4

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from agent import Client, ClientError


TEST_TEXT = "Verified v2 – أهلاً ١٢٣ 🌍"
BEFORE_COLOR = (25, 43, 66)
AFTER_COLOR = (23, 99, 59)


def screenshot(client):
    return Image.open(BytesIO(client.fetch("/v1/screenshot"))).convert("RGB")


def require_color(frame, point, expected):
    actual = frame.getpixel(tuple(point))
    if max(abs(a - b) for a, b in zip(actual, expected)) > 6:
        raise AssertionError(f"Expected {expected} at {point}, observed {actual}.")
    return actual


def require_authentication(client):
    request = Request(client.origin + "/v1/session")
    try:
        with urlopen(request, timeout=10):
            raise AssertionError("The session allowed an unauthenticated request.")
    except HTTPError as error:
        if error.code != 401:
            raise
        return error.code


def exercise(connection, token_file, evidence, entry, apply, sample, crop, dismiss, *, fixture_text=TEST_TEXT):
    client = Client(connection, token_file)
    session = client.identify()
    capabilities = json.loads(client.fetch("/v2/capabilities"))
    if dismiss:
        client.command("pointer.click", dict(zip(("x", "y"), dismiss)))
        time.sleep(.6)
    before = screenshot(client)
    # Retain a failed observation too. This makes wrong geometry diagnosable.
    before.crop(crop).save(evidence / "before.png")
    before_color = require_color(before, sample, BEFORE_COLOR)
    steps = [
        {"command": "pointer.click", "params": dict(zip(("x", "y"), entry))},
        {"command": "text.insert", "params": {"text": fixture_text, "replace": True}},
        {"command": "pointer.click", "params": dict(zip(("x", "y"), apply))},
    ]
    request_id = uuid4().hex
    batch = client.batch(steps, request_id)
    if not batch["ok"] or batch != client.batch(steps, request_id):
        raise AssertionError(f"The fixture batch failed or was not replayed identically: {batch}")
    for _ in range(10):
        after = screenshot(client)
        after.crop(crop).save(evidence / "after.png")
        try:
            after_color = require_color(after, sample, AFTER_COLOR)
            break
        except AssertionError:
            time.sleep(.25)
    else:
        raise AssertionError("The fixture did not change to its applied state.")
    second_client = Client(connection, token_file)
    if second_client.identify()["id"] != session["id"]:
        raise AssertionError("The fresh client did not reconnect to the same session.")
    require_color(screenshot(second_client), sample, AFTER_COLOR)
    result = {
        "observed_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "target": session["target"],
        "api_version": capabilities["api_version"],
        "anonymous_status": require_authentication(client),
        "reconnected": True,
        "batch_steps": batch["completed"],
        "batch_replay_equal": True,
        "before_color": before_color,
        "after_color": after_color,
        "fixture_text": fixture_text,
    }
    (evidence / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("connection", type=Path)
    parser.add_argument("--token-file", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--entry", nargs=2, type=int, required=True)
    parser.add_argument("--apply", nargs=2, type=int, required=True)
    parser.add_argument("--sample", nargs=2, type=int, required=True)
    parser.add_argument("--crop", nargs=4, type=int, required=True, metavar=("LEFT", "TOP", "RIGHT", "BOTTOM"))
    parser.add_argument("--dismiss", nargs=2, type=int, help="Optional coordinates of a visible startup prompt")
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    try:
        result = exercise(json.loads(args.connection.read_text(encoding="utf-8")), args.token_file,
                          args.evidence, args.entry, args.apply, args.sample, args.crop, args.dismiss)
    except (AssertionError, ClientError) as error:
        parser.exit(1, f"{error}\n")
    print(json.dumps(result, ensure_ascii=False))

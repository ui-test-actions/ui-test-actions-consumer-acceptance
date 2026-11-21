"""Fetch pinned third-party fixtures and verify text saved by the real application."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
from urllib.request import urlopen

HERE = Path(__file__).resolve().parent
SEED = "Original document from the UI journey.\n"
TITLE = "اختبار ١٢٣ — UI journey 🌍"
EXPECTED = "مرحبًا بالعالم، هذه تجربة ١٢٣؟\nHello from لوحة المفاتيح 🌍 — café\n- [ ] مراجعة الاختبار!"


def release(target: str) -> dict:
    return json.loads((HERE / "apps.json").read_text(encoding="utf-8"))[target]


def prepare(target: str, directory: Path, evidence: Path) -> None:
    entry = release(target)
    evidence.mkdir(parents=True, exist_ok=True)
    directory.mkdir(parents=True, exist_ok=True)
    (evidence / "app.json").write_text(json.dumps(entry, indent=2) + "\n", encoding="utf-8")
    (evidence / "document.txt").write_bytes(SEED.encode("utf-8"))
    if "asset" not in entry:
        return
    url = f"https://github.com/{entry['repository']}/releases/download/{entry['ref']}/{entry['asset']}"
    downloaded = directory / entry["asset"]
    print(f"Downloading pinned release for {entry['app']}", flush=True)
    with urlopen(url, timeout=60) as response, downloaded.open("wb") as destination:
        shutil.copyfileobj(response, destination)
    with downloaded.open("rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != entry["sha256"]:
            downloaded.unlink()
            raise SystemExit(f"Release digest mismatch for {entry['app']}")
    print(f"Verified upstream release digest for {entry['app']}")


def assert_persisted(target: str, path: Path, evidence: Path) -> None:
    raw = path.read_bytes()
    if target == "ios":
        notes = json.loads(raw)["data"]["notes"]
        matches = [
            note for note in notes
            if note.get("title") == TITLE and note.get("body") == EXPECTED
            and note.get("status") == "active" and not note.get("sample")
        ]
        if len(matches) != 1:
            raise SystemExit("Thought Meadow did not persist exactly one matching active note")
    else:
        # Editors can preserve/add an EOF newline, UTF-8 BOM or use CRLF on Windows.
        value = raw.decode("utf-8-sig").replace("\r\n", "\n").removesuffix("\n")
        if value != EXPECTED:
            raise SystemExit("Saved UTF-8 document did not match the expected Unicode journey text")
    result = {
        "app": release(target)["app"],
        "target": target,
        "result": "passed",
        "persisted_utf8_sha256": hashlib.sha256(raw).hexdigest(),
        "tested_text": EXPECTED,
    }
    (evidence / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Verified the app persisted the expected Unicode and multiline text on {target}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["prepare", "assert"])
    parser.add_argument("target", choices=["linux", "windows", "macos", "android", "ios"])
    parser.add_argument("path", type=Path)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    function = prepare if args.operation == "prepare" else assert_persisted
    function(args.target, args.path, args.evidence)


if __name__ == "__main__":
    main()

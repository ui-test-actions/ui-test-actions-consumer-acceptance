"""Exercise the hosted fixture repeatedly and retain a trace of real transitions."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from probe_lifetime import (
    IOS_MACOS_26, LAYOUTS, Client, change_label, checkpoint, opening,
    observe_expiry, save, utc,
)

target, path, run_id = sys.argv[1:]
root = Path(path)
evidence = root / 'evidence'
evidence.mkdir(exist_ok=True)
connection_file = root / 'connection' / 'connection.json'
until = time.monotonic() + 540
while not connection_file.is_file():
    if time.monotonic() > until:
        raise TimeoutError(f'No connection file for hosted run {run_id}')
    time.sleep(3)
config = json.loads(connection_file.read_text())
token = root / 'token'
client = Client(config, token)
layout = IOS_MACOS_26 if target == 'ios' else LAYOUTS[target]
if not (evidence / 'result.json').exists():
    opening(config, token, client, evidence, layout, hour=True)
initial = client.identify()
deadline = config['expires_unix']
assert initial['target'] == target
other_token = (root.parent / ('macos' if target == 'windows' else 'windows') / 'token').read_text()
cross = Request(client.origin + '/v1/session', headers={'Authorization': f'Bearer {other_token}'})
try:
    with urlopen(cross, timeout=8):
        raise AssertionError('A bearer from a different run was accepted')
except HTTPError as error:
    assert error.code == 401, error.code
    save(evidence / 'isolation.json', {'other_session_bearer_http': error.code, 'at': utc()})

def reads():
    reconnect = Client(config, token)
    timing = []
    for _ in range(6):
        start = time.monotonic()
        state = reconnect.identify()
        assert state['id'] == initial['id'] and state['target'] == target
        timing.append(round((time.monotonic() - start) * 1000))
    return timing

for remaining in range(3300, 299, -300):
    if deadline - time.time() < remaining - 120:
        continue
    while (delay := deadline - remaining - time.time()) > 0:
        time.sleep(min(delay, 30))
    sequence = (3600 - remaining) // 300
    prefix = f'round-{sequence:02}'
    label = f'Round {sequence:02d} - اختبار {sequence}'
    with ThreadPoolExecutor(max_workers=8) as executor:
        futures = [executor.submit(reads) for _ in range(8)]
        region = change_label(client, evidence, target, layout, label, prefix)
        timings = [ms for future in futures for ms in future.result()]
    result = checkpoint(client, evidence)
    sample = {'at': utc(), 'target': target, 'run_id': int(run_id), 'round': sequence,
              'seconds_remaining': result['seconds_remaining'], 'same_session_reads': len(timings),
              'metadata_ms': timings, 'applied_text': label, 'changed_label_bounds': region}
    with (evidence / 'rounds.jsonl').open('a', encoding='utf-8') as stream:
        stream.write(json.dumps(sample, ensure_ascii=False) + chr(10))
    print(json.dumps({key: value for key, value in sample.items() if key != 'metadata_ms'}), flush=True)

observe_expiry(client, evidence, target, layout)

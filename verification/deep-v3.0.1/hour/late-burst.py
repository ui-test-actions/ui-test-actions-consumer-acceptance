"""Run concurrent authenticated observations against our hosted runners only."""
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
from statistics import median
import sys
import time

from agent import Client, ClientError

root = Path(sys.argv[1])
config = json.loads((root / 'connection' / 'connection.json').read_text())
token = root / 'token'
primary = Client(config, token)
opening = primary.identify()

def worker(index):
    client = Client(config, token)
    reports = []
    for shot in range(14):
        path = '/v1/screenshot' if shot % 5 == 0 else '/v1/session'
        started = time.monotonic()
        error_code = None
        try:
            data = client.fetch(path, retries=0)
            if path.endswith('screenshot'):
                assert data.startswith(b'\x89PNG\r\n\x1a\n')
            else:
                node = json.loads(data)
                assert node['id'] == opening['id'] and node['target'] == opening['target']
            status = 200
        except ClientError as error:
            status = error.status or 'connection_error'
            error_code = (error.payload or {}).get('error')
        reports.append({'resource': path, 'http': status, 'error': error_code, 'ms': round((time.monotonic()-started)*1000)})
        time.sleep(.05 * (1 + (index % 4)))
    return reports

with ThreadPoolExecutor(max_workers=12) as workers:
    results = [response for series in workers.map(worker, range(12)) for response in series]
after = Client(config, token).identify()
assert after['id'] == opening['id']
counts = dict(Counter(str(row['http']) for row in results))
output = {'at': datetime.now(timezone.utc).isoformat(),'target':after['target'],
          'workers':12,'requests':len(results),'same_session_after':True,'remaining_after':after['seconds_remaining'],
          'counts':counts,'median_ms':median(row['ms'] for row in results),
          'valid_screenshots':sum(row['http']==200 for row in results if row['resource'].endswith('screenshot')),
          'samples':results}
(root / 'evidence' / 'late-burst.json').write_text(json.dumps(output, indent=2) + '\n')
summary = {key: value for key, value in output.items() if key != 'samples'}
print(json.dumps(summary), flush=True)
assert output['valid_screenshots'] > 0 and counts.get('200',0) >= 120

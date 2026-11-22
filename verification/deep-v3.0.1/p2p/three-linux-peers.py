import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

root = Path(__file__).parent
sample = root/'p2p-source/samples/p2p-sample-desktop/build/install/p2p-sample-desktop/bin/p2p-sample-desktop'
work = root/sys.argv[1] if len(sys.argv) > 1 else root/'p2p-three-peers'
work.mkdir(exist_ok=False)
peers = {}
receipt = {'mode':'three unchanged P2pKit CLI applications in an isolated Linux network namespace',
           'app_source':'fd3cd74fcc82d342ee6c5a305f7ed15b0b7ed19d', 'events':[]}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def start(peer):
    home = work / peer
    home.mkdir()
    log = home/'sample.log'
    with log.open('wb') as stream:
        process = subprocess.Popen([str(sample), peer, 'synthetic.uita.p2p', 'trace=on'], cwd=home,
            stdin=subprocess.PIPE, stdout=stream, stderr=subprocess.STDOUT, text=True,
            env={**os.environ, 'JAVA_HOME':'/usr/lib/jvm/java-17-openjdk-amd64',
                 'JAVA_OPTS':f'-Duser.home={home} -Djava.net.preferIPv4Stack=true -XX:ActiveProcessorCount=2'})
    peers[peer] = (process, log)

def read(peer):
    return peers[peer][1].read_text(errors='replace')

def send(peer, command):
    process = peers[peer][0]
    if process.poll() is not None:
        raise RuntimeError(f'{peer} ended before {command.split()[0]}')
    process.stdin.write(command+'\n')
    process.stdin.flush()

def ready(description, check, limit=30):
    stop = time.monotonic() + limit
    while time.monotonic() < stop:
        if result := check():
            return result
        time.sleep(.25)
    raise TimeoutError(description)

def query(peer, command):
    pos = len(read(peer))
    send(peer, command)
    time.sleep(.23)
    return read(peer)[pos:]

def offer(peer, filename):
    text = query(peer, 'offers')
    for line in text.splitlines():
        if filename in line:
            match = re.search(r'selector=(\S+)', line)
            if match:
                return match[1]
    return None

try:
    for name in ('Alpha','Beta','Gamma'):
        start(name)
    for name in peers:
        ready(f'{name} startup', lambda: 'Ready.' in read(name))
    counts = {}
    for peer in peers:
        counts[peer] = ready(f'{peer} mDNS discovery', lambda: (count if (count := len(re.findall(r'\[(?:JVM_DESKTOP|DESKTOP|Desktop|JVM|Jvm|LINUX|Linux)\]', query(peer,'peers')))) == 2 else None), 40)
    receipt['events'].append({'discovered_peer_counts':counts, 'discovery':'native mDNS; no manual addresses passed'})
    for peer in peers:
        ready(f'{peer} authenticated peer sessions', lambda: len(re.findall(r'state=Connected\b', query(peer,'sessions'))) == 2, 20)
    receipt['events'].append({'authenticated_mesh_sessions_per_peer':2})
    specifications = [('Alpha','Beta','alpha-small.bin',256,31), ('Gamma','Alpha','gamma-medium.bin',2*1024*1024,17), ('Beta','Gamma','beta-large.bin',7*1024*1024,43)]
    transfers = []
    for sender, receiver, filename, size, salt in specifications:
        payload = work/sender/filename
        pattern = bytes((index*salt+7)%256 for index in range(256))
        payload.write_bytes(pattern * (size//256))
        send(sender, f'sendfile {receiver} {payload}')
        transfers.append((receiver, filename, size, digest(payload)))
    accepted = []
    for peer, filename, *_ in transfers:
        accepted.append((peer, ready(f'{peer} incoming offer for {filename}', lambda: offer(peer,filename), 20)))
    for peer, selector in accepted:
        send(peer, f'accept {selector}')
    for peer, filename, size, expected in transfers:
        def matching_file():
            files = list((work/peer/'.p2pkit/incoming').rglob(filename))
            return files[0] if files and files[0].stat().st_size == size and digest(files[0]) == expected else None
        ready(f'{peer} verified file {filename}', matching_file, 45)
        receipt['events'].append({'receiver':peer,'file':filename,'bytes':size,'sha256':expected,'received_sha256_matches':True})
    receipt['result'] = 'success'
except Exception as error:
    receipt['result'] = 'failure'
    receipt['failed_checkpoint'] = str(error)
    raise
finally:
    for peer, (process, _) in peers.items():
        if process.poll() is None:
            try:
                send(peer, 'quit')
                process.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                process.terminate()
                process.wait(timeout=5)
    receipt['native_exit_codes'] = {peer: descriptor[0].returncode for peer,descriptor in peers.items()}
    (work/'results.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print(json.dumps(receipt), flush=True)

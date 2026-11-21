from hashlib import sha256
import json
from pathlib import Path
import struct
import sys
import time
from datetime import datetime, timezone

from agent import Client, ClientError

root=Path(sys.argv[1]).resolve()
out=root/'evidence'
out.mkdir(exist_ok=True)
config=json.loads(next((root/'connection').rglob('connection.json')).read_text())
client=Client(config,root/'token')
events=[]

def event(kind,**details):
    events.append({'event':kind,'utc':datetime.now(timezone.utc).isoformat(),**details})
    (out/'observations.json').write_text(json.dumps(events,ensure_ascii=False,indent=2)+'\n')
    print(kind, details, flush=True)

def action(name, **params):
    reply=client.command(name,params)
    assert reply['ok']
    return reply['result']

def labels():
    tree=action('tree.snapshot',limit=220)
    return tree,[n.get('text') or n.get('name') for n in tree['nodes']
                 if n.get('visible') and (n.get('text') or n.get('name'))]

def eventually(observe, valid):
    for _ in range(18):
        result=observe()
        if valid(result): return result
        time.sleep(.6)
    raise RuntimeError('Expected screen state did not appear')

def screen(name):
    data=client.fetch('/v1/screenshot')
    assert data[:8]==b'\x89PNG\r\n\x1a\n'
    (out/(name+'.png')).write_bytes(data)
    dims=struct.unpack('>II',data[16:24])
    event('screenshot',file=name+'.png',dimensions=dims,sha256=sha256(data).hexdigest())
    return dims

def click_label(predicate):
    tree,_=labels()
    candidates=[n for n in tree['nodes'] if n.get('visible') and n.get('enabled') and
                predicate(n.get('text') or n.get('name') or '')]
    [node]=candidates
    action('element.click',id=node['id'],snapshot_id=tree['snapshot_id'])

def run():
    live=client.identify()
    assert live['target']=='android'
    event('connected',target='android',lease_remaining=live['seconds_remaining'],transport=config['transport'])
    assert 'BEFORE · Ready for input' in labels()[1]
    portrait=screen('01-stock-fixture')
    click_label(lambda value: value.casefold()=='apply change')
    eventually(labels,lambda item:'AFTER · Button tapped' in item[1])
    screen('02-native-button-applied')
    action('device.orientation',orientation='landscape')
    try:
        landscape=eventually(lambda: struct.unpack('>II',client.fetch('/v1/screenshot')[16:24]),lambda d:d[0]>d[1])
        assert landscape==screen('03-landscape')
    finally:
        action('device.orientation',orientation='portrait')
    restored=eventually(lambda: struct.unpack('>II',client.fetch('/v1/screenshot')[16:24]),lambda d:d==portrait)
    event('orientation_restored',dimensions=restored)
    app='me.parlor.android'
    action('app.install',id=app)
    event('installed_with_ui_test_actions',package=app)
    action('app.launch',id=app)
    _, names=eventually(labels,lambda item:'Parlor' in item[1] and any('Whodunit' in x for x in item[1]))
    event('real_app_home_verified',labels=names)
    screen('04-parlor-installed-and-running')
    click_label(lambda value: value.startswith('Open Whodunit'))
    _, names=eventually(labels,lambda item:'Pass and Play' in item[1])
    event('real_app_navigation_verified',labels=names)
    screen('05-parlor-whodunit')
    action('app.launch',id='com.android.vending')
    _, names=eventually(labels,lambda item:any('Sign in' in x or 'Settings' in x or 'Google Play' in x for x in item[1]))
    event('google_play_store_observed',labels=names)
    screen('06-stock-play-store')

if __name__=='__main__':
    try:
        run()
    except ClientError as error:
        event('client_error',http_status=error.status,error=(error.payload or {}).get('error'))
        raise

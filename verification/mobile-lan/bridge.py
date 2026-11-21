"""One isolated IPv4 LAN over mutually authenticated TLS carried by WebSocket."""

import argparse
import asyncio
from collections import Counter
from contextlib import suppress
from http import HTTPStatus
from ipaddress import IPv4Address
import json
from pathlib import Path
import re
import ssl
import struct
import sys
from urllib.parse import urlsplit

from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
from websockets.exceptions import InvalidStatus

# The workflow runs this file directly.
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from link_faults import FrameQueue, LinkFaults

FRAME_MAX = 1514
STREAM_CHUNK = 16384
MDNS = IPv4Address("224.0.0.251").packed
ANDROID = IPv4Address("192.168.137.10").packed
IOS = IPv4Address("192.168.137.2").packed
P2PKIT_SERVICE = b"\x08_p2pkit2\x04_tcp"


def permitted(frame, source, peer):
    """Keep host networking outside the bridge, including DHCP and default routes."""
    if not 14 <= len(frame) <= FRAME_MAX:
        return False
    if frame[12:14] == b"\x08\x06":
        return (len(frame) >= 42 and frame[14:22] in
                (b"\0\1\x08\0\x06\x04\0\1", b"\0\1\x08\0\x06\x04\0\2") and
                frame[22:28] == frame[6:12] and frame[28:32] == source and frame[38:42] == peer)
    if frame[12:14] != b"\x08\x00" or len(frame) < 34 or frame[14] != 0x45:
        return False
    length = int.from_bytes(frame[16:18], "big")
    if not 20 <= length <= len(frame) - 14 or int.from_bytes(frame[20:22], "big") & 0x3fff:
        return False
    if frame[26:30] != source:
        return False
    destination = frame[30:34]
    protocol = frame[23]
    if destination == peer and protocol in (1, 6):
        return True
    if protocol != 17 or length < 28 or destination not in (peer, MDNS):
        return False
    src_port, dst_port = struct.unpack("!HH", frame[34:38])
    return dst_port == 5353 or destination == peer and src_port == 5353


async def frames(reader, source, peer):
    while True:
        header = await reader.readexactly(2)
        length, = struct.unpack("!H", header)
        if not 14 <= length <= FRAME_MAX:
            raise ValueError("Invalid LAN frame length")
        frame = await reader.readexactly(length)
        if permitted(frame, source, peer):
            yield header, frame


async def records(reader, writer, source, peer, counts, faults=None, direction=0):
    async def forward(header, frame):
        if frame[12:14] == b"\x08\x06":
            counts["arp"] += 1
        else:
            counts[{1: "icmp", 6: "tcp", 17: "mdns"}[frame[23]]] += 1
            if frame[23] == 17 and P2PKIT_SERVICE in frame[42:].lower():
                kind = "response" if int.from_bytes(frame[44:46], "big") & 0x8000 else "query"
                counts[f"p2pkit_mdns_{kind}"] += 1
        writer.write(header + frame)
        await writer.drain()

    if faults is None:
        async for header, frame in frames(reader, source, peer):
            await forward(header, frame)
        return
    queue = FrameQueue(faults, direction, counts)

    async def enqueue():
        async for header, frame in frames(reader, source, peer):
            queue.push(header, frame)

    async def deliver():
        while True:
            await forward(*(await queue.next()))

    await duplex(enqueue(), deliver())


async def duplex(left, right):
    tasks = [asyncio.create_task(coroutine) for coroutine in (left, right)]
    try:
        done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            task.result()
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)


async def frame_session(reader, writer, args, source, peer):
    process = await asyncio.create_subprocess_exec(
        str(args.frame_port), args.interface, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE)
    sent, received = Counter(), Counter()

    async def evidence():
        while True:
            dump_counts()
            await asyncio.sleep(3)

    def dump_counts():
        temporary = args.stats.with_suffix(".tmp")
        state = {"sent": sent, "received": received}
        if args.faults:
            state["link"] = args.faults.inspect()
        temporary.write_text(json.dumps(state) + "\n", encoding="utf-8")
        temporary.replace(args.stats)

    monitor = asyncio.create_task(evidence())
    try:
        if await asyncio.wait_for(process.stdout.readexactly(2), timeout=5) != b"\0\0":
            raise RuntimeError("Native frame port failed its readiness check")
        args.ready.touch()
        print("Authenticated LAN peer attached", flush=True)
        await duplex(records(process.stdout, writer, source, peer, sent, args.faults, 0),
                     records(reader, process.stdin, peer, source, received, args.faults, 1))
    except (asyncio.IncompleteReadError, ConnectionError):
        pass
    finally:
        monitor.cancel()
        await asyncio.gather(monitor, return_exceptions=True)
        dump_counts()
        args.ready.unlink(missing_ok=True)
        if process.returncode is None:
            with suppress(ProcessLookupError):
                process.terminate()
        await process.wait()
        writer.close()
        with suppress(OSError, TimeoutError):
            await writer.wait_closed()


async def websocket_proxy(websocket, reader, writer):
    async def from_socket():
        while chunk := await reader.read(STREAM_CHUNK):
            await websocket.send(chunk)

    async def from_websocket():
        async for chunk in websocket:
            if not isinstance(chunk, bytes):
                raise ValueError("Only binary transport is supported")
            writer.write(chunk)
            await writer.drain()

    try:
        await duplex(from_socket(), from_websocket())
    finally:
        writer.close()
        with suppress(OSError):
            await writer.wait_closed()


def tls(args, server):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER if server else ssl.PROTOCOL_TLS_CLIENT)
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_cert_chain(args.cert, args.key)
    context.load_verify_locations(args.peer_cert)
    return context


WS_OPTIONS = {"compression": None, "max_size": STREAM_CHUNK, "max_queue": 8,
              "open_timeout": 8, "close_timeout": 2, "ping_interval": 15}


async def server(args):
    active = asyncio.Lock()
    proxy_budget = asyncio.Semaphore(8)

    async def peer(reader, writer):
        if active.locked():
            writer.close()
            return
        async with active:
            await frame_session(reader, writer, args, ANDROID, IOS)

    async with await asyncio.start_server(peer, "127.0.0.1", 0, ssl=tls(args, True), ssl_handshake_timeout=6) as inner:
        port = inner.sockets[0].getsockname()[1]

        async def proxy(websocket):
            if proxy_budget.locked():
                await websocket.close(code=1013)
                return
            async with proxy_budget:
                reader, writer = await asyncio.open_connection("127.0.0.1", port)
                await websocket_proxy(websocket, reader, writer)

        async def path_check(connection, request):
            if request.path != "/lan":
                return connection.respond(HTTPStatus.NOT_FOUND, "Unknown route\n")
            return None

        async with serve(proxy, "127.0.0.1", args.port, process_request=path_check, **WS_OPTIONS) as outer:
            await outer.serve_forever()


def endpoint(hostname):
    parsed = urlsplit(hostname)
    if not re.fullmatch(r"https://[a-z0-9-]+\.trycloudflare\.com", hostname):
        raise ValueError("Expected the HTTPS origin published by the paired GitHub job")
    return f"wss://{parsed.hostname}/lan"


async def client(args):
    async def proxy(reader, writer):
        try:
            async with connect(endpoint(args.origin), **WS_OPTIONS) as websocket:
                await websocket_proxy(websocket, reader, writer)
        except InvalidStatus as error:
            print(f"Relay handshake returned HTTP {error.response.status_code}", flush=True)
        finally:
            writer.close()

    async with await asyncio.start_server(proxy, "127.0.0.1", 0) as outer:
        port = outer.sockets[0].getsockname()[1]
        context = tls(args, False)
        deadline = asyncio.get_running_loop().time() + 145
        while True:
            try:
                reader, writer = await asyncio.open_connection(
                    "127.0.0.1", port, ssl=context, server_hostname="ui-mobile-lan", ssl_handshake_timeout=12)
                break
            except ConnectionError:
                if asyncio.get_running_loop().time() >= deadline:
                    raise
                await asyncio.sleep(3)
        await frame_session(reader, writer, args, IOS, ANDROID)


async def run(args):
    args.faults = LinkFaults() if args.control else None
    service = server if args.role == "server" else client
    if not args.faults:
        await service(args)
        return
    control = await args.faults.listen(args.control)
    try:
        async with control:
            await service(args)
    finally:
        args.control.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("role", choices=("server", "client"))
    parser.add_argument("--interface", required=True)
    parser.add_argument("--frame-port", required=True, type=Path)
    parser.add_argument("--cert", required=True, type=Path)
    parser.add_argument("--key", required=True, type=Path)
    parser.add_argument("--peer-cert", required=True, type=Path)
    parser.add_argument("--ready", required=True, type=Path)
    parser.add_argument("--stats", required=True, type=Path)
    parser.add_argument("--port", type=int, default=8788)
    parser.add_argument("--origin")
    parser.add_argument("--control", type=Path)
    args = parser.parse_args()
    asyncio.run(run(args))


if __name__ == "__main__":
    main()

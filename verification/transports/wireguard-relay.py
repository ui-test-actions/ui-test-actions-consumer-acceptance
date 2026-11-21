"""CI-only UDP carrier for a WireGuard proof across two NATed hosted VMs."""

import argparse
import asyncio
from pathlib import Path
import signal
import socket
import sys
import time
from urllib.parse import urlsplit

from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tunnel import QUICK_URL, Tunnel, download_tunnel


PATH = "/wireguard"
OPTIONS = {"compression": None, "max_size": 2048, "max_queue": 8, "open_timeout": 8, "ping_interval": 8}


async def forward(websocket, listen, target):
    loop = asyncio.get_running_loop()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as channel:
        channel.bind(("127.0.0.1", listen))
        channel.connect(("127.0.0.1", target))
        channel.setblocking(False)

        async def from_kernel():
            while packet := await loop.sock_recv(channel, 2048):
                await websocket.send(packet)

        async def to_kernel():
            async for packet in websocket:
                if isinstance(packet, bytes):
                    await loop.sock_sendall(channel, packet)

        tasks = [asyncio.create_task(exchange()) for exchange in (from_kernel, to_kernel)]
        try:
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
        except ConnectionClosed:
            pass
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)


async def host(work, stop):
    routes = asyncio.Semaphore(6)

    async def handle(websocket):
        if websocket.request.path != PATH or routes.locked():
            await websocket.close(code=1008)
            return
        async with routes:
            await forward(websocket, 0, 51871)

    async with serve(handle, "127.0.0.1", 0, origins=[None], **OPTIONS) as server:
        port = server.sockets[0].getsockname()[1]
        connector = Tunnel(await asyncio.to_thread(download_tunnel, work), port, work)
        try:
            origin = await asyncio.to_thread(connector.start, time.monotonic() + 110, stop.is_set)
            (work / "origin").write_text(origin + "\n", encoding="ascii")
            while connector.process.poll() is None:
                try:
                    await asyncio.wait_for(stop.wait(), timeout=1)
                    return
                except TimeoutError:
                    continue
            raise RuntimeError("The test-only Quick Tunnel stopped.")
        finally:
            connector.close()


async def peer(work, stop):
    origin = (work / "origin").read_text(encoding="ascii").strip()
    if not QUICK_URL.fullmatch(origin):
        raise ValueError("Expected a test relay hostname in the run's rendezvous artifact.")
    uri = "wss://" + urlsplit(origin).netloc + PATH
    async for websocket in connect(uri, proxy=None, **OPTIONS):
        await forward(websocket, 51873, 51872)
        if stop.is_set():
            return


async def run(mode, work):
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)
    if mode == "host":
        await host(work, stop)
    else:
        connection = asyncio.create_task(peer(work, stop))
        finished = asyncio.create_task(stop.wait())
        done, pending = await asyncio.wait((connection, finished), return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)
        for task in done:
            task.result()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("host", "peer"))
    parser.add_argument("work", type=Path)
    args = parser.parse_args()
    asyncio.run(run(args.mode, args.work))

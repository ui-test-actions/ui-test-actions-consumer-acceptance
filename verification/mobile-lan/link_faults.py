"""Shape forwarded LAN frames while the relay and UI endpoints stay reachable."""

import asyncio
from contextlib import suppress
import json
import os
import random
import time

from contract import NETWORK_PROFILE, validate
from network_control import MAX_MESSAGE, NETWORK_COMMANDS


DEFAULT = {"delay_ms": 0, "jitter_ms": 0, "loss_percent": 0, "rate_kbit": 0,
           "offline": False, "seconds": 30, "seed": 0}
QUEUE_LIMIT = 128


class LinkFaults:
    def __init__(self):
        self.loop = asyncio.get_running_loop()
        self.profile = DEFAULT.copy()
        self.generation = 0
        self.changed = asyncio.Event()
        self.expires = 0
        self.timer = None

    def apply(self, params, lease=True):
        validate(params, NETWORK_PROFILE, "profile")
        if self.timer:
            self.timer.cancel()
        self.changed.set()
        self.changed = asyncio.Event()
        self.profile = {**DEFAULT, **params}
        self.generation += 1
        self.expires = self.loop.time() + self.profile["seconds"] if lease else 0
        self.timer = self.loop.call_at(self.expires, self.reset) if lease else None

    def reset(self):
        self.apply({}, lease=False)

    def inspect(self):
        return {"profile": self.profile, "generation": self.generation,
                "remaining_ms": max(0, round((self.expires - self.loop.time()) * 1000)),
                "controller_epoch_ms": time.time_ns() // 1_000_000}

    async def command(self, reader, writer):
        try:
            line = await asyncio.wait_for(reader.readline(), 2)
            if len(line) > MAX_MESSAGE:
                return
            request = json.loads(line)
            if type(request) is not dict or set(request) != {"command", "params"}:
                return
            command, params = request["command"], request["params"]
            if command not in NETWORK_COMMANDS or type(params) is not dict:
                return
            if command == "network.profile.set":
                self.apply(params)
            elif params:
                return
            elif command == "network.profile.reset":
                self.reset()
            writer.write(json.dumps(self.inspect()).encode() + b"\n")
            await writer.drain()
        except (OSError, ValueError, TypeError):
            pass
        finally:
            writer.close()
            with suppress(OSError, TimeoutError):
                await writer.wait_closed()

    async def listen(self, path):
        parent = path.parent.resolve(strict=True)
        directory = parent.stat()
        if directory.st_mode & 0o077:
            raise ValueError("The LAN control directory must be private.")
        server = await asyncio.start_unix_server(self.command, path=parent / path.name, limit=MAX_MESSAGE)
        try:
            os.chmod(path, 0o600)
            os.chown(path, directory.st_uid, directory.st_gid)
            return server
        except OSError:
            server.close()
            await server.wait_closed()
            raise


class FrameQueue:
    def __init__(self, faults, direction, counters):
        self.faults = faults
        self.direction = direction
        self.counters = counters
        self.queue = asyncio.Queue(maxsize=QUEUE_LIMIT)
        self.generation = -1
        self.scheduled = 0

    def push(self, header, frame):
        faults = self.faults
        profile = faults.profile
        if self.generation != faults.generation:
            self.generation = faults.generation
            self.random = random.Random(profile["seed"] + self.direction)
            self.scheduled = 0
        if profile["offline"] or self.random.randrange(100) < profile["loss_percent"]:
            self.counters["fault_drop"] += 1
            return
        if self.queue.full():
            self.counters["fault_queue_full"] += 1
            return
        jitter = self.random.randint(-profile["jitter_ms"], profile["jitter_ms"])
        delay = max(0, profile["delay_ms"] + jitter) / 1000
        due = max(self.scheduled, faults.loop.time() + delay)
        if rate := profile["rate_kbit"]:
            due += len(frame) * 8 / (rate * 1000)
        self.scheduled = due
        self.queue.put_nowait((faults.changed, due, header, frame))

    async def next(self):
        while True:
            changed, due, header, frame = await self.queue.get()
            if not changed.is_set():
                remaining = due - self.faults.loop.time()
                if remaining > 0:
                    with suppress(TimeoutError):
                        await asyncio.wait_for(changed.wait(), remaining)
                if not changed.is_set():
                    return header, frame
            self.counters["fault_flushed"] += 1

"""Keep the runner-owned WebSocket tunnel alive for this experiment."""

from pathlib import Path
import signal
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tunnel import Tunnel, download_tunnel


def main():
    work = Path(sys.argv[1])
    output = Path(sys.argv[2])
    work.mkdir(parents=True, exist_ok=True)
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    tunnel = Tunnel(download_tunnel(work), 8788, work)
    try:
        address = tunnel.start(time.monotonic() + 105, stop.is_set)
        output.write_text(address + "\n", encoding="ascii")
        while not stop.wait(1):
            if tunnel.process.poll() is not None:
                raise RuntimeError("LAN Quick Tunnel exited")
    finally:
        output.unlink(missing_ok=True)
        tunnel.close()


if __name__ == "__main__":
    main()

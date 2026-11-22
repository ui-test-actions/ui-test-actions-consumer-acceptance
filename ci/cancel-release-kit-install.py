"""Cancel the runner-owned installer before dpkg can modify its package state."""
import fcntl
import json
from pathlib import Path
import signal
import subprocess
import sys
from time import monotonic, sleep

PACKAGE = "mobile-release-kit-desktop"

def installed():
    return subprocess.run(["dpkg-query", "-W", "-f=${Status}", PACKAGE],
                          capture_output=True, text=True, check=False).stdout == "install ok installed"

def main(package, evidence):
    if installed():
        raise AssertionError("The cancellation check requires an empty runner")
    with open("/var/lib/dpkg/lock-frontend", "rb+") as lock:
        fcntl.lockf(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        log = evidence.with_suffix(".log")
        with log.open("wb") as output:
            child = subprocess.Popen(
                ["apt-get", "-o", "DPkg::Lock::Timeout=40", "install", "-y", str(package)],
                stdout=output, stderr=subprocess.STDOUT,
            )
            try:
                deadline = monotonic() + 8
                while "Waiting for cache lock" not in log.read_text(errors="replace"):
                    if child.poll() is not None or monotonic() >= deadline:
                        raise RuntimeError("The installer did not reach the expected package lock")
                    sleep(.2)
                child.send_signal(signal.SIGTERM)
                exit_status = child.wait(timeout=10)
                if exit_status != -signal.SIGTERM:
                    raise AssertionError(f"Unexpected installer exit {exit_status}")
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait(timeout=5)
        if installed() or Path("/usr/bin/mobile-release-kit-desktop").exists():
            raise AssertionError("The cancelled invocation changed package state")
    evidence.write_text(json.dumps({"lock_observed": True, "terminated": True,
                                   "installed_after_cancellation": False, "exit": exit_status}) + "\n")

if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))

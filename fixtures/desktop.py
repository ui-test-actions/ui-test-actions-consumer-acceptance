import json
import os
import time
import tkinter as tk
from threading import Event
from pathlib import Path
import sys

root = tk.Tk()
root.title("Live UI test fixture")
root.geometry("560x350+60+60")
root.configure(bg="#192b42")
state = tk.StringVar(value="BEFORE · Ready for input")
status = tk.Label(root, textvariable=state, fg="white", bg="#192b42", font=("Arial", 23))
status.pack(pady=(35, 20))
entry = tk.Entry(root, width=30, font=("Arial", 18))
entry.pack(pady=8)

def note(event, **kwargs):
    if path := os.environ.get("UI_FIXTURE_EVENTS"):
        with open(path, "a", encoding="utf-8") as log:
            print(json.dumps({"event": event, "epoch_ms": time.time_ns() // 1_000_000, **kwargs}), file=log)


def apply():
    if len(sys.argv) == 3 and sys.argv[2] == "freeze-once":
        marker = Path(sys.argv[1] + ".blocked")
        if not marker.exists():
            marker.touch()
            note("process.frozen", level="info")
            Event().wait(120)
            return
    state.set("AFTER · " + (entry.get() or "Button clicked"))
    root.configure(bg="#17633b")
    status.configure(bg="#17633b")
    note("ui.applied", level="info")


def fail():
    note("process.failed", level="error", code=17, diagnostic_detail="synthetic-private-value")
    os._exit(17)

tk.Button(root, text="Apply change", command=apply, font=("Arial", 16)).pack(pady=22)
root.lift()
root.attributes("-topmost", True)
root.update()
entry.focus_force()
Path(sys.argv[1]).touch()
note("ui.ready", level="info")
if len(sys.argv) == 3 and sys.argv[2] != "freeze-once":
    root.after(int(sys.argv[2]) * 1000, fail)
root.mainloop()

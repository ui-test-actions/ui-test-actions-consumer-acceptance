"""Live Tk-window transport fixture with a separate on-runner application observation."""

import json
import os
from pathlib import Path
import sys
import tkinter as tk


directory = Path(sys.argv[1])
root = tk.Tk()
root.title("UI transport verification")
root.geometry("560x350+60+60")
root.configure(bg="#192b42")
status = tk.Label(root, text="Ready for input", fg="white", bg="#192b42", font=("Arial", 22))
status.pack(pady=(35, 20))
entry = tk.Entry(root, width=30, font=("Arial", 18))
entry.pack(pady=8)
submitted = []


def apply():
    submitted.append(entry.get())
    (directory / "app-state.json").write_text(json.dumps(submitted, ensure_ascii=False), encoding="utf-8")
    status.configure(text="Applied · " + entry.get(), bg="#17633b")
    root.configure(bg="#17633b")


button = tk.Button(root, text="Apply", command=apply, font=("Arial", 16))
button.pack(pady=22)
root.lift()
root.attributes("-topmost", True)
root.update()
entry.focus_force()


def center(widget):
    return [widget.winfo_rootx() + widget.winfo_width() // 2,
            widget.winfo_rooty() + widget.winfo_height() // 2]


controls = directory / "controls.tmp"
controls.write_text(json.dumps({
    "entry": center(entry), "apply": center(button),
    "sample": [root.winfo_rootx() + 8, root.winfo_rooty() + 300],
    "crop": [root.winfo_rootx(), root.winfo_rooty(), root.winfo_rootx() + 560, root.winfo_rooty() + 350],
}), encoding="utf-8")
controls.replace(directory / "controls.json")
if exchange := os.environ.get("UI_TEST_EXCHANGE_DIR"):
    (Path(exchange) / "controls.json").write_bytes((directory / "controls.json").read_bytes())
root.mainloop()

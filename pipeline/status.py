"""Live training status: every stage of run.sh writes its part of one JSON
file, atomically (runs/progress.json, or $TARS_PROGRESS), for a dashboard to poll.

Stages run one after another, so read-modify-write needs no locking.

    python pipeline/status.py stage generating "Asking Claude for phrasings"
"""

from __future__ import annotations

import json
import os
import sys
import time

PATH = os.environ.get("TARS_PROGRESS", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "runs", "progress.json"))
LOG_LINES = 14


def read() -> dict:
    try:
        with open(PATH, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def write(d: dict) -> None:
    os.makedirs(os.path.dirname(PATH), exist_ok=True)
    d["updated"] = time.time()
    tmp = PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f)
    os.replace(tmp, PATH)


def update(section: str | None = None, **fields) -> None:
    d = read()
    if section:
        d.setdefault(section, {}).update(fields)
    else:
        d.update(fields)
    write(d)


def log(line: str) -> None:
    d = read()
    tail = d.get("log", [])[-(LOG_LINES - 1):]
    tail.append(f"{time.strftime('%H:%M:%S')}  {line}")
    d["log"] = tail
    write(d)


def stage(name: str, message: str = "") -> None:
    d = read()
    if name == "starting":
        d = {"run_id": time.strftime("%Y%m%d-%H%M%S"), "started": time.time(), "pid": os.getppid()}
    d["stage"] = name
    d["message"] = message
    d.setdefault("stage_times", {})[name] = time.time()
    write(d)
    log(f"— {name}{': ' + message if message else ''}")


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "stage":
        stage(sys.argv[2], " ".join(sys.argv[3:]))
    else:
        print(__doc__)

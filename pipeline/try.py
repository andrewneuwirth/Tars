"""Plan one sentence with several checkpoints and print what each decides, as JSON.
The Tars app's Model Lab calls this to compare a fine-tuned model with the base.

    python pipeline/try.py --catalog catalogs/example.json "open tunebox and play jazz" base candidate
    (a checkpoint is a folder, or "base" / "candidate" for the configured ones)
"""

from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tars.catalog import Catalog  # noqa: E402
from tars.config import BASE_CHECKPOINT, CHECKPOINT  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("said")
    ap.add_argument("checkpoints", nargs="*", default=["base", "candidate"])
    args = ap.parse_args()
    from tars.planner import Planner
    cat = Catalog.load(args.catalog)
    named = {"base": BASE_CHECKPOINT, "candidate": CHECKPOINT + "-candidate"}
    out = {}
    for name in args.checkpoints:
        path = named.get(name, name)
        if not os.path.exists(os.path.join(path, "option_marker.pt")):
            out[name] = {"error": f"no checkpoint at {path}"}
            continue
        planner = Planner(cat, path)
        planner.plan(args.said)  # warm-up, so the reported time is a steady-state plan
        out[name] = planner.plan(args.said)
    print(json.dumps(out))


if __name__ == "__main__":
    main()

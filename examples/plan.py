"""Plan a few sentences in-process.

    VON_REPO=../von TARS_CHECKPOINT=checkpoints/tars python examples/plan.py
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from tars import Catalog, Planner  # noqa: E402

planner = Planner(Catalog.load(os.path.join(os.path.dirname(__file__), "..", "catalogs", "example_catalog.json")))
for said in [
    "open apple music and go play oppenheimer move it to my right monitor",
    "lock in timer 25 minutes put on my study playlist dnd on",
    "whats due tomorrow and open the browser to put it on the left screen",
    "play Stop Making Sense",
]:
    plan = planner.plan(said)
    print(f"{plan['ms']:>6.0f} ms  {said}")
    for s in plan["steps"]:
        print(f"          → {s['text']!r:45} {s['family']:>9} / {s.get('skill')}  ({s['family_p']:.2f})")

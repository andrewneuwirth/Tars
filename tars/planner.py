"""Sentence → steps, each with a family and a skill.

    from tars import Catalog, Planner
    planner = Planner(Catalog.load("catalogs/example.json"))
    planner.plan("set a 20 minute timer play Stop Making Sense and throw it on my right monitor")
"""

from __future__ import annotations

import threading
import time

from . import questions as Q
from .catalog import Catalog
from .config import CHECKPOINT
from .model import load, predict


class Planner:
    def __init__(self, catalog: Catalog, checkpoint: str = CHECKPOINT, dev=None):
        self.catalog = catalog
        self.model, _ = load(checkpoint, dev)
        self.lock = threading.Lock()   # one pass on the GPU at a time

    def split(self, said: str) -> tuple[list[str], list[dict]]:
        words = said.split()
        cands = Q.split_candidates(words)
        cuts = []
        if cands:
            for i, (choice, p) in zip(cands, predict(self.model, [Q.split_row(words, i) for i in cands])):
                if choice == "new_step":
                    cuts.append({"at": i, "p": round(p, 3)})
        bounds = [0] + [c["at"] for c in cuts] + [len(words)]
        steps = [Q.strip_joiners(words[a:b]) for a, b in zip(bounds, bounds[1:])]
        return [s for s in steps if s], cuts

    def plan(self, said: str) -> dict:
        started = time.perf_counter()
        with self.lock:
            texts, cuts = self.split(said)
            steps = [{"text": t} for t in texts]
            rows = [Q.route_row(self.catalog, t, prev=texts[n - 1] if n else None,
                                sentence=said if len(texts) > 1 else None) for n, t in enumerate(texts)]
            for st, (fam, p) in zip(steps, predict(self.model, rows) if rows else []):
                st["family"], st["family_p"] = fam, round(p, 3)
            skill_rows, which = [], []
            for n, st in enumerate(steps):
                r = Q.skill_row(self.catalog, st["text"], st["family"], prev=texts[n - 1] if n else None)
                if r:
                    skill_rows.append(r)
                    which.append(st)
                elif st["family"] != "none":
                    only = next(iter(self.catalog.skills_in(st["family"])), None)
                    st["skill"], st["skill_p"] = only, 1.0
            for st, (sk, p) in zip(which, predict(self.model, skill_rows) if skill_rows else []):
                st["skill"], st["skill_p"] = sk, round(p, 3)
        return {"said": said, "steps": steps, "cuts": cuts, "ms": round((time.perf_counter() - started) * 1000, 1)}

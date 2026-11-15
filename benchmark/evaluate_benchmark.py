"""End-to-end benchmark: give a planner each sentence, compare its steps with the
gold steps. A sentence counts only if the number of steps, every step's family
and every step's skill all match (step text is compared loosely: same words
after dropping joiners and punctuation).

    python benchmark/evaluate_benchmark.py --catalog catalogs/mine.json --file my_benchmark.jsonl
    python benchmark/evaluate_benchmark.py --catalog ... --url http://127.0.0.1:8766/plan   # any HTTP planner

Any planner works if it returns {"steps": [{"text", "family", "skill"}]} for {"said": ...}.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.request
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from tars.catalog import Catalog  # noqa: E402

JOIN = {"and", "then", "go", "ahead", "to", "so", "also", "after", "that", "next", "plus"}


def words(s: str) -> list[str]:
    w = re.findall(r"[a-z0-9']+", s.lower())
    while w and w[0] in JOIN:
        w = w[1:]
    return w


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--file", required=True, help="jsonl of labeled sentences (see benchmark/README.md)")
    ap.add_argument("--url", help="POST endpoint of any planner; default: load Tars in-process")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--out", help="write per-sentence results here (jsonl)")
    args = ap.parse_args()
    cat = Catalog.load(args.catalog)
    items = [json.loads(l) for l in open(args.file)]
    if args.limit:
        items = items[:args.limit]
    if args.url:
        def plan(said):
            req = urllib.request.Request(args.url, json.dumps({"said": said}).encode(), {"Content-Type": "application/json"})
            return json.load(urllib.request.urlopen(req, timeout=30))
    else:
        from tars.planner import Planner
        plan = Planner(cat).plan

    tally, ms, out = Counter(), [], []
    for it in items:
        gold = [{"text": s["text"], "skill": s["skill"],
                 "family": cat.family_of(s["skill"]) if s["skill"] in cat.skills or s["skill"] == "none" else None}
                for s in it["steps"]]
        got = plan(it["said"])
        ms.append(got.get("ms", 0))
        steps = got["steps"]
        n_ok = len(steps) == len(gold)
        split_ok = n_ok and all(words(a["text"]) == words(g["text"]) for a, g in zip(steps, gold))
        fam_ok = n_ok and all(a.get("family") == g["family"] for a, g in zip(steps, gold))
        skill_ok = fam_ok and all(g["skill"] == "none" or a.get("skill") == g["skill"] for a, g in zip(steps, gold))
        tally.update(sentences=1, count=n_ok, split=split_ok, family=fam_ok, skill=skill_ok, full=skill_ok and split_ok)
        out.append({"said": it["said"], "gold": gold, "got": steps, "ok": skill_ok and split_ok})
    n = tally["sentences"]
    pct = lambda k: round(100 * tally[k] / n, 1)  # noqa: E731
    ms.sort()
    print(json.dumps({"sentences": n, "step_count": pct("count"), "split_exact": pct("split"),
                      "families": pct("family"), "skills": pct("skill"), "end_to_end": pct("full"),
                      "median_ms": ms[len(ms) // 2] if ms else None}, indent=2))
    if args.out:
        with open(args.out, "w") as f:
            f.writelines(json.dumps(r) + "\n" for r in out)


if __name__ == "__main__":
    main()

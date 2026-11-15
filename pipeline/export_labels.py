"""Turn generate.py's raw output into two label files (build.py --labels format):
the training labels and a held-out benchmark that never overlaps them.

  training   single + confuse + multi requests          -> --train (set "train")
  benchmark  multi_h requests (held-out styles), 2+ steps -> --bench (set "test")

Every label is checked against the catalog (known skill keys, step texts found in
order inside "said"), deduplicated, and dropped if it looks personal. A training
sentence that is a near-copy (>= 80% word overlap) of a benchmark sentence is
dropped, so the benchmark stays clean.

    python pipeline/export_labels.py --catalog catalogs/example.json \
        --train labels/example.jsonl --bench benchmark/public/benchmark.jsonl
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
from build import RAW, Builder, norm  # noqa: E402
from common import read_jsonl  # noqa: E402
from tars.catalog import Catalog  # noqa: E402

# Anything that could be a real person's details rather than made-up example speech.
PERSONAL = re.compile(r"andrew|neuwirth|\bdrew\b|@|https?://|\.com\b|gmail|\b\d{3}[-. ]\d{3}[-. ]\d{4}\b", re.I)


def near(a: list[str], b: list[str]) -> bool:
    m = difflib.SequenceMatcher(None, a, b, autojunk=False)
    return m.real_quick_ratio() >= 0.8 and m.quick_ratio() >= 0.8 and m.ratio() >= 0.8


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--train", required=True)
    ap.add_argument("--bench", required=True)
    args = ap.parse_args()
    b = Builder(Catalog.load(args.catalog), random.Random(0))
    dropped: dict[str, int] = {}

    def clean(items: list[dict], kind: str) -> list[dict]:
        out = []
        for it in items:
            said = " ".join(str(it.get("said", "")).split())
            steps = it.get("steps") or [{"text": said, "skill": it.get("skill") or it["job"].split("-", 1)[1]}]
            steps = [{"text": " ".join(str(s.get("text", "")).split()), "skill": b.fix_skill(s.get("skill"))} for s in steps]
            why = ("personal" if PERSONAL.search(said) else
                   "unknown skill" if any(s["skill"] is None for s in steps) else
                   "steps not in sentence" if not said or b.locate(said, steps) is None else
                   "single step" if kind == "multi_h" and len(steps) < 2 else None)
            if why:
                dropped[why] = dropped.get(why, 0) + 1
                continue
            out.append({"said": said, "steps": steps, "style": it.get("style", ""), "from": kind})
        return out

    seen: set[str] = set()

    def dedupe(items: list[dict]) -> list[dict]:
        out = []
        for it in items:
            k = norm(it["said"])
            if k in seen:
                dropped["duplicate"] = dropped.get("duplicate", 0) + 1
                continue
            seen.add(k)
            out.append(it)
        return out

    bench = dedupe(clean(read_jsonl(os.path.join(RAW, "multi_h.jsonl")), "multi_h"))
    train = dedupe([it for kind in ("single", "confuse", "multi") for it in clean(read_jsonl(os.path.join(RAW, f"{kind}.jsonl")), kind)])
    bwords = [norm(it["said"]).split() for it in bench]
    kept = []
    for it in train:
        w = norm(it["said"]).split()
        if any(near(bw, w) for bw in bwords):
            dropped["near-copy of a benchmark sentence"] = dropped.get("near-copy of a benchmark sentence", 0) + 1
            continue
        kept.append(it)
    for path, items, s in ((args.train, kept, "train"), (args.bench, bench, "test")):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(json.dumps(dict(it, set=s)) + "\n" for it in items)
    print(json.dumps({"train": len(kept), "benchmark": len(bench), "dropped": dropped}, indent=1))


if __name__ == "__main__":
    assert near("open the browser and play jazz".split(), "open the browser and play some jazz".split())
    assert not near("set a timer".split(), "play jazz in tunebox now".split())
    main()

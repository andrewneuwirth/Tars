"""Score checkpoints per question and per whole sentence (every split, route and
skill of a sentence right), and decide whether a candidate should replace the base.

    python pipeline/evaluate.py baseline                 # the base model only
    python pipeline/evaluate.py compare [candidate_dir]  # base vs candidate + verdict

Verdict PROMOTE needs: whole-sentence gains on test_real (if present) and
test_hard, and general reasoning (val_replay) down by no more than 2 points.
"""

from __future__ import annotations

import json
import os
import sys
import time
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import status  # noqa: E402
from common import read_jsonl  # noqa: E402
from tars.config import BASE_CHECKPOINT, CHECKPOINT  # noqa: E402
from tars.model import load, predict  # noqa: E402

DATA = os.environ.get("TARS_DATA", os.path.join(HERE, "..", "data"))
SETS = ["test_real", "test_hard", "test_style", "val_replay"]


def score(ckpt: str) -> dict:
    model, _ = load(ckpt)
    out = {}
    for name in SETS:
        rows = read_jsonl(os.path.join(DATA, f"{name}.jsonl"))
        if not rows:
            continue
        by_kind, by_sid = defaultdict(lambda: [0, 0]), defaultdict(lambda: True)
        t0 = time.perf_counter()
        preds = predict(model, rows)
        ms = (time.perf_counter() - t0) * 1000 / len(rows)
        for r, (pid, _) in zip(rows, preds):
            ok = pid == r["label"]
            k = r.get("kind", "general")
            by_kind[k][0] += ok
            by_kind[k][1] += 1
            if "sid" in r:
                by_sid[r["sid"]] &= ok
        res = {k: round(100 * a / n, 1) for k, (a, n) in by_kind.items()}
        res["all"] = round(100 * sum(a for a, _ in by_kind.values()) / sum(n for _, n in by_kind.values()), 1)
        res["n"] = len(rows)
        res["ms_per_question"] = round(ms, 1)  # batched, so a lower bound on one live question
        if by_sid:
            res["sentence"] = round(100 * sum(by_sid.values()) / len(by_sid), 1)
            res["sentences"] = len(by_sid)
        out[name] = res
        print(f"  {name:11s} {json.dumps(res)}", flush=True)
    return out


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else "compare"
    candidate = sys.argv[2] if len(sys.argv) > 2 else CHECKPOINT + "-candidate"
    path = os.path.join(DATA, "eval_report.json")
    report = json.load(open(path)) if os.path.exists(path) else {}
    print(f"base ({BASE_CHECKPOINT}):")
    report["base"] = base = score(BASE_CHECKPOINT)
    if mode == "compare":
        print(f"candidate ({candidate}):")
        report["candidate"] = cand = score(candidate)
        ok, reasons = True, []
        for name, label in (("test_real", "your sentences"), ("test_hard", "hard multi-step")):
            if name in base:
                b, c = base[name]["sentence"], cand[name]["sentence"]
                reasons.append(f"{label} {b}% → {c}%")
                ok &= c > b
        drop = base["val_replay"]["all"] - cand["val_replay"]["all"]
        if drop > 2:
            ok = False
            reasons.append(f"general reasoning dropped {drop:.1f} points")
        report["verdict"], report["reasons"] = ("PROMOTE" if ok else "KEEP"), reasons
        status.update("eval", verdict=report["verdict"], reasons=reasons)
        print("VERDICT:", report["verdict"], "·", "; ".join(reasons))
    json.dump(report, open(path, "w"), indent=2)


if __name__ == "__main__":
    main()

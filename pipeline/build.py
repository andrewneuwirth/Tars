"""Turn generated data into model rows for the three questions (split, route,
skill), built by tars/questions.py exactly as the planner asks them live.

Splits (by sentence, nothing crosses): train / val (6%) from single+confuse+multi;
test_style (held-out styles, single steps); test_hard (multi-step, held-out styles,
separate requests); test_real (your own sentences, if generated with --real).
Every row carries `sid` so evaluate.py can score whole sentences.

Replay keeps the base model's general reasoning (Von's synthetic decisions) and,
optionally, rows from an earlier task (--replay file.jsonl) so fine-tuning on
routing doesn't erase what the model already did well.

    python pipeline/build.py --catalog catalogs/example.json
    python pipeline/build.py --catalog mine.json --labels labels.jsonl   # labels from the Tars app or any agent

A --labels file has one sentence per line: {"said": "...", "steps": [{"text": "...", "skill": "<key or none>"}],
"set": "train" | "test" | "real"} (set defaults to train). Step texts are exact substrings of "said".
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import random
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import status  # noqa: E402
from common import read_jsonl  # noqa: E402
from tars import questions as Q  # noqa: E402
from tars.catalog import Catalog  # noqa: E402
from tars.config import use_von  # noqa: E402

DATA = os.environ.get("TARS_DATA", os.path.join(HERE, "..", "data"))
RAW = os.path.join(DATA, "raw")
FILLERS = ["um", "uh", "like", "okay", "so", "wait"]
VERBISH = {"open", "close", "play", "move", "put", "send", "search", "set", "start", "stop", "turn", "text", "call",
           "make", "show", "hide", "find", "look", "pause", "skip", "take", "switch", "click", "press", "go", "minimize",
           "maximize", "quit", "launch", "what", "whats", "how", "when", "is", "remind", "note", "throw", "mute"}


def norm(s: str) -> str:
    return " ".join(re.findall(r"[a-z0-9']+", s.lower()))


def asr_noise(s: str, rng: random.Random) -> str:
    """What a speech recognizer does to real speech."""
    words = s.split()
    if rng.random() < 0.6:
        words = [w for w in (re.sub(r"[^\w'-]", "", w) for w in words) if w]
    if rng.random() < 0.5:
        words = [w.lower() for w in words]
    if len(words) > 3 and rng.random() < 0.3:
        del words[rng.randrange(len(words))]
    if rng.random() < 0.3:
        words.insert(rng.randrange(len(words) + 1), rng.choice(FILLERS))
    return " ".join(words) or s


class Builder:
    def __init__(self, cat: Catalog, rng: random.Random):
        self.cat, self.rng = cat, rng
        self.keys = list(cat.skills)

    def fix_skill(self, k: str | None) -> str | None:
        if not k:
            return None
        k = k.strip().lower()
        if k in ("none", "chatter", "not_a_command"):
            return "none"
        if k in self.cat.skills:
            return k
        m = difflib.get_close_matches(k, self.keys, n=1, cutoff=0.8)
        return m[0] if m else None

    def shuffled(self, row: dict | None, **meta) -> dict | None:
        if row is None:
            return None
        self.rng.shuffle(row["options"])
        row.update(meta)
        return row

    def locate(self, said: str, steps: list[dict]) -> list[int] | None:
        low, starts, pos = said.lower(), [], 0
        for st in steps:
            t = st["text"].strip().lower()
            i = low.find(t, pos) if t else -1
            if i < 0:
                i = low.find(" ".join(t.split()[:2]), pos) if t else -1
                if i < 0:
                    return None
            starts.append(len(low[:i].split()))
            pos = i + len(t)
        return starts if len(set(starts)) == len(starts) else None

    def split_rows(self, said: str, starts: list[int], max_neg: int = 3, **meta) -> list[dict]:
        words = said.split()
        clean = [Q.clean_word(w) for w in words]
        pos, neg = [], []
        for i in Q.split_candidates(words):
            j = i
            while j < len(words) and clean[j] in Q.JOINERS and j not in starts:
                j += 1
            is_new = j in starts and j > 0
            row = Q.split_row(words, i, "new_step" if is_new else "same_step")
            row.update(meta, source="tars")
            (pos if is_new else neg).append(row)
        self.rng.shuffle(neg)
        neg.sort(key=lambda r: 0 if clean[r["at"]] in Q.JOINERS or clean[r["at"]] in VERBISH else 1)
        return pos + neg[:max_neg]

    def sentence(self, item: dict, sid: str, meta: dict) -> list[dict]:
        said = item["said"].strip()
        steps = [dict(s, skill=self.fix_skill(s.get("skill"))) for s in item.get("steps", [])]
        if not steps or any(s["skill"] is None for s in steps):
            return []
        starts = self.locate(said, steps)
        if starts is None:
            return []
        rows = []
        if len(steps) > 1 or self.rng.random() < 0.5:
            rows += self.split_rows(said, starts, sid=sid, **meta)
        prev = None
        for s in steps:
            fam = self.cat.family_of(s["skill"])
            rows.append(self.shuffled(Q.route_row(self.cat, s["text"], fam, prev=prev, sentence=said), sid=sid,
                                      source="tars", **meta))
            if s["skill"] != "none" and (r := self.shuffled(Q.skill_row(self.cat, s["text"], fam, s["skill"], prev=prev),
                                                            sid=sid, source="tars", **meta)):
                rows.append(r)
            prev = s["text"]
        return rows

    def single(self, item: dict, sid: str, meta: dict) -> list[dict]:
        sk = self.fix_skill(item.get("skill") or item.get("_skill"))
        if sk is None:
            return []
        fam = self.cat.family_of(sk)
        rows = [self.shuffled(Q.route_row(self.cat, item["said"], fam), sid=sid, source="tars", **meta)]
        if sk != "none" and (r := self.shuffled(Q.skill_row(self.cat, item["said"], fam, sk), sid=sid, source="tars", **meta)):
            rows.append(r)
        return rows


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--val-frac", type=float, default=0.06)
    ap.add_argument("--noise-frac", type=float, default=0.4)
    ap.add_argument("--general", type=int, default=6000, help="general reasoning rows replayed (Von's generator)")
    ap.add_argument("--replay", action="append", default=[], help="jsonl of earlier-task rows to keep (repeatable)")
    ap.add_argument("--replay-rows", type=int, default=7000)
    ap.add_argument("--seed", type=int, default=4)
    ap.add_argument("--labels", help="jsonl of labeled sentences (see the docstring); used with or alongside data/raw")
    args = ap.parse_args()
    rng = random.Random(args.seed)
    cat = Catalog.load(args.catalog)
    b = Builder(cat, rng)
    labels = read_jsonl(args.labels) if args.labels else []

    def read(kind: str) -> list[dict]:
        rows = read_jsonl(os.path.join(RAW, f"{kind}.jsonl"))
        for it in labels:  # test -> test_hard, real -> test_real, train -> single-step "confuse" (gets ASR noise) or multi
            s = it.get("set", "train")
            k = {"test": "multi_h", "real": "real"}.get(s, "multi" if len(it.get("steps", [])) > 1 else "confuse")
            if k == kind:
                rows.append(it)
        return rows

    def with_skill(items):
        for it in items:
            it["_skill"] = it["job"].split("-", 1)[1]
        return items

    real, held, multi_h = read("real"), with_skill(read("held")), read("multi_h")
    seen = {norm(r["said"]) for r in real + held + multi_h}

    def fresh(items):
        out = []
        for it in items:
            k = norm(it["said"])
            if k and k not in seen:
                seen.add(k)
                out.append(it)
        return out

    pool = ([("single", it) for it in fresh(with_skill(read("single")))] + [("confuse", it) for it in fresh(read("confuse"))]
            + [("multi", it) for it in fresh(read("multi"))])
    rng.shuffle(pool)
    n_val = int(len(pool) * args.val_frac)

    def rows_for(kind, it, sid, meta):
        return b.sentence(it, sid, meta) if "steps" in it else b.single(it, sid, meta)

    train, val = [], []
    for n, (kind, it) in enumerate(pool[n_val:]):
        train += rows_for(kind, it, f"t{n}", {"from": kind})
        if kind != "multi" and rng.random() < args.noise_frac:
            train += rows_for(kind, dict(it, said=asr_noise(it["said"], rng)), f"t{n}n", {"from": kind, "asr": True})
    for n, (kind, it) in enumerate(pool[:n_val]):
        val += rows_for(kind, it, f"v{n}", {"from": kind})
    test_style = [r for n, it in enumerate(held) for r in b.single(it, f"s{n}", {"from": "held"})]
    test_hard = [r for n, it in enumerate(multi_h) for r in b.sentence(it, f"h{n}", {"from": "multi_h"})]
    test_real = [r for n, it in enumerate(real) for r in b.sentence(it, f"r{n}", {"from": "real"})]

    use_von()
    from training.generate_synthetic_decisions import generate as general_gen  # Von's
    general = general_gen(args.general + 600, seed=args.seed + 11)
    for r in general:
        r.update(source="replay", kind="general")
    val_replay, replay = general[:600], general[600:]
    for path in args.replay:
        extra = read_jsonl(path)
        rng.shuffle(extra)
        replay += [dict(r, kind=r.get("kind", "command")) for r in extra[:args.replay_rows]]

    all_train = train + replay
    rng.shuffle(all_train)
    os.makedirs(DATA, exist_ok=True)

    def write(name, rows):
        with open(os.path.join(DATA, name), "w", encoding="utf-8") as f:
            f.writelines(json.dumps(r) + "\n" for r in rows)

    for name, rows in [("train", all_train), ("val", val), ("val_replay", val_replay), ("test_style", test_style),
                       ("test_hard", test_hard), ("test_real", test_real)]:
        write(f"{name}.jsonl", rows)
        print(f"  {name:11s} {len(rows):6,} rows {dict(Counter(r.get('kind') for r in rows))}")
    fams = Counter(r["label"] for r in train if r["kind"] == "route")
    print("route labels:", dict(fams.most_common()))
    status.update("build", train=len(all_train), tars=len(train), replay=len(replay), val=len(val),
                  test_style=len(test_style), test_real=len(test_real), per_command=dict(fams.most_common()))


if __name__ == "__main__":
    main()

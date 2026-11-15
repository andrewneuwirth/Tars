"""Generate hard training data for a skill catalog with Claude (headless
`claude -p`, no tools: text in, text out). Diversity and difficulty are the
point: today's model should score well under 90% on what this produces.

Kinds of requests:
  single   one skill, messy real speech (training styles)           -> train/val
  held     one skill, 3 held-out speaking styles                    -> test_style
  multi    2-4 step sentences across families, adversarial          -> train/val
  multi_h  same, held-out styles, separate requests                 -> test_hard
  confuse  near-miss pairs across families + not-a-command talk     -> train/val
  real     your own logged sentences (--real file), labeled         -> test_real

Output: data/raw/<kind>.jsonl. Resumable: finished requests are skipped.

    python pipeline/generate.py --catalog catalogs/example.json --workers 6
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import hashlib
import json
import os
import random
import re
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import status  # noqa: E402
from tars.catalog import Catalog  # noqa: E402

RAW = os.path.join(os.environ.get("TARS_DATA", os.path.join(HERE, "..", "data")), "raw")
CLAUDE = os.environ.get("CLAUDE_BIN", os.path.expanduser("~/.local/bin/claude"))
# How people actually talk to a computer. The last 3 are held out of training.
STYLES = [
    "short and blunt, 1-4 words, like barking an order",
    "polite and complete, with please or could you",
    "casual college student slang and filler (like, um, lowkey, bro, ngl)",
    "indirect: describe the goal or the problem instead of naming the action",
    "mid-thought, starting with 'okay so' or 'wait' or 'alright', trailing off a little",
    "referring to the thing vaguely: this, that, it, the thing, over there, this one",
    "naming a specific app or window",
    "questions phrased as requests: can you, could we, is there a way to",
    "impatient or annoyed, repeating a word, 'just' and 'already'",
    "very long rambly sentence with the request buried in the middle",
    "speech-to-text errors: dropped words, homophones, no punctuation, run-on",
    "non-native English speaker, simple grammar, slightly wrong word choices",
    "tired late-night mumbling, lowercase, abbreviated",
    # held out:
    "formal and precise, like dictating instructions to an assistant",
    "gamer / streamer talk, fast and hype",
    "a parent who isn't technical, describing things by what they look like",
]
HELD_OUT_STYLES = set(STYLES[-3:])
CAT: Catalog = None  # set in main()
FAMILIES: dict = {}
SKILLS: dict = {}
TRAIN_STYLES = [s for s in STYLES if s not in HELD_OUT_STYLES]
HELD = [s for s in STYLES if s in HELD_OUT_STYLES]





def skill_list(keys: list[str] | None = None) -> str:
    return "\n".join(f"- {k} ({s['family']}): {s['name']}. e.g. {'; '.join(s['examples'][:3])}"
                     for k, s in SKILLS.items() if keys is None or k in keys)


def ask(prompt: str) -> str:
    r = subprocess.run([CLAUDE, "-p", "--tools", "", "--strict-mcp-config", "--no-session-persistence"], input=prompt, capture_output=True,
                       text=True, timeout=600)
    if r.returncode != 0:
        raise RuntimeError(r.stderr[-400:])
    return r.stdout


def parse_array(text: str) -> list:
    m = re.search(r"\[.*\]", text, re.S)
    if not m:
        raise ValueError("no JSON array in reply")
    return json.loads(m.group(0))


# --- request builders ---------------------------------------------------------------

def single_prompt(key: str, styles: list[str], n: int) -> str:
    s = SKILLS[key]
    others = [k for k in SKILLS if SKILLS[k]["family"] != s["family"]]
    return f"""{CAT.context}

Write {n} different things the user might say that should be handled by this one skill:
  {key}: {s['name']} (family: {s['family']}). Known examples: {'; '.join(s['examples'])}

Make them HARD and realistic, not textbook:
- spread them across these speaking styles: {' | '.join(styles)}
- vary vocabulary heavily; avoid the words in the known examples for at least half
- include indirect goals ("it's way too loud" instead of "volume down"), vague references (this, that, it),
  filler, self-corrections ("open, no wait, close"), and a few with speech-to-text mistakes
- about a fifth should contain a word that belongs to a DIFFERENT skill but still mean this one
  (e.g. "move my 3pm meeting" is calendar, not windows; "play the next tab" is not music)
Only one action per sentence.
Return ONLY a JSON array of objects: {{"said": "...", "style": "<one of the styles above, copied exactly>"}}"""


def multi_prompt(seed_keys: list[str], styles: list[str], n: int) -> str:
    return f"""{CAT.context}

Write {n} sentences where the user asks for 2 to 4 things in ONE breath, across different apps/skills.
Draw steps from any of these skills (use each seed skill at least once across the set):
{skill_list(seed_keys)}
and also freely from the rest of Tars:
{skill_list()}

Make the sentences hard to split into steps, the way people really talk:
- joiners vary: "and", "and then", "then", commas, NOTHING at all ("open the browser move it to the left"),
  "and go", "go ahead and", "to" used as "and" ("open music to play oppenheimer")
- later steps refer back: it, that, this window, them, the song
- names and queries that contain command words must stay inside their step:
  "play Stop Making Sense", "search how to close a tab", "text mom I'll open the door",
  "play Move Along then put it on the right screen"
- mix families: a timer + music + window move; a question + an action; a text + a search
- some steps are questions ("am I free at 4 and open the calendar")
- speaking styles to spread across: {' | '.join(styles)}
For each sentence give the exact step texts as substrings of "said" (in order, without the joiner words),
and each step's skill key from the list above (or "none" if a part is just chatter).
Return ONLY a JSON array: {{"said": "...", "style": "<style>", "steps": [{{"text": "...", "skill": "<key>"}}]}}"""


def confuse_prompt(pairs: list[tuple[str, str]], n: int) -> str:
    lines = "\n".join(f"- {a} vs {b}" for a, b in pairs)
    return f"""{CAT.context}

Write {n} short commands that sit right on the line between two Tars skills that are easy to confuse.
Pairs to cover (roughly equal numbers, both directions):
{lines}
Also include about a sixth that are NOT commands at all (skill "none"): the user talking to a friend
or on the phone, reading something aloud, thinking out loud, saying "never mind", mentioning apps
without asking for anything ("the browser was so slow today", "i left my laptop on the right").
All skills, for reference:
{skill_list()}
Return ONLY a JSON array: {{"said": "...", "skill": "<key or none>", "style": "confusable"}}"""


def real_prompt(sentences: list[str]) -> str:
    listing = "\n".join(f"{i}. {s}" for i, s in enumerate(sentences))
    return f"""{CAT.context}

These are real sentences the user said to the assistant (speech-to-text output). Label each: split it into steps
(exact substrings, without joiner words), and give each step its skill key, or "none" if it's chatter
or not a request. Be faithful to what they most likely meant.
Skills:
{skill_list()}
Sentences:
{listing}
Return ONLY a JSON array, one object per sentence in order:
{{"i": <index>, "said": "...", "steps": [{{"text": "...", "skill": "<key or none>"}}]}}"""


# --- plan -------------------------------------------------------------------------------

def plan(rng: random.Random, real_path: str | None = None) -> list[dict]:
    jobs = []
    keys = list(SKILLS)
    for k in keys:
        jobs.append({"kind": "single", "id": f"single-{k}", "prompt": single_prompt(k, rng.sample(TRAIN_STYLES, 5), 30)})
        jobs.append({"kind": "held", "id": f"held-{k}", "prompt": single_prompt(k, HELD, 6)})
    fams = sorted({s["family"] for s in SKILLS.values()})
    for i in range(110):
        seeds = rng.sample(keys, 5)
        jobs.append({"kind": "multi", "id": f"multi-{i}", "prompt": multi_prompt(seeds, rng.sample(TRAIN_STYLES, 4), 25)})
    for i in range(24):
        seeds = rng.sample(keys, 5)
        jobs.append({"kind": "multi_h", "id": f"multih-{i}", "prompt": multi_prompt(seeds, HELD, 20)})
    pairs = []
    for _ in range(300):
        a, b = rng.sample(keys, 2)
        if SKILLS[a]["family"] != SKILLS[b]["family"] or rng.random() < 0.3:
            pairs.append((a, b))
    for i in range(0, 240, 8):
        jobs.append({"kind": "confuse", "id": f"confuse-{i}", "prompt": confuse_prompt(pairs[i:i + 8], 30)})
    real = [l.strip() for l in open(real_path) if l.strip()] if real_path else []
    for i in range(0, len(real), 25):
        jobs.append({"kind": "real", "id": f"real-{i}", "prompt": real_prompt(real[i:i + 25])})
    return jobs


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--real", help="optional: a text file of your own logged sentences, one per line (test_real)")
    ap.add_argument("--workers", type=int, default=5)
    ap.add_argument("--only", default="", help="comma list of kinds")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()
    global CAT, FAMILIES, SKILLS
    CAT = Catalog.load(args.catalog)
    FAMILIES, SKILLS = CAT.families, CAT.skills
    os.makedirs(RAW, exist_ok=True)
    jobs = plan(random.Random(4), args.real)
    if args.only:
        jobs = [j for j in jobs if j["kind"] in args.only.split(",")]
    done_ids = set()
    for f in os.listdir(RAW):
        if f.endswith(".jsonl"):
            done_ids |= {json.loads(l)["job"] for l in open(os.path.join(RAW, f)) if l.strip()}
    todo = [j for j in jobs if j["id"] not in done_ids]
    if args.limit:
        todo = todo[:args.limit]
    lock = threading.Lock()
    finished = [len(jobs) - len(todo)]
    t0 = time.time()
    status.update("generate", total=len(jobs), done=finished[0], lines=0)

    def run(job):
        for attempt in range(3):
            try:
                items = parse_array(ask(job["prompt"]))
                break
            except Exception as e:  # noqa: BLE001
                if attempt == 2:
                    print(f"  {job['id']} failed: {e}", flush=True)
                    return
                time.sleep(5)
        with lock:
            with open(os.path.join(RAW, f"{job['kind']}.jsonl"), "a", encoding="utf-8") as f:
                for it in items:
                    it["job"] = job["id"]
                    f.write(json.dumps(it) + "\n")
            finished[0] += 1
            rate = (time.time() - t0) / max(1, finished[0] - (len(jobs) - len(todo)))
            eta = rate * (len(jobs) - finished[0]) / 60
            status.update("generate", total=len(jobs), done=finished[0], eta_min=round(eta, 1))
            print(f"  [{finished[0]}/{len(jobs)}] {job['id']}: {len(items)} items, eta {eta:.0f} min", flush=True)

    with cf.ThreadPoolExecutor(args.workers) as ex:
        list(ex.map(run, todo))


if __name__ == "__main__":
    main()

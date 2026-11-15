# Benchmark script

`evaluate_benchmark.py` scores any planner end to end on a file of multi-step commands. A sentence counts only if
the number of steps, every step's words, family and skill all match.

The file has one sentence per line, labeled with your catalog's skill keys:

```json
{"said": "set a timer for 10 minutes and play some jazz", "steps": [{"text": "set a timer for 10 minutes", "skill": "timers"}, {"text": "play some jazz", "skill": "play_music"}]}
```

    python benchmark/evaluate_benchmark.py --catalog catalogs/mine.json --file my_benchmark.jsonl
    python benchmark/evaluate_benchmark.py --catalog catalogs/mine.json --file my_benchmark.jsonl --url http://127.0.0.1:8766/plan

Any planner works if it returns `{"steps": [{"text", "family", "skill"}]}` for `{"said": ...}`.

The 480-sentence benchmark behind the numbers in the main README is not released: it was written for one person's
catalog and names their own apps. Write yours the same way: separate requests from your training labels, held-out
speaking styles, and a check for near-copies of training sentences.

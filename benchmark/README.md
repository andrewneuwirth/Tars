# Benchmark

## The public benchmark

[`public/benchmark.jsonl`](public/benchmark.jsonl) has 477 hard multi-step commands for the example catalog
([`catalogs/example.json`](../catalogs/example.json)), each asking for 2 to 5 things in one breath. It is the
benchmark behind the Tars 0.5 numbers in the main README and in the model card.

| | |
|---|---|
| Sentences | 477 (127 with 2 steps, 272 with 3, 72 with 4, 6 with 5) |
| Steps | 1,388, covering all 31 skills plus 79 `none` steps (chatter inside a command) |
| Speaking styles | formal dictation, gamer or streamer talk, and a non-technical parent describing things by how they look. None of the three is used in the training labels |
| Written by | Anthropic's Claude through `pipeline/generate.py` (the `multi_h` requests: 24 separate requests of 20 sentences each) |
| Checked | Every skill key is in the catalog, every step text is found in order inside `said`, single-step and duplicate sentences removed |
| Near-copies | None. Any training sentence with 80% or more word overlap with a benchmark sentence was removed from the training labels (254 removed) |

Each line is one sentence in the `pipeline/build.py --labels` format, with `"set": "test"` so the build step keeps
it out of training:

```json
{"said": "play Stop Making Sense in Tunebox, then tell me how much time is left on my timer", "steps": [{"text": "play Stop Making Sense in Tunebox", "skill": "play_music"}, {"text": "tell me how much time is left on my timer", "skill": "timers"}], "style": "formal and precise, like dictating instructions to an assistant", "from": "multi_h", "set": "test"}
```

Never train on it. The training labels it was checked against are [`labels/example.jsonl`](../labels/example.jsonl).

To score a checkpoint:

```bash
TARS_CHECKPOINT=path/to/checkpoint python benchmark/evaluate_benchmark.py \
    --catalog catalogs/example.json --file benchmark/public/benchmark.jsonl
```

The labels were written by an LLM, so a few are debatable (for example two `tip_split` steps for "a 20 percent tip
then split it four ways"). They are kept as written so the numbers stay comparable.

## The script

`evaluate_benchmark.py` scores any planner end to end on a file of multi-step commands. A sentence counts only if
the number of steps, every step's words, family and skill all match. It reports:

| Field | Meaning |
|---|---|
| `step_count` | the right number of steps |
| `split_exact` | the right number of steps, each with the right words |
| `families` | every step routed to the right family |
| `skills` | every step's family and skill right |
| `end_to_end` | words, family and skill right for every step |
| `median_ms` | median time to plan one whole sentence |

The file has one sentence per line, labeled with your catalog's skill keys:

```json
{"said": "set a timer for 10 minutes and play some jazz", "steps": [{"text": "set a timer for 10 minutes", "skill": "timers"}, {"text": "play some jazz", "skill": "play_music"}]}
```

    python benchmark/evaluate_benchmark.py --catalog catalogs/mine.json --file my_benchmark.jsonl
    python benchmark/evaluate_benchmark.py --catalog catalogs/mine.json --file my_benchmark.jsonl --url http://127.0.0.1:8766/plan

Any planner works if it returns `{"steps": [{"text", "family", "skill"}]}` for `{"said": ...}`.

For your own catalog, write a benchmark the same way: requests separate from your training labels, held-out
speaking styles, and a check for near-copies of training sentences (`pipeline/export_labels.py` does all three).

Tars 0.4's numbers came from a private 480-sentence benchmark written for one person's catalog. It is not in this
repository.

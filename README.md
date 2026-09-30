# Tars

**A small, local planner for voice assistants.** Tars takes one spoken sentence, splits it
into steps, routes each step to the right part of the assistant, and picks the skill. It
runs offline on a laptop in a few hundred milliseconds.

```
"lock in timer 25 minutes put on my study playlist dnd on"

  → "lock in timer 25 minutes"  time   / timers               0.99
  → "put on my study playlist"  media  / play_music_by_name   1.00
  → "dnd on"                    mac    / do_not_disturb       0.94
```

Tars is a full fine-tune of [**Von**](https://github.com/wfzyx/von) (Victor Hugo), a
395M-parameter ModernBERT *option-marker* decision model. It keeps Von's approach: no text
generation, only a calibrated choice among options you supply. It adds three questions that
a voice assistant needs answered before it can act.

| Question | Asked | Options |
|---|---|---|
| **Split**: does a new request start at `‖`? | at each candidate word | `new_step` / `same_step` |
| **Route**: which part of the assistant handles this step? | once per step | your catalog's families (+ `none`) |
| **Skill**: which skill within that family? | once per step | that family's skills |

Your skills are data, not code. Describe them in a catalog JSON (families, skills, a few
examples each), and the planner and the training pipeline both read it. The
[example catalog](catalogs/example_catalog.json) has 14 families and 103 skills from a
real macOS assistant.

---

## Results

### Public benchmark: hard multi-step commands

480 sentences that each ask for 2–4 things in one breath
([`benchmark/`](benchmark/README.md)). They were written to be hard:
- no joiners ("open claude move it to the left")
- "and go" or "to" used in place of "and"
- back-references ("move it", "that song")
- titles and queries that contain command words ("play Stop Making Sense")
- questions mixed with actions
- three speaking styles held out of training entirely

A sentence counts as correct only if **every** step's boundary, family and skill is right.
Tars has to do the splitting itself.

| Model | End to end | Clean subset* | Step count right | Split exact | Median latency |
|---|---|---|---|---|---|
| Von 1.2 (base, no fine-tune) | 0.0% | 0.0% | 1.9% | 0.0% | 759 ms |
| **Tars 0.4** | **65.0%** | **61.2%** | **76.9%** | **74.6%** | **352 ms** |

\* 75 of the 480 sentences have a near-copy (≥80% word overlap) in Tars's training data
([`benchmark/near_copies.json`](benchmark/near_copies.json)). The clean subset leaves them
out and is the number to quote.

Latency is the whole plan (every split, route and skill question), measured in-process on
an Apple M5 Pro (MPS). Single-step commands take about 130–230 ms.

### Private evaluation: one user's real commands

The author's own logged voice commands (178 sentences, not released) are the test that
matters most. They were never in training. Here, every question is scored given the
correct step boundaries.

| | Von 1.2 → Tars 0.4 |
|---|---|
| Whole sentence right (every split, route, skill) | 18.0% → **68.0%** |
| Split decisions | 39.3% → **99.3%** |
| Route (family) | 41.9% → **80.3%** |
| Skill | 85.4% → **91.7%** |
| Held-out speaking styles, single steps (620) | 10.2% → **74.8%** |
| General reasoning (Von's replay set, must not drop) | 93.2% → 92.7% |

### What it still gets wrong

- **Apps versus websites.** "Open Apple Music" is routed to *web* (0.80), and "Google Chrome"
  said alone goes to *web* instead of *apps & windows*. The family descriptions overlap; this
  is the main target for the next round.
- **Chit-chat.** "How are you" and "let's close out" get routed to a skill instead of `none`.
- **A back-reference after a media step.** In "…play Stop Making Sense and throw it on my
  right monitor", the second step goes to *sound output* rather than *move window*.
- **Weak splits without cues.** Missing splits on "lock in", and splitting inside conditional
  requests ("am I free at 4 **and if so** add…").

---

## Quick start

Tars reuses Von's model class and training utilities, so you need a Von checkout next to
this repo.

```bash
git clone https://github.com/wfzyx/von ../von        # base model + utilities
cd ../von && uv sync && cd -                          # (see Von's README for weights)
export VON_REPO=../von
export TARS_CHECKPOINT=checkpoints/tars               # a trained Tars checkpoint (see "Weights")

python examples/plan.py
python -m tars.server --catalog catalogs/example_catalog.json --port 8766
curl -s localhost:8766/plan -d '{"said":"open spotify and play drake then mute"}' -H 'Content-Type: application/json'
```

```python
from tars import Catalog, Planner

planner = Planner(Catalog.load("catalogs/example_catalog.json"))
planner.plan("whats due tomorrow and open the browser to put it on the left screen")
# {'steps': [{'text': 'whats due tomorrow', 'family': 'day', 'skill': 'due_dates_and_tests', ...},
#            {'text': 'open the browser', 'family': 'web', ...},
#            {'text': 'put it on the left screen', 'family': 'windows', 'skill': 'move_minimize_maximize_windows', ...}],
#  'ms': 396.0}
```

Each step comes with probabilities (`family_p`, `skill_p`). The intended use is for the
assistant to trust Tars above a threshold and fall back to its own rules below it.

## Weights

Checkpoints are about 2.9 GB and aren't stored in git. Train your own with the pipeline
below (about 2 hours on an Apple Silicon laptop), or ask the author for the Tars 0.4
checkpoint.

## Train on your own catalog

```bash
# 1. describe your assistant: families, skills, examples, and one paragraph of context
cp catalogs/example_catalog.json catalogs/mine.json

# 2. one round: generate → build → baseline → fine-tune → compare
CATALOG=catalogs/mine.json REAL=my_logged_sentences.txt pipeline/run.sh
```

| Stage | Script | What it does |
|---|---|---|
| Generate | `pipeline/generate.py` | Claude (headless `claude -p`, no tools) writes messy single-skill phrasings, adversarial 2–4 step sentences, near-miss pairs across families, and not-a-command chatter. Three speaking styles are generated only for testing. With `--real`, it also labels your own logged sentences as the real-world test set. Resumable. |
| Build | `pipeline/build.py` | Turns everything into split / route / skill rows through the same builders the planner uses at inference ([`tars/questions.py`](tars/questions.py)). Adds speech-recognition noise, and replays Von's general-reasoning rows so fine-tuning doesn't cause forgetting. |
| Baseline | `pipeline/evaluate.py baseline` | Scores the base model first. **If it's already above ~90%, the data is too easy:** make it harder before training. |
| Train | `pipeline/train.py` | Full fine-tune (encoder and head) on MPS or CUDA with bf16 autocast. Checkpoints are selected on validation plus general replay, never on the tests. Early stopping, time budget, memory-capped on Apple GPUs. |
| Compare | `pipeline/evaluate.py compare` | Base versus candidate on whole sentences. **PROMOTE** only if real and hard sentences improve and general reasoning drops by no more than 2 points. |

Tars 0.4 was trained on 46k rows: 33k split/route/skill rows plus 13k replay. It ran for
1,200 steps (batch 8 × 4, lr 2e-5), about 105 minutes on an M5 Pro with 48 GB.

## Repository layout

```
tars/          planner, HTTP server, catalog, the three questions, model loading
pipeline/      generate · build · train · evaluate · run.sh
catalogs/      example_catalog.json (14 families, 103 skills)
benchmark/     hard_multistep.jsonl (480), evaluate_benchmark.py, near_copies.json
results/       benchmark outputs per model
examples/      plan.py
```

## Credits

- **[Von](https://github.com/wfzyx/von)** by **Victor Hugo** is the base model. Tars is a
  fine-tune of Von 1.2 and uses Von's option-marker model, training collator, loss and
  synthetic general-reasoning generator. Von is licensed Apache-2.0.
- **[ModernBERT](https://github.com/AnswerDotAI/ModernBERT)** (Answer.AI and LightOn) is the
  encoder under Von. Apache-2.0.
- **Claude** (Anthropic) wrote the synthetic training phrasings and the benchmark
  sentences. Check Anthropic's terms before redistributing generated data.

See [NOTICE](NOTICE). Tars is released under the [Apache License 2.0](LICENSE).

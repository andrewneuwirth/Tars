---
license: apache-2.0
base_model: wfzyx/von
library_name: transformers
language: en
tags:
  - decision-model
  - intent-routing
  - modernbert
---
# Model card: Tars 0.5

## Summary

Tars is a 395M-parameter decision model that takes a spoken command and decides what to do with it: where one
request ends and the next begins, which part of the assistant handles each request, and which skill to run. It
does not generate text. It picks one option from a list you supply and gives a probability for it.

Tars 0.5 is trained only on public, synthetic data: labels for the made-up example catalog in the code repository.
It is meant as a starting point. Fine-tune it on your own catalog (the Tars Mac app's "Start from Tars" does this),
since it only knows the example catalog's skills well.

| | |
|---|---|
| Base model | [Von](https://github.com/wfzyx/von) 1.2 by Victor Hugo (Apache-2.0), a ModernBERT option-marker decision model |
| Encoder | [ModernBERT](https://github.com/AnswerDotAI/ModernBERT) (Answer.AI and LightOn, Apache-2.0) |
| Fine-tuning | Full fine-tune (encoder and scoring head) |
| Size | 395M parameters, about 2.9 GB on disk with tokenizer and calibration |
| License | Apache-2.0 |
| Code, labels and benchmark | https://github.com/andrewneuwirth/Tars |

## Intended use

- Deciding which skill, tool or app should handle a short command, given a catalog of skills you write.
- Splitting a sentence that asks for several things into steps.
- A starting point for fine-tuning on your own catalog.
- Running locally on a laptop as a fast first pass. Act on Tars's decision above a probability threshold and fall
  back to your own rules or a larger model below it.

It is not a chat model, cannot answer questions, and cannot take actions by itself.

## Training data

- **Synthetic labels for the public example catalog** (`catalogs/example.json`: made-up apps such as Tunebox and
  Inkpad, 10 families, 31 skills), written by Anthropic's Claude through `pipeline/generate.py`: messy single-skill
  phrasings in 13 speaking styles (terse, casual, speech-to-text errors with no punctuation, rambling, and more),
  2 to 5 step chained commands, near-miss pairs between similar skills, and not-a-command chatter (`none`). Every
  label was checked against the catalog and deduplicated. 8,432 labeled sentences, published in the code
  repository as `labels/example.jsonl`. Speech recognition noise is added in the build step.
- **General-reasoning replay**: 13,000 rows from Von's own synthetic decision generator, mixed in so fine-tuning
  does not erase what the base model already did.
- No personal data: no logged commands, no personal catalog.
- 76,542 training rows (63,542 split, route and skill rows plus 13,000 replay), 3,124 optimizer steps (batch 8 x 4,
  learning rate 2e-5), 151 minutes on an Apple M5 Pro. The checkpoint is the one from step 3,000, picked on
  validation plus general replay, never on the benchmark.

## Evaluation

The public benchmark (`benchmark/public/benchmark.jsonl` in the code repository) has 477 hard multi-step commands
for the example catalog, 2 to 5 steps each. It was generated separately from the training labels, in three speaking
styles never used in training (formal dictation, gamer talk, a non-technical parent). No training sentence has 80%
or more word overlap with a benchmark sentence. A sentence counts only if every step's words, family and skill are
right.

| Model | End to end | Step count right | Split exact | Families right | Skills right | Median latency |
|---|---|---|---|---|---|---|
| Von 1.2 (base, no fine-tune) | 0.0% | 1.7% | 0.4% | 0.0% | 0.0% | 791 ms |
| **Tars 0.5** | **69.2%** | **77.8%** | **71.3%** | **74.8%** | **74.8%** | **280 ms** |

Latency is the whole plan (every split, route and skill question), in-process on an Apple M5 Pro (MPS).

Each question alone, given the correct steps (`pipeline/evaluate.py`, same 477 sentences): split 44.2% → 98.6%,
route 29.0% → 98.8%, skill 74.7% → 100.0%, whole sentence 0.0% → 90.1%. General reasoning on 600 of Von's replay
rows went from 84.3% to 91.2%.

Tars 0.4's numbers (65.0% end to end) came from a private benchmark for a personal catalog and can't be compared
directly with these.

## Limits

- It knows the example catalog's skills. Your own catalog needs a fine-tune; this model is the starting point.
- Most errors are extra splits: a filler word or aside at the start or middle ("yo", "please", "cause the raid
  starts then") becomes its own `none` step. 92 of the 147 failed benchmark sentences have too many steps.
- Labels written by an LLM carry that LLM's mistakes and its idea of how people talk. A few benchmark labels are
  debatable too.
- English only. Tested on short commands; long dictation is out of scope.
- Probabilities come from Von 1.2's calibration and are not refit after fine-tuning. On the benchmark they are close
  to 1.0 for almost every step, including steps in sentences it gets wrong, so they are a weak signal. Check them on
  your own data before choosing a threshold.

## Use

```python
from tars import Catalog, Planner   # https://github.com/andrewneuwirth/Tars
planner = Planner(Catalog.load("catalogs/example.json"), "path/to/this/folder")
planner.plan("open tunebox and play some jazz then mute")
```

The Tars Mac app downloads this checkpoint to fine-tune from it ("Start from Tars 0.5" in Settings).

## Attribution

Tars is a fine-tune of [Von](https://github.com/wfzyx/von) 1.2 by Victor Hugo, Apache-2.0. See NOTICE. The training
labels and benchmark were written by Anthropic's Claude.

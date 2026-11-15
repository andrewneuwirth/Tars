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
# Model card: Tars 0.4

## Summary

Tars is a 395M-parameter decision model that takes a spoken command and decides what to do with it: where one
request ends and the next begins, which part of the assistant handles each request, and which skill to run. It
does not generate text. It picks one option from a list you supply and gives a probability for it.

| | |
|---|---|
| Base model | [Von](https://github.com/wfzyx/von) 1.2 by Victor Hugo (Apache-2.0), a ModernBERT option-marker decision model |
| Encoder | [ModernBERT](https://github.com/AnswerDotAI/ModernBERT) (Answer.AI and LightOn, Apache-2.0) |
| Fine-tuning | Full fine-tune (encoder and scoring head) |
| Size | 395M parameters, about 2.9 GB on disk with tokenizer and calibration |
| License | Apache-2.0 |
| Weights | This repository. Code and training pipeline: https://github.com/andrewneuwirth/Tars |

## Intended use

- Deciding which skill, tool or app should handle a short command, given a catalog of skills you write.
- Splitting a sentence that asks for several things into steps.
- Running locally on a laptop as a fast first pass. The intended pattern is to act on Tars's decision above a
  probability threshold and fall back to your own rules or a larger model below it.

It is not a chat model, cannot answer questions, and cannot take actions by itself.

## Training data

- **Synthetic labels made by an LLM.** Training sentences and their labels (step boundaries, family, skill) were
  written by Anthropic's Claude from a skill catalog: messy single-skill phrasings in many speaking styles,
  adversarial 2 to 4 step sentences, near-miss pairs between similar skills, and not-a-command chatter. Speech
  recognition noise is added in the build step.
- **General-reasoning replay** from Von's own synthetic decision generator, mixed in so fine-tuning does not erase
  what the base model already did.
- Tars 0.4 was trained on 46k rows (33k split, route and skill rows plus 13k replay) for 1,200 optimizer steps
  (batch 8 x 4, learning rate 2e-5), about 105 minutes on an Apple M5 Pro.
- The catalog used for Tars 0.4 belongs to one person's assistant and is not released. The repository ships a
  made-up example catalog instead.

When you fine-tune your own model with the Tars app, the labels come from the AI provider or MCP client you choose.

## Evaluation

Measured on a 480-sentence benchmark of hard multi-step commands written by an LLM for the original catalog (not
released, since it is tied to a personal catalog). A sentence counts only if every step's boundary, family and
skill is right.

| Model | End to end | Clean subset (405) | Step count right | Split exact | Median latency |
|---|---|---|---|---|---|
| Von 1.2 (base, no fine-tune) | 0.0% | 0.0% | 1.9% | 0.0% | 759 ms |
| Tars 0.4 | 65.0% | 61.2% | 76.9% | 74.6% | 352 ms |

75 of the 480 sentences have a near-copy in the training data; the clean subset leaves them out. Latency is the
whole plan, in-process on an Apple M5 Pro (MPS). General reasoning on Von's replay set went from 93.2% to 92.7%.

## Limits

- It only knows the skills in the catalog it was trained on. A new catalog needs a new fine-tune.
- Labels written by an LLM carry that LLM's mistakes and its idea of how people talk. Review a sample before
  training.
- English only. Tested on short commands; long dictation is out of scope.
- Known weak spots in 0.4: apps versus websites with overlapping descriptions, small talk that should be `none`,
  back-references after a media step ("throw it on my right monitor"), and splits with no joining words.
- Probabilities come from Von 1.2's calibration and are not refit after fine-tuning. Check them on your own data
  before choosing a threshold.

## Use

```python
from tars import Catalog, Planner   # https://github.com/andrewneuwirth/Tars
planner = Planner(Catalog.load("my_catalog.json"), "path/to/this/folder")
```

The Tars Mac app downloads this checkpoint to fine-tune from it ("Start from Tars 0.4").

## Attribution

Tars is a fine-tune of [Von](https://github.com/wfzyx/von) 1.2 by Victor Hugo, Apache-2.0. See NOTICE.

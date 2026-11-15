<div align="center">

<img src="docs/images/icon.png" width="128" height="128" alt="Tars app icon">

# Tars

**A small local model that decides what to do with a spoken command.**

[![CI](https://github.com/andrewneuwirth/Tars/actions/workflows/ci.yml/badge.svg)](https://github.com/andrewneuwirth/Tars/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/andrewneuwirth/Tars)](https://github.com/andrewneuwirth/Tars/releases/latest)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Python](https://img.shields.io/badge/python-3.12%2B-3776AB.svg)](pyproject.toml)
[![Swift](https://img.shields.io/badge/app-SwiftUI-F05138.svg)](app/README.md)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%20%C2%B7%20Apple%20silicon-lightgrey.svg)](app/README.md)
[![Based on Von](https://img.shields.io/badge/based%20on-Von%201.2-8A2BE2.svg)](https://github.com/wfzyx/von)

[**Download the Mac app**](https://github.com/andrewneuwirth/Tars/releases/latest) · [Project page](https://newitools.app/lab/tars/) · [Model card](MODEL_CARD.md)

<img src="docs/images/hero.png" width="860" alt="One spoken command split into five steps, each routed to an app and a skill">

<sub>Illustration from the project page. The families and skills come from the example catalog; the confidences are example values.</sub>

</div>

You give Tars what someone said and a catalog of your own tools and skills. It splits the sentence into steps, sends
each step to the right part of your assistant and picks the skill. It runs offline on a laptop in a few hundred
milliseconds, and you fine-tune it on your own tools.

> [!NOTE]
> **Built on [Von](https://github.com/wfzyx/von) by Victor Hugo** (Apache-2.0), a 395M-parameter ModernBERT decision
> model. Tars is a full fine-tune of Von 1.2 and keeps Von's approach: no text generation, only a calibrated choice
> among options you supply. See [NOTICE](NOTICE) and [MODEL_CARD.md](MODEL_CARD.md).

| 65.0% | 352 ms | 395M | 3 |
|:---:|:---:|:---:|:---:|
| hard multi-step commands fully right | median time for a whole plan | parameters, runs offline | questions, no text generation |

```
"lock in timer 25 minutes put on my study playlist dnd on"

  → "lock in timer 25 minutes"  time   / timers               0.99
  → "put on my study playlist"  media  / play_music_by_name   1.00
  → "dnd on"                    mac    / do_not_disturb       0.94
```

(Output of Tars 0.4 on the catalog it was trained on.)

## What it decides

```mermaid
flowchart LR
    S["What someone said"] --> Q1{"Split<br/>new step here?"}
    Q1 --> Q2{"Route<br/>which family?"}
    Q2 --> Q3{"Skill<br/>which skill?"}
    Q3 --> P["Plan: steps with<br/>family_p and skill_p"]
    C[("Your catalog JSON")] -.-> Q2
    C -.-> Q3
```

| Question | Asked | Options |
|---|---|---|
| **Split**: does a new request start at `‖`? | at each candidate word | `new_step` / `same_step` |
| **Route**: which part of the assistant handles this step? | once per step | your catalog's families (+ `none`) |
| **Skill**: which skill within that family? | once per step | that family's skills |

Your skills are data, not code. You describe them in a catalog JSON (families, skills, a few examples each), and
both the planner and the training pipeline read it. [`catalogs/example.json`](catalogs/example.json)
is a made-up example with 10 families and 31 skills.

## Results

Measured on 480 hard multi-step commands, each asking for 2 to 4 things in one breath: missing joiners, "to" used
as "and", back-references ("move it"), titles that contain command words ("play Stop Making Sense"), and three
speaking styles kept out of training. A sentence counts only if every step's boundary, family and skill is right.

```mermaid
xychart-beta
    title "Tars 0.4: sentences fully right (%)"
    x-axis ["Split", "Route", "Skill", "Overall"]
    y-axis "% of 480 sentences" 0 --> 100
    bar [74.6, 66.0, 65.6, 65.0]
```

Von 1.2, the base model, scores 0.0% (split), 0.2% (route), 0.2% (skill) and 0.0% (overall) on the same sentences.

```mermaid
xychart-beta
    title "Median time to plan a whole command (ms, lower is better)"
    x-axis ["Von 1.2", "Tars 0.4"]
    y-axis "ms" 0 --> 800
    bar [759, 352]
```

| Model | End to end | Clean subset* | Step count right | Split exact | Median latency |
|---|---|---|---|---|---|
| Von 1.2 (base, no fine-tune) | 0.0% | 0.0% | 1.9% | 0.0% | 759 ms |
| **Tars 0.4** | **65.0%** | **61.2%** | **76.9%** | **74.6%** | **352 ms** |

\* 75 of the 480 sentences have a near-copy (≥80% word overlap) in the training data. The clean subset leaves them
out and is the number to quote.

Latency is the whole plan (every split, route and skill question), in-process on an Apple M5 Pro (MPS). Single-step
commands take about 130–230 ms.

The benchmark sentences and the Tars 0.4 weights are not in this repository: both are tied to the personal catalog
the model was trained on. [`benchmark/evaluate_benchmark.py`](benchmark/README.md) scores any planner on your own
benchmark file in the same way.

## Fine-tune it on your own tools

The base model doesn't know your skills, so the useful version of Tars is the one you train. That takes labels:
example commands with their correct steps and skills. Tars 0.4 used about 10,000 sentences written by an LLM.

**The Tars Mac app** ([`app/`](app/README.md), [download](https://github.com/andrewneuwirth/Tars/releases/latest)) does the whole loop:

1. Define your catalog: families, skills, example commands.
2. Make labels with your own AI provider (a Claude, ChatGPT or Gemini subscription through its command line tool,
   an API key, or a local OpenAI-compatible server), or let any MCP client such as Claude Code write them through
   the app's MCP server.
3. Review the labels in a table, spot-check and delete bad ones.
4. Train, watch loss and accuracy live, compare your model with the base model, and export it.

<table>
  <tr>
    <td width="50%"><img src="docs/images/app-catalog.png" alt="Catalog screen"><br><sub><b>Catalog</b>: families and skills with example commands</sub></td>
    <td width="50%"><img src="docs/images/app-labels.png" alt="Labels screen"><br><sub><b>Labels</b>: search, spot-check, edit and delete</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/images/app-train.png" alt="Train screen"><br><sub><b>Train</b>: build, baseline, train and compare</sub></td>
    <td width="50%"><img src="docs/images/app-model-lab.png" alt="Model Lab screen"><br><sub><b>Model Lab</b>: live charts and your model against the base</sub></td>
  </tr>
</table>

<sub>Screenshots use the app's built-in demo data. The labels and numbers in them are made up, not results.</sub>

The app comes with the training code. The first time, it downloads Python, PyTorch, Von's code and the Von 1.2 base
model (about 3.4 GB, pinned and checksummed), then trains offline. No checkout or Python setup is needed.

Or run the pipeline yourself:

```bash
# labels you already have: one sentence per line, see pipeline/build.py
LABELS=labels.jsonl CATALOG=catalogs/mine.json pipeline/run.sh

# or let the Claude Code CLI write them
CATALOG=catalogs/mine.json pipeline/run.sh
```

```mermaid
flowchart LR
    G["Generate<br/><code>generate.py</code>"] --> B["Build<br/><code>build.py</code>"]
    L[("LABELS=…")] -.->|skips Generate| B
    B --> BL["Baseline<br/><code>evaluate.py baseline</code>"]
    BL --> T["Train<br/><code>train.py</code>"]
    T --> CMP{"Compare<br/><code>evaluate.py compare</code>"}
    CMP -->|PROMOTE| M["Manual copy<br/>of the checkpoint"]
```

| Stage | Script | What it does |
|---|---|---|
| Generate | `pipeline/generate.py` | Claude (headless `claude -p`, no tools) writes messy single-skill phrasings, adversarial 2–4 step sentences, near-miss pairs across families and not-a-command chatter. Three speaking styles are kept for testing only. Skipped when `LABELS` is set. |
| Build | `pipeline/build.py` | Turns labels into split, route and skill rows through the same code the planner uses ([`tars/questions.py`](tars/questions.py)). Adds speech-recognition noise and replays Von's general-reasoning rows so fine-tuning doesn't cause forgetting. |
| Baseline | `pipeline/evaluate.py baseline` | Scores the base model first. If it's already above about 90%, the data is too easy. |
| Train | `pipeline/train.py` | Full fine-tune on MPS or CUDA with bf16 autocast. Picks the checkpoint on validation plus general replay, never on the tests. Early stopping, a time budget, memory capped on Apple GPUs. |
| Compare | `pipeline/evaluate.py compare` | Base versus candidate on whole sentences. **PROMOTE** only if test sentences improve and general reasoning drops by no more than 2 points. |

Nothing replaces a checkpoint automatically. Promoting is a manual copy after `compare` says PROMOTE.

## Quick start

Tars imports Von's model class and training utilities, so it needs a Von checkout with Von 1.2's weights next to
this repo.

```bash
git clone https://github.com/wfzyx/von ../von           # base model + utilities (see Von's README for weights)
uv venv && uv pip install -e . -e ../von                 # Python 3.12+
export VON_REPO=../von
export TARS_CHECKPOINT=checkpoints/tars                  # a checkpoint you trained

python -m tars.server --catalog catalogs/example.json --port 8766
curl -s localhost:8766/plan -d '{"said":"open tunebox and play jazz then mute"}' -H 'Content-Type: application/json'
```

```python
from tars import Catalog, Planner

planner = Planner(Catalog.load("catalogs/example.json"))
planner.plan("am i free at 4 and text sam that i'll be late")
# {'steps': [{'text': 'am i free at 4', 'family': 'calendar', 'skill': 'am_i_free', 'family_p': ..., 'skill_p': ...},
#            {'text': "text sam that i'll be late", 'family': 'messages', 'skill': 'send_message', ...}],
#  'ms': ...}
```

Each step comes with probabilities (`family_p`, `skill_p`). Trust Tars above a threshold and fall back to your own
rules below it.

## Repository layout

```
tars/          planner, HTTP server, catalog, the three questions, model loading
pipeline/      generate · build · train · evaluate · try · run.sh
catalogs/      example.json (made-up apps and skills)
benchmark/     evaluate_benchmark.py
app/           the Tars Mac app (SwiftUI)
tests/         python -m unittest discover -s tests
```

## Credits

- **[Von](https://github.com/wfzyx/von)** by **Victor Hugo** is the base model. Tars is a fine-tune of Von 1.2 and
  uses Von's option-marker model, training collator, loss and synthetic general-reasoning generator. Apache-2.0.
- **[ModernBERT](https://github.com/AnswerDotAI/ModernBERT)** (Answer.AI and LightOn) is the encoder under Von.
  Apache-2.0.
- Tars 0.4's training sentences were written by Anthropic's Claude. Check your provider's terms before
  redistributing generated data.

Tars is released under the [Apache License 2.0](LICENSE).

# AGENTS.md: Tars

**Tars** (`tars-planner` 0.4.0, Apache-2.0) is a small local model that decides what to do with a command: it splits one spoken sentence into steps, routes each step to a family, and picks the skill. It is a full fine-tune of Von 1.2 (395M ModernBERT option-marker model, https://github.com/wfzyx/von). `app/` is the Tars Mac app for building a catalog, collecting labels, training and comparing models.

## Naming

- The user-facing name is **Tars**. "Von" is the credited base model; never call the assistant "Von" in UI.

## Stack

- Python ≥3.12; torch, transformers ≥5, FastAPI/uvicorn, pydantic. Package `tars/` (setuptools).
- Needs a Von checkout for the base model and its training utilities: `VON_REPO` (default `../von`). Base checkpoint `TARS_BASE` (default `$VON_REPO/checkpoints/von-1.2`), Tars checkpoint `TARS_CHECKPOINT` (default `checkpoints/tars`), data `TARS_DATA` (default `data/`), live status `TARS_PROGRESS` (default `runs/progress.json`). See `tars/config.py`.
- `app/`: SwiftUI, SwiftPM (tools 6.2, Swift 5 language mode, macOS 26), MacToolsKit. See `app/README.md`.

## Commands

```sh
python -m unittest discover -s tests                     # pure tests, no torch or Von needed
python -m tars.server --catalog catalogs/example.json --port 8766
LABELS=labels.jsonl CATALOG=catalogs/mine.json pipeline/run.sh   # build → baseline → train → compare
CATALOG=catalogs/mine.json pipeline/run.sh                       # same, with Claude CLI generation first
python pipeline/try.py --catalog catalogs/mine.json "open tunebox and play jazz" base candidate
cd app && ./build.sh && build/Tars.app/Contents/MacOS/Tars --self-check
```

## Rules

- Checkpoints (~2.9 GB), `data/` and `runs/` are gitignored. Never commit weights or generated data.
- `pipeline/generate.py` calls Claude through the CLI (`claude -p --tools "" --strict-mcp-config --no-session-persistence`); keep those flags on any new background call.
- `pipeline/run.sh` never replaces a checkpoint; promoting is a manual copy after `evaluate.py compare` says PROMOTE.
- No personal data in the repo: no real logged commands, personal catalogs, names or home-folder paths. The example catalog uses made-up apps.
- Files adapted from Von keep a header saying what was adapted and what The Tars Authors changed.

## Layout

```
tars/        planner, HTTP server, catalog, the three questions (split/route/skill), model loading
pipeline/    generate · build · train · evaluate · try · status · run.sh
catalogs/    example.json (made-up apps and skills)
benchmark/   evaluate_benchmark.py
app/         Tars Mac app
tests/       unit tests for questions and catalog
```

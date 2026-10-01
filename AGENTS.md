# AGENTS.md: Tars

**Tars** (`tars-planner` 0.4.0, Apache-2.0, repo `andrewneuwirth/Tars`, written to be released) is a small local planner for voice assistants: it splits one spoken sentence into steps, routes each step to a family, and picks the skill. It's a full fine-tune of Von 1.2 (395M ModernBERT option-marker model). This is the standalone, publishable version of the planner; the live assistant runs from a separate Von checkout.

## Naming

- The user-facing name is **Tars**. "Von" is only the credited base model (wfzyx/von); never call the assistant "Von" in UI or when talking to the user.

## Stack

- Python ≥3.12; torch, transformers ≥5, FastAPI/uvicorn, pydantic. Package `tars/` (setuptools).
- Needs a Von checkout for the base model and its training utilities: `VON_REPO` (default `../von`). Base checkpoint `TARS_BASE` (default `$VON_REPO/checkpoints/von-1.2`), Tars checkpoint `TARS_CHECKPOINT` (default `checkpoints/tars`). See `tars/config.py`.
- If the Von checkout isn't at `../von` (locally it's the sibling `von/` folder), set `VON_REPO` to it.

## Commands

```sh
python examples/plan.py
python -m tars.server --catalog catalogs/example_catalog.json --port 8766
curl -s localhost:8766/plan -d '{"said":"open spotify and play drake then mute"}' -H 'Content-Type: application/json'
CATALOG=catalogs/mine.json REAL=my_sentences.txt pipeline/run.sh   # generate → build → baseline → train → compare (~2 h)
python benchmark/evaluate_benchmark.py --catalog catalogs/example_catalog.json   # 480-sentence hard benchmark (--url for an HTTP planner)
```

There is no unit-test suite; the benchmark and `pipeline/evaluate.py` are the checks. No launchd service runs from this repo.

## Rules

- Checkpoints (~2.9 GB), `data/` and `runs/` are gitignored. Never commit weights or generated data.
- `pipeline/generate.py` calls Claude through the subscription CLI (`claude -p --tools "" --strict-mcp-config --no-session-persistence`); keep those flags on any new background call. No API keys, no `--bare`.
- `pipeline/run.sh` never replaces a checkpoint; promoting is a manual copy after `evaluate.py compare` says PROMOTE.
- Written for release: keep the author's private logged commands, paths and personal notes out of it. The private eval set (178 real sentences) is not released.
- Quote the benchmark's **clean subset** number (near-copies listed in `benchmark/near_copies.json`).

## Layout

```
tars/        planner, HTTP server, catalog, the three questions (split/route/skill), model loading
pipeline/    generate · build · train · evaluate · status · run.sh
catalogs/    example_catalog.json (14 families, 103 skills)
benchmark/   hard_multistep.jsonl (480), evaluate_benchmark.py, near_copies.json
results/     benchmark outputs per model
examples/    plan.py
```

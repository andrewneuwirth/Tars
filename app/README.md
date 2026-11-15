# Tars for Mac

A native macOS app for fine-tuning your own Tars: describe your tools, collect labels, review them, train, and
compare your model with the base model.

## What it does

- **Catalog**: your families and skills with a few example commands each, saved in the JSON the pipeline reads.
- **Make Labels**: your own AI provider writes labeled commands in batches, thinnest skills first. Providers: a
  Claude subscription (Claude Code), a ChatGPT subscription (Codex), Gemini CLI, or an Anthropic, OpenAI, Google or
  OpenAI-compatible (Ollama, LM Studio) API key. Keys are kept in the Keychain under the service
  `app.newitools.Tars`. Every label is checked against the catalog before it's kept.
- **MCP server**: `Tars --mcp` lets Claude Code, Codex or any MCP client write labels with the tools `get_catalog`,
  `get_label_schema`, `submit_labels` and `get_progress`:

      claude mcp add tars -- /Applications/Tars.app/Contents/MacOS/Tars --mcp

- **Labels**: a table to search, spot-check, edit, move between train and test, and delete.
- **Train**: runs `pipeline/run.sh` with your catalog and labels (build, baseline, train, compare), with a time
  budget, a quick test mode, a clean stop, and export of the fine-tuned checkpoint with its catalog.
- **Model Lab**: live loss and accuracy charts, validation checks during the run, your model against the base model
  (whole sentence, splitting, routing, skill choice, time per question, general reasoning), past runs with their
  scores, and a box to type a command and see what each model decides.

Your data lives in `~/Library/Application Support/Tars` (catalog.json, labels.jsonl, training data, runs,
checkpoints).

## Everything needed to train comes with the app

The app bundles the training code (`pipeline/`, `tars/`, the example catalog) and
[uv](https://github.com/astral-sh/uv) (MIT OR Apache-2.0, licenses in `Contents/Resources/third-party/uv`). The first
time you train, **Set Up Training** downloads, once, into `~/Library/Application Support/Tars`:

| What | From | Pinned by | Download |
|---|---|---|---|
| CPython 3.12.16 | uv's managed Python builds | version | ~20 MB |
| PyTorch, transformers and the rest | PyPI | `Resources/requirements.lock` (versions and sha256 hashes) | ~170 MB |
| Von's source (model class, training collator and loss, replay generator) | github.com/wfzyx/von | commit, plus sha256 of every Python file used | ~4 MB |
| Von 1.2 base model | [huggingface.co/wfzyx/von](https://huggingface.co/wfzyx/von) (Von's official weights, Apache-2.0) | revision, each file checked against the repo's sha256 | 3.17 GB |

About 3.4 GB in total, about 4 GB on disk. It shows progress, can be cancelled, and Retry continues where it stopped.
Afterwards training runs offline (`HF_HUB_OFFLINE=1`). Everything pinned lives in
`Resources/training-manifest.json`.

Optional: **Download Tars 0.4** (Settings) fetches the fine-tuned Tars weights from the Hugging Face repo named in the
manifest (`tars.repo`) so training can start from Tars instead of Von 1.2.

**Advanced** (Settings): use your own checkout, Python and Von instead.

## Requirements

- macOS 26 on Apple silicon, Swift 6.2 toolchain (Xcode 26) to build.

## Build and run

    cd app
    ./build.sh                   # build/Tars.app, signed with your Apple Development identity (or ad hoc)
    ./build.sh --install         # also copies it to /Applications and opens it
    ./build.sh --release         # Developer ID signing with hardened runtime, for notarization

    build/Tars.app/Contents/MacOS/Tars --self-check       # pure-logic checks, touches nothing
    build/Tars.app/Contents/MacOS/Tars --preview shots/   # PNGs of every screen with demo data, light and dark
    build/Tars.app/Contents/MacOS/Tars --demo             # the app with demo data, nothing saved
    TARS_HOME=/tmp/t build/Tars.app/Contents/MacOS/Tars --setup                 # the training setup without the window
    TARS_HOME=/tmp/t build/Tars.app/Contents/MacOS/Tars --quick-train labels.jsonl   # a few steps, then the verdict

`build.sh` copies the training code from the repository into the app and downloads the pinned uv release (checked by
sha256).

To build with your own bundle id or signing identity, copy `config.example.env` to `config.local.env`.

The app depends on [MacToolsKit](https://github.com/andrewneuwirth/mac-tools-kit). A `../Kit` checkout next to
`app/` is used when present.

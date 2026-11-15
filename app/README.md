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

## Requirements

- macOS 26, Swift 6.2 toolchain (Xcode 26).
- For training: this repository, a Python 3.12+ environment with the package and Von installed, and a Von checkout
  with Von 1.2's weights. Set the three paths in Settings.

      git clone https://github.com/wfzyx/von ../von
      uv venv && uv pip install -e . -e ../von

## Build and run

    cd app
    ./build.sh                   # build/Tars.app, signed with your Apple Development identity (or ad hoc)
    ./build.sh --install         # also copies it to /Applications and opens it
    ./build.sh --release         # Developer ID signing with hardened runtime, for notarization

    build/Tars.app/Contents/MacOS/Tars --self-check       # pure-logic checks, touches nothing
    build/Tars.app/Contents/MacOS/Tars --preview shots/   # PNGs of every screen with demo data, light and dark
    build/Tars.app/Contents/MacOS/Tars --demo             # the app with demo data, nothing saved

To build with your own bundle id or signing identity, copy `config.example.env` to `config.local.env`.

The app depends on [MacToolsKit](https://github.com/andrewneuwirth/mac-tools-kit). A `../Kit` checkout next to
`app/` is used when present.

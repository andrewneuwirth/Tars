#!/usr/bin/env bash
# Uploads a Tars checkpoint to Hugging Face so the Tars app can download it ("Start from Tars 0.4").
#   hf/publish.sh <checkpoint-folder>          (needs `hf auth login` with write access to the repo)
# The repo id is the one the app reads: app/Resources/training-manifest.json → tars.repo.
set -euo pipefail
cd "$(dirname "$0")/.."
CKPT=${1:?usage: hf/publish.sh <checkpoint-folder>}
REPO=$(plutil -extract tars.repo raw app/Resources/training-manifest.json)
for f in config.json tokenizer.json tokenizer_config.json marker_calibration.json model.safetensors option_marker.pt; do
  [ -f "$CKPT/$f" ] || { echo "missing $CKPT/$f" >&2; exit 1; }
done
# Only a Tars fine-tune trained on synthetic labels belongs here, never one trained on personal logged commands.
grep -q '"model_id": "tars"' "$CKPT/marker_calibration.json" || { echo "$CKPT is not a Tars checkpoint (model_id must be \"tars\")" >&2; exit 1; }
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp "$CKPT"/{config.json,tokenizer.json,tokenizer_config.json,marker_calibration.json,model.safetensors,option_marker.pt} "$STAGE/"
[ -f "$CKPT/calibration.json" ] && cp "$CKPT/calibration.json" "$STAGE/"
cp hf/README.md "$STAGE/README.md"
cp NOTICE LICENSE "$STAGE/"
echo "Uploading $(du -sh "$STAGE" | cut -f1) to https://huggingface.co/$REPO"
hf repo create "$REPO" --repo-type model --exist-ok
hf upload "$REPO" "$STAGE" . --commit-message "Tars 0.4"

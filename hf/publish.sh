#!/usr/bin/env bash
# Uploads a Tars checkpoint to Hugging Face so the Tars app can download it ("Start from Tars").
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
hf repos create "$REPO" --type model --public --exist-ok
NAME=$(plutil -extract tars.name raw app/Resources/training-manifest.json)
hf upload "$REPO" "$STAGE" . --commit-message "$NAME"
SHA=$(curl -fsS "https://huggingface.co/api/models/$REPO/revision/main" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])')
echo "Uploaded $REPO at $SHA. To pin the app to exactly these files, set tars.revision to $SHA in app/Resources/training-manifest.json."

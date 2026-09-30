"""Load a Von/Tars checkpoint and score rows in batches, with the same packing
and attention mode Von's live service uses."""

from __future__ import annotations

import json
import os
from typing import Iterable

import torch

from .config import BASE_CHECKPOINT, use_von

use_von()
from von.models.option_marker import OptionMarkerModel  # noqa: E402
from training.train_option_marker import collate_marker_fn  # noqa: E402


def device() -> torch.device:
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


def calibration(ckpt: str) -> dict:
    p = os.path.join(ckpt, "marker_calibration.json")
    return json.load(open(p)) if os.path.exists(p) else {}


def load(ckpt: str, dev: torch.device | None = None) -> tuple[OptionMarkerModel, dict]:
    """Encoder config and tokenizer from the Von base; weights from `ckpt`."""
    dev = dev or device()
    cal = calibration(ckpt) or calibration(BASE_CHECKPOINT)
    model = OptionMarkerModel(base_model_id=BASE_CHECKPOINT, max_position_embeddings=8192,
                              digit_split=bool(cal.get("digit_split", False)))
    state = torch.load(os.path.join(ckpt, "option_marker.pt"), map_location="cpu")
    missing, unexpected = model.load_state_dict(state, strict=True)
    assert not missing and not unexpected, (missing, unexpected)
    return model.to(dev), cal


def _batches(rows: list[dict], size: int) -> Iterable[list[dict]]:
    order = sorted(range(len(rows)), key=lambda i: len(rows[i]["state"]) + sum(len(o["description"]) for o in rows[i]["options"]))
    for i in range(0, len(order), size):
        yield [rows[j] for j in order[i:i + size]]


@torch.no_grad()
def predict(model: OptionMarkerModel, rows: list[dict], batch_size: int = 32,
            max_length: int = 2048) -> list[tuple[str, float]]:
    """(chosen option id, its probability) per row, in the original order."""
    model.eval()
    dev = next(model.parameters()).device
    index = {id(r): i for i, r in enumerate(rows)}
    out: dict[int, tuple[str, float]] = {}
    for batch in _batches(rows, batch_size):
        enc = collate_marker_fn(batch, model.tokenizer, max_length=max_length, digit_split=model.digit_split)
        logits = model(input_ids=enc["input_ids"].to(dev), attention_mask=enc["attention_mask"].to(dev),
                       mask_positions=enc["mask_positions"], independent_options=True)
        for r, lg in zip(batch, logits):
            p = torch.softmax(lg.float(), dim=-1)
            k = int(torch.argmax(p))
            out[index[id(r)]] = (r["options"][k]["id"], float(p[k]))
    return [out[i] for i in range(len(rows))]

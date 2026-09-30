"""Small helpers shared by the pipeline scripts."""

from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tars.model import predict  # noqa: E402


def read_jsonl(path: str) -> list[dict]:
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]


def accuracy(model, rows: list[dict], **_) -> float:
    if not rows:
        return float("nan")
    preds = predict(model, rows)
    return sum(p == r["label"] for (p, _), r in zip(preds, rows)) / len(rows)

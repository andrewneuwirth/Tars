"""Where Von lives. Tars reuses Von's model class and training utilities, so it
needs a Von checkout: set VON_REPO, or clone it next to this repo (../von)."""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VON_REPO = os.path.abspath(os.environ.get("VON_REPO", os.path.join(ROOT, "..", "von")))
# The base model Tars is fine-tuned from, and the fine-tuned Tars checkpoint.
BASE_CHECKPOINT = os.environ.get("TARS_BASE", os.path.join(VON_REPO, "checkpoints", "von-1.2"))
CHECKPOINT = os.environ.get("TARS_CHECKPOINT", os.path.join(ROOT, "checkpoints", "tars"))


def use_von() -> None:
    """Put Von's package and its training/ folder on the import path."""
    if not os.path.isdir(VON_REPO):
        raise SystemExit(f"Von not found at {VON_REPO}. Clone https://github.com/wfzyx/von there or set VON_REPO.")
    for p in (VON_REPO, os.path.join(VON_REPO, "src")):
        if p not in sys.path:
            sys.path.insert(0, p)

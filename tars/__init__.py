"""Tars: a small, local command planner for voice assistants.

Splits a spoken sentence into steps, routes each step to a part of the
assistant, and picks the skill, in one ~150 ms pass on a laptop. Built on Von
(https://github.com/wfzyx/von), a ModernBERT option-marker decision model.
"""

from .catalog import Catalog
from .planner import Planner

__all__ = ["Catalog", "Planner"]
__version__ = "0.4.0"

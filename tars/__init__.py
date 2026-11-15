"""Tars: a small, local command planner for voice assistants.

Splits a spoken sentence into steps, routes each step to a part of the
assistant, and picks the skill, in a few hundred milliseconds on a laptop. Built on Von
(https://github.com/wfzyx/von), a ModernBERT option-marker decision model.
"""

from .catalog import Catalog

__all__ = ["Catalog", "Planner"]
__version__ = "0.4.0"


def __getattr__(name):
    # Planner loads torch and Von; import it only when asked, so tars.catalog and
    # tars.questions work (and test) without either.
    if name == "Planner":
        from .planner import Planner
        return Planner
    raise AttributeError(name)

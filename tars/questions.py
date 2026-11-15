"""The three questions Tars answers, as model rows. Training and inference both
build rows here, so what the model sees live is exactly what it learned on.

  split  "Does a new, separate request start at the ‖ mark?"   new_step / same_step
  route  "Which part of Tars should handle this request?"     a catalog family
  skill  "Which of these does the user want?"                  a skill in that family
"""

from __future__ import annotations

import re

from .catalog import Catalog

Q_ROUTE = "Which part of Tars should handle this request?"
Q_SKILL = "Which of these does the user want?"
Q_SPLIT = "Does a new, separate request start at the ‖ mark?"
MARK = "‖"
SPLIT_OPTS = [{"id": "new_step", "description": "Yes: a separate request starts at ‖"},
              {"id": "same_step", "description": "No: the words after ‖ still belong to the same request"}]
# Words that join requests ("and go", "then", "to" said for "and"). A boundary is
# asked at the first word of a run of these, never in the middle of one.
JOINERS = {"and", "then", "go", "ahead", "to", "so", "also", "after", "that", "next", "plus", "&", "n", "an"}


def state_text(state: dict) -> str:
    return "\n".join(f"{k}: {v}" for k, v in state.items())


def clean_word(w: str) -> str:
    return re.sub(r"[^\w']", "", w.lower())


def split_candidates(words: list[str]) -> list[int]:
    clean = [clean_word(w) for w in words]
    return [i for i in range(1, len(words)) if not (clean[i - 1] in JOINERS and i - 1 > 0)]


def split_row(words: list[str], i: int, label: str = "same_step") -> dict:
    return {"state": state_text({"said": " ".join(words[:i] + [MARK] + words[i:])}), "question": Q_SPLIT,
            "options": [dict(o) for o in SPLIT_OPTS], "label": label, "kind": "split", "at": i}


def route_row(cat: Catalog, step: str, label: str = "none", prev: str | None = None,
              sentence: str | None = None) -> dict:
    state = {"said": step}
    if sentence and sentence != step:
        state["whole sentence"] = sentence
    if prev:
        state["previous step"] = prev
    return {"state": state_text(state), "question": Q_ROUTE, "kind": "route", "label": label,
            "options": [{"id": k, "description": v} for k, v in cat.families.items()]}


def skill_row(cat: Catalog, step: str, family: str, label: str | None = None, prev: str | None = None) -> dict | None:
    fam = cat.skills_in(family)
    if len(fam) < 2:
        return None
    state = {"said": step}
    if prev:
        state["previous step"] = prev
    return {"state": state_text(state), "question": Q_SKILL, "kind": "skill", "label": label or next(iter(fam)),
            "options": [{"id": k, "description": cat.describe(k)} for k in fam]}


# "next" also starts real commands ("next song"); it is a joiner only before other words.
NEXT_NOUNS = {"song", "track", "tab", "page", "video", "episode"}


def strip_joiners(words: list[str]) -> str:
    while len(words) > 1 and clean_word(words[0]) in JOINERS:
        if clean_word(words[0]) == "next" and clean_word(words[1]) in NEXT_NOUNS:
            break
        words = words[1:]
    return " ".join(words).strip(" ,")

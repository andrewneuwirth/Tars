"""A skill catalog: the assistant's families (first question) and skills
(second question). See catalogs/example_catalog.json for the format."""

from __future__ import annotations

import json
from dataclasses import dataclass, field


@dataclass
class Catalog:
    families: dict[str, str]
    skills: dict[str, dict]
    context: str = ""
    assistant: str = "Tars"
    path: str = field(default="", repr=False)

    @classmethod
    def load(cls, path: str) -> "Catalog":
        d = json.load(open(path, encoding="utf-8"))
        skills = {s["key"]: s for s in d["skills"]}
        unknown = {s["family"] for s in skills.values()} - set(d["families"])
        if unknown:
            raise ValueError(f"skills use families not in the catalog: {sorted(unknown)}")
        if "none" not in d["families"]:
            raise ValueError('the catalog needs a "none" family (not a request)')
        return cls(d["families"], skills, d.get("context", ""), d.get("assistant", "Tars"), path)

    def skills_in(self, family: str) -> dict[str, dict]:
        return {k: v for k, v in self.skills.items() if v["family"] == family}

    def family_of(self, skill: str) -> str:
        return "none" if skill == "none" else self.skills[skill]["family"]

    def describe(self, skill: str) -> str:
        s = self.skills[skill]
        return f"{s['name']}, like: {'; '.join(s['examples'][:3])}"

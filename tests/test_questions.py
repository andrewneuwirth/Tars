import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tars import questions as Q  # noqa: E402
from tars.catalog import Catalog  # noqa: E402

CATALOG = Path(__file__).resolve().parents[1] / "catalogs" / "example.json"


class StripJoinerTests(unittest.TestCase):
    def test_keeps_next_song(self):
        self.assertEqual(Q.strip_joiners(["next", "song"]), "next song")
        self.assertEqual(Q.strip_joiners(["and", "next", "tab"]), "next tab")

    def test_removes_joiners(self):
        self.assertEqual(Q.strip_joiners(["and", "go", "play", "music"]), "play music")
        self.assertEqual(Q.strip_joiners(["then", "open", "Tunebox"]), "open Tunebox")


class RowTests(unittest.TestCase):
    def test_rows_use_the_catalog(self):
        cat = Catalog.load(str(CATALOG))
        route = Q.route_row(cat, "pause", "music")
        self.assertIn("music", [o["id"] for o in route["options"]])
        skill = Q.skill_row(cat, "pause", "music", "play_pause_skip")
        self.assertEqual(skill["label"], "play_pause_skip")
        self.assertEqual(Q.split_candidates("open tunebox and play jazz".split()), [1, 2, 4])


if __name__ == "__main__":
    unittest.main()

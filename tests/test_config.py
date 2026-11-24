"""Reading, validating and writing settings – without a model and without real folders.

    .venv/bin/python -m unittest discover tests
"""
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from wissen import config, organize


class ConfigTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name) / "config.toml"

    def tearDown(self):
        self.dir.cleanup()

    def defaults(self) -> dict:
        return config.to_dict(config.load(self.path), self.path)

    def test_without_file_defaults_apply(self):
        raw = self.defaults()
        self.assertFalse(raw["exists"])
        self.assertFalse(raw["links_enabled"], "browser history is off for new users")
        self.assertEqual(raw["topics"][-1]["slug"], "other")
        fresh = config.to_dict(config._from_raw({**raw, "root": self.dir.name + "/Wissen"}), self.path)
        self.assertEqual(fresh["folder_names"]["topics"], "Topics")

    def test_save_and_load_round_trip(self):
        raw = self.defaults()
        raw.update(root="~/Archive", watch=["~/Downloads", "~/Desktop"], auto_apply=True, subfolders="year",
                   min_age_minutes=10, profile='Likes "quotes" and umlauts: äöü', summary_language="German")
        config.save(raw, self.path)
        again = config.to_dict(config.load(self.path), self.path)
        self.assertTrue(again["exists"])
        for key in ("root", "watch", "auto_apply", "subfolders", "min_age_minutes", "profile", "summary_language", "topics"):
            expected = config.to_dict(config._from_raw(raw), self.path)[key]
            self.assertEqual(again[key], expected, key)
        self.assertIn('root = "~/Archive"', self.path.read_text(), "paths in the home folder are written with ~")

    def test_new_topic_gets_folder_name_from_name(self):
        raw = self.defaults()
        raw["topics"] = [{"name": "Küche & Rezepte"}, {"name": "Küche & Rezepte"}]
        cfg = config.save(raw, self.path)
        self.assertEqual(cfg.slugs, ["kueche-rezepte", "kueche-rezepte-2", "other"])

    def test_invalid_settings_are_rejected_with_a_sentence(self):
        raw = self.defaults()
        for change in ({"root": raw["watch"][0]}, {"model": " "}, {"topics": [{"slug": "Not Allowed", "name": "x"}]},
                       {"topics": [{"slug": "a", "name": "A"}, {"slug": "a", "name": "B"}]}, {"min_age_minutes": "lots"}):
            with self.assertRaises(config.ConfigError, msg=str(change)):
                config.save({**raw, **change}, self.path)
        self.assertFalse(self.path.exists(), "nothing is written after an error")

    def test_slugify(self):
        self.assertEqual(config.slugify("Travel & Transport"), "travel-transport")
        self.assertEqual(config.slugify("  Straße/Größe  "), "strasse-groesse")
        self.assertEqual(config.slugify("???"), "topic")


class LegacyInstallTest(unittest.TestCase):
    """Installs from before the switch to English keep their German topic and folder names."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name) / "Wissen"
        self.path = Path(self.dir.name) / "config.toml"
        self.path.write_text(f'root = "{self.root}"\n'
                             '[[topics]]\nslug = "finanzen"\nname = "Finanzen"\n'
                             '[[topics]]\nslug = "eigenes"\nname = "Eigenes"\n'
                             '[[topics]]\nslug = "sonstiges"\nname = "Sonstiges"\n')

    def tearDown(self):
        self.dir.cleanup()

    def test_old_config_keeps_links_on_fallback_and_styles(self):
        cfg = config.load(self.path)
        self.assertTrue(cfg.links_enabled, "a missing entry keeps the behaviour from before the setting existed")
        self.assertEqual(cfg.fallback, "sonstiges")
        self.assertNotIn("other", cfg.slugs, "no second catch-all topic is added")
        self.assertEqual(cfg.topic("finanzen").symbol, "eurosign.circle.fill")
        self.assertIn(cfg.topic("eigenes").color, config.COLORS)

    def test_existing_german_folders_are_kept(self):
        for name in ("Themen", "Tage", "_privat"):
            (self.root / name).mkdir(parents=True)
        cfg = config.load(self.path)
        self.assertEqual((cfg.topics_dir.name, cfg.days_dir.name, cfg.private_dir.name), ("Themen", "Tage", "_privat"))
        cfg.ensure_dirs()
        self.assertFalse((self.root / "Topics").exists(), "no English folders appear next to the German ones")

    def test_new_install_gets_english_folders(self):
        cfg = config.load(self.path)
        self.assertEqual((cfg.topics_dir.name, cfg.days_dir.name, cfg.private_dir.name), ("Topics", "Days", "_private"))


class DestinationTest(unittest.TestCase):
    def cfg(self, **changes):
        raw = config.to_dict(config.load(Path("/does/not/exist.toml")))
        raw.update(root="/tmp/wissen-test-destination", **changes)
        return config._from_raw(raw)

    def row(self, topic="finance", confidence=0.9):
        return {"topic": topic, "confidence": confidence, "name": "a.pdf", "mtime": datetime(2026, 3, 14).timestamp()}

    def test_subfolders(self):
        root = Path("/tmp/wissen-test-destination")
        self.assertEqual(organize.destination(self.cfg(), self.row()), root / "Topics/finance/a.pdf")
        self.assertEqual(organize.destination(self.cfg(subfolders="year"), self.row()), root / "Topics/finance/2026/a.pdf")
        self.assertEqual(organize.destination(self.cfg(subfolders="month"), self.row()),
                         root / "Topics/finance/2026/2026-03/a.pdf")

    def test_unsure_or_unknown_goes_to_inbox(self):
        cfg = self.cfg(subfolders="year")
        root = Path("/tmp/wissen-test-destination")
        self.assertEqual(organize.destination(cfg, self.row(confidence=0.2)), root / "_inbox/a.pdf")
        for new in ("new", "neu"):
            self.assertEqual(organize.destination(cfg, self.row(topic=new)), root / "_inbox/a.pdf")


if __name__ == "__main__":
    unittest.main()

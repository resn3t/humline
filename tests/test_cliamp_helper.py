"""Tests for bin/humline-cliamp (favorites.toml handling) and the manifest.

Run: python3 -m unittest discover -s tests
"""
import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_helper():
    path = os.path.join(ROOT, "bin", "humline-cliamp")
    loader = importlib.machinery.SourceFileLoader("humline_cliamp", path)
    spec = importlib.util.spec_from_loader("humline_cliamp", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


helper = load_helper()


class QuoteTests(unittest.TestCase):
    def test_roundtrip(self):
        for text in ["plain", 'a "quoted" title', "back\\slash", "tab\there", "new\nline",
                     "ünïcödé — 日本語", "emoji 🎵", "ctrl\x01char", ""]:
            with self.subTest(text=text):
                self.assertEqual(helper.go_unquote(helper.go_quote(text)), text)

    def test_quote_matches_go_for_simple_strings(self):
        self.assertEqual(helper.go_quote('a"b'), '"a\\"b"')
        self.assertEqual(helper.go_quote("x\ny"), '"x\\ny"')


class EntryTests(unittest.TestCase):
    TRACK = {"path": "/music/a.flac", "title": "A", "artist": "Artist", "year": 1999,
             "provider_meta": {"id": "1"}}

    def test_new_entry_fields(self):
        text = helper.new_entry(self.TRACK)
        self.assertTrue(text.startswith("[[entry]]\n"))
        self.assertIn('path = "/music/a.flac"', text)
        self.assertIn('artist = "Artist"', text)
        self.assertIn("year = 1999", text)
        self.assertIn('provider_meta.id = "1"', text)

    def test_split_entries_decodes_paths(self):
        text = helper.new_entry(self.TRACK) + "\n" + helper.new_entry({"path": 'x "y"', "title": "T"})
        self.assertEqual([p for p, _ in helper.split_entries(text)], ["/music/a.flac", 'x "y"'])


class ToggleTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.old_env = os.environ.get("CLIAMP_CONFIG_DIR")
        os.environ["CLIAMP_CONFIG_DIR"] = self.dir.name
        self.old_current = helper.current_track
        self.track = {"path": "/music/one.mp3", "title": "One"}
        helper.current_track = lambda expected="": self.track

    def tearDown(self):
        helper.current_track = self.old_current
        if self.old_env is None:
            os.environ.pop("CLIAMP_CONFIG_DIR", None)
        else:
            os.environ["CLIAMP_CONFIG_DIR"] = self.old_env
        self.dir.cleanup()

    def paths(self):
        return [p for p, _ in helper.split_entries(helper.read_favs())]

    def test_toggle_adds_then_removes_and_keeps_others(self):
        self.assertEqual(helper.toggle_fav(""), {"ok": True, "fav": True})
        self.track = {"path": "/music/two.mp3", "title": "Two"}
        self.assertTrue(helper.toggle_fav("")["fav"])
        self.assertEqual(self.paths(), ["/music/two.mp3", "/music/one.mp3"])
        self.assertFalse(helper.toggle_fav("")["fav"])
        self.assertEqual(self.paths(), ["/music/one.mp3"])
        self.assertTrue(helper.is_fav("/music/one.mp3"))

    def test_refuses_unsafe_file_names(self):
        self.track = {"path": "/music/bad�.mp3", "title": "Bad"}
        with self.assertRaises(helper.Fail):
            helper.toggle_fav("")


class ManifestTests(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(ROOT, "manifest.json")) as f:
            self.manifest = json.load(f)

    def test_entry_points_exist(self):
        for path in self.manifest["entryPoints"].values():
            self.assertTrue(os.path.isfile(os.path.join(ROOT, path)), path)

    def test_kinds_match_entry_points(self):
        self.assertEqual(sorted(self.manifest["kinds"]), ["bar-widget", "service"])
        self.assertIn("service", self.manifest["entryPoints"])

    def test_settings_have_defaults(self):
        bar = self.manifest["barWidget"]
        self.assertEqual(sorted(bar["defaults"]), sorted(item["key"] for item in bar["schema"]))


if __name__ == "__main__":
    unittest.main()

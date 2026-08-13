import json
import tempfile
import unittest
from pathlib import Path

from dreeve_ha import options


class ReadTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def write(self, payload):
        path = self.root / "options.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_defaults_every_missing_option(self):
        result = options.read(self.write({}))

        self.assertEqual(result["wahoo_client_id"], "")
        self.assertEqual(result["sync_time_window"], "1_week")
        self.assertEqual(result["sync_cron"], "0 * * * *")
        self.assertEqual(result["extra_env"], [])

    def test_strips_surrounding_whitespace(self):
        # A pasted client ID carrying a trailing newline is far likelier than a credential that
        # legitimately ends in whitespace.
        result = options.read(self.write({"wahoo_client_id": "  abc-123  "}))

        self.assertEqual(result["wahoo_client_id"], "abc-123")

    def test_drops_unknown_keys(self):
        result = options.read(self.write({"wahoo_client_id": "abc-123", "nonsense": "x"}))

        self.assertNotIn("nonsense", result)

    def test_null_values_read_as_the_empty_default(self):
        result = options.read(self.write({"redirect_uri": None, "extra_env": None}))

        self.assertEqual(result["redirect_uri"], "")
        self.assertEqual(result["extra_env"], [])

    def test_extra_env_items_become_strings(self):
        result = options.read(self.write({"extra_env": ["A=1", 2]}))

        self.assertEqual(result["extra_env"], ["A=1", "2"])

    def test_an_unreadable_or_unusable_file_falls_back_to_defaults(self):
        # json.loads happily returns a list or a string, neither of which has .get(); a missing file
        # is normal in the host test run. Neither may crash the add-on at boot.
        broken = self.root / "broken.json"
        broken.write_text("[1, 2, 3]", encoding="utf-8")
        for path in (self.root / "absent.json", broken):
            with self.subTest(path=path):
                result = options.read(path)

                self.assertEqual(result["wahoo_client_id"], "")
                self.assertEqual(result["sync_time_window"], "1_week")


if __name__ == "__main__":
    unittest.main()

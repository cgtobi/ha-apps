import json
import tempfile
import unittest
from pathlib import Path

from dreeve_ha import options


class ReadTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "options.json"

    def write(self, payload):
        self.path.write_text(json.dumps(payload), encoding="utf-8")
        return self.path

    def test_missing_file_yields_defaults(self):
        result = options.read(self.path)

        self.assertEqual(result["since"], "-30d")
        self.assertEqual(result["log_level"], "info")
        self.assertEqual(result["polar_client_id"], "")
        self.assertEqual(result["extra_env"], [])

    def test_values_are_read_and_stripped(self):
        result = options.read(self.write({"polar_client_id": "  abc-123  "}))

        self.assertEqual(result["polar_client_id"], "abc-123")

    def test_unknown_keys_are_ignored(self):
        result = options.read(self.write({"nonsense": "value"}))

        self.assertNotIn("nonsense", result)

    def test_null_value_falls_back_to_default_shape(self):
        result = options.read(self.write({"public_url": None, "extra_env": None}))

        self.assertEqual(result["public_url"], "")
        self.assertEqual(result["extra_env"], [])

    def test_extra_env_entries_are_strings(self):
        result = options.read(self.write({"extra_env": ["POLL_INTERVAL=7200", 5]}))

        self.assertEqual(result["extra_env"], ["POLL_INTERVAL=7200", "5"])

    def test_unparsable_file_yields_defaults(self):
        self.path.write_text("not json at all", encoding="utf-8")

        result = options.read(self.path)

        self.assertEqual(result["since"], "-30d")
        self.assertEqual(result["extra_env"], [])

    def test_json_that_is_not_an_object_yields_defaults(self):
        # json.loads succeeds for these, so the except clause never fires and the result would be
        # asked for .get() - which lists, strings and None do not have.
        for payload in ("null", "[]", '"text"', "42"):
            with self.subTest(payload=payload):
                self.path.write_text(payload, encoding="utf-8")

                result = options.read(self.path)

                self.assertEqual(result["since"], "-30d")
                self.assertEqual(result["polar_client_id"], "")


if __name__ == "__main__":
    unittest.main()

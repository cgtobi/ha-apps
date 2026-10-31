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

    def test_weight_sync_is_off_and_kilograms_by_default(self):
        result = options.read(self.path)

        self.assertIs(result["weight_sync"], False)
        self.assertEqual(result["weight_unit"], "kg")
        self.assertEqual(result["dreeve_api_key"], "")
        self.assertEqual(result["dreeve_url"], "")

    def test_a_boolean_option_stays_a_boolean(self):
        # str(True) is "True", which nothing downstream would read as switched on.
        self.assertIs(options.read(self.write({"weight_sync": True}))["weight_sync"], True)
        self.assertIs(options.read(self.write({"weight_sync": False}))["weight_sync"], False)

    def test_a_boolean_option_only_accepts_true(self):
        # The schema says bool; anything else is a hand-edited file, and "off" is the safe reading.
        for value in ("true", 1, "yes", None):
            with self.subTest(value=value):
                self.assertIs(options.read(self.write({"weight_sync": value}))["weight_sync"], False)

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

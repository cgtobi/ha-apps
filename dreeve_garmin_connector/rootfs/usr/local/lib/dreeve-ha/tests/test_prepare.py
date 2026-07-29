import json
import tempfile
import unittest
from pathlib import Path

from dreeve_ha import prepare


class RunTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.options_file = self.root / "options.json"
        self.env_file = self.root / "dreeve-ha.env"
        self.addon_configs = self.root / "addon_configs"
        (self.addon_configs / "local_statistics_for_strava" / "watch").mkdir(parents=True)
        self.logged = []

    def write_options(self, payload):
        self.options_file.write_text(json.dumps(payload), encoding="utf-8")

    def run_prepare(self):
        return prepare.run(
            options_file=self.options_file,
            env_file=self.env_file,
            addon_configs=self.addon_configs,
            data_dirs=[self.root / "tokens", self.root / "state"],
            log=self.logged.append,
        )

    def test_writes_a_sourceable_env_file_and_returns_zero(self):
        self.write_options({"garmin_email": "me@example.com", "garmin_password": "se cret"})

        exit_code = self.run_prepare()

        self.assertEqual(exit_code, 0)
        content = self.env_file.read_text(encoding="utf-8")
        self.assertIn("export GARMIN_EMAIL=me@example.com\n", content)
        self.assertIn("export GARMIN_PASSWORD='se cret'\n", content)
        self.assertIn(
            "export WATCH_DIR={0}\n".format(
                self.addon_configs / "local_statistics_for_strava" / "watch"
            ),
            content,
        )

    def test_the_env_file_is_not_world_readable(self):
        self.write_options({"garmin_email": "me@example.com"})

        self.run_prepare()

        self.assertEqual(self.env_file.stat().st_mode & 0o777, 0o600)

    def test_creates_the_persistent_directories(self):
        self.write_options({"garmin_email": "me@example.com"})

        self.run_prepare()

        self.assertTrue((self.root / "tokens").is_dir())
        self.assertTrue((self.root / "state").is_dir())

    def test_reports_extra_env_warnings(self):
        self.write_options({"garmin_email": "me@example.com", "extra_env": ["WATCH_DIR=/tmp/x"]})

        self.run_prepare()

        self.assertTrue(any("WATCH_DIR" in message for message in self.logged))

    def test_fails_when_the_watch_dir_cannot_be_resolved(self):
        self.write_options({"garmin_email": "me@example.com"})
        for path in self.addon_configs.glob("*/watch"):
            path.rmdir()

        exit_code = self.run_prepare()

        self.assertEqual(exit_code, 1)
        self.assertFalse(self.env_file.exists())
        self.assertTrue(any("expose_share" in message for message in self.logged))


if __name__ == "__main__":
    unittest.main()

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
        self.write_options({"polar_client_id": "abc-123", "polar_client_secret": "se cret"})

        exit_code = self.run_prepare()

        self.assertEqual(exit_code, 0)
        content = self.env_file.read_text(encoding="utf-8")
        self.assertIn("export POLAR_CLIENT_ID=abc-123\n", content)
        self.assertIn("export POLAR_CLIENT_SECRET='se cret'\n", content)
        self.assertIn(
            "export WATCH_DIR={0}\n".format(
                self.addon_configs / "local_statistics_for_strava" / "watch"
            ),
            content,
        )

    def test_the_env_file_is_not_world_readable(self):
        self.write_options({"polar_client_id": "abc-123"})

        self.run_prepare()

        self.assertEqual(self.env_file.stat().st_mode & 0o777, 0o600)

    def test_creates_the_persistent_directories(self):
        self.write_options({"polar_client_id": "abc-123"})

        self.run_prepare()

        self.assertTrue((self.root / "tokens").is_dir())
        self.assertTrue((self.root / "state").is_dir())

    def test_reports_extra_env_warnings(self):
        self.write_options({"polar_client_id": "abc-123", "extra_env": ["WATCH_DIR=/tmp/x"]})

        self.run_prepare()

        self.assertTrue(any("WATCH_DIR" in message for message in self.logged))

    def test_notes_a_missing_public_url_without_failing(self):
        # Legitimate when the Polar client has exactly one registered redirect URL, so this is a note
        # rather than a refusal - but it is the single likeliest reason authorization fails.
        self.write_options({"polar_client_id": "abc-123"})

        exit_code = self.run_prepare()

        self.assertEqual(exit_code, 0)
        self.assertTrue(any("public_url" in message for message in self.logged))

    def test_stays_quiet_about_public_url_when_it_is_set(self):
        self.write_options({"polar_client_id": "abc-123", "public_url": "http://ha.local:8080"})

        self.run_prepare()

        self.assertFalse(any("public_url" in message for message in self.logged))

    def test_stays_quiet_when_only_the_redirect_uri_is_set(self):
        # That option names the redirect URL outright, so the fallback the note warns about - Polar
        # picking the client's single registered URL - cannot apply.
        self.write_options({"polar_client_id": "abc-123", "redirect_uri": "http://ha.local:8080"})

        self.run_prepare()

        self.assertFalse(any("NOTE:" in message for message in self.logged))

    def test_fails_when_the_watch_dir_cannot_be_resolved(self):
        self.write_options({"polar_client_id": "abc-123"})
        for path in self.addon_configs.glob("*/watch"):
            path.rmdir()

        exit_code = self.run_prepare()

        self.assertEqual(exit_code, 1)
        self.assertFalse(self.env_file.exists())
        self.assertTrue(any("expose_share" in message for message in self.logged))


if __name__ == "__main__":
    unittest.main()

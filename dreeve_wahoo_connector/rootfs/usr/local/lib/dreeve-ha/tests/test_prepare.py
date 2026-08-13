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
            data_dirs=[self.root / "downloads", self.root / "state"],
            log=self.logged.append,
        )

    def test_writes_an_export_line_per_variable_and_returns_zero(self):
        self.write_options(
            {
                "wahoo_client_id": "abc-123",
                "wahoo_client_secret": "se cret",
                "redirect_uri": "http://ha.local:8085/callback",
            }
        )

        exit_code = self.run_prepare()

        self.assertEqual(exit_code, 0)
        content = self.env_file.read_text(encoding="utf-8")
        self.assertIn("export WAHOO_CLIENT_ID=abc-123\n", content)
        self.assertIn("export WAHOO_CLIENT_SECRET='se cret'\n", content)
        self.assertIn("export WAHOO_REDIRECT_URI=http://ha.local:8085/callback\n", content)
        self.assertIn(
            "export DREEVE_WATCH_DIR={0}\n".format(
                self.addon_configs / "local_statistics_for_strava" / "watch"
            ),
            content,
        )

    def test_the_env_file_is_not_world_readable(self):
        self.write_options({"wahoo_client_id": "abc-123"})

        self.run_prepare()

        self.assertEqual(self.env_file.stat().st_mode & 0o777, 0o600)

    def test_creates_the_persistent_directories(self):
        # /data/downloads is upstream's own, and the relay's source; /data/state holds the relay
        # ledger.
        self.write_options({"wahoo_client_id": "abc-123"})

        self.run_prepare()

        self.assertTrue((self.root / "downloads").is_dir())
        self.assertTrue((self.root / "state").is_dir())

    def test_reports_extra_env_warnings(self):
        self.write_options({"wahoo_client_id": "abc-123", "extra_env": ["DATA_DIR=/tmp/x"]})

        self.run_prepare()

        self.assertTrue(any("DATA_DIR" in message for message in self.logged))

    def test_notes_a_missing_redirect_uri_without_failing(self):
        # Nothing can be authorized until it is set, but the dashboard still comes up and the option
        # is the one thing the log should name.
        self.write_options({"wahoo_client_id": "abc-123"})

        exit_code = self.run_prepare()

        self.assertEqual(exit_code, 0)
        self.assertTrue(any("redirect_uri" in message for message in self.logged))

    def test_notes_that_an_https_redirect_turns_the_dashboard_into_https(self):
        # Upstream generates a self-signed certificate for an https redirect, which leaves the
        # add-on's http:// webui link answering nothing and costs the status loop a failed attempt
        # every cycle. A legitimate configuration when Wahoo's portal refuses plain HTTP, so it is a
        # note rather than a refusal - but it has to be said, or the dead button names nothing.
        self.write_options(
            {"wahoo_client_id": "abc-123", "redirect_uri": "https://ha.local:8085/callback"}
        )

        exit_code = self.run_prepare()

        self.assertEqual(exit_code, 0)
        notes = [message for message in self.logged if "NOTE:" in message]
        self.assertEqual(len(notes), 1)
        self.assertIn("https://", notes[0])

    def test_stays_quiet_about_the_redirect_uri_when_it_is_set(self):
        self.write_options(
            {"wahoo_client_id": "abc-123", "redirect_uri": "http://ha.local:8085/callback"}
        )

        self.run_prepare()

        self.assertFalse(any("NOTE:" in message for message in self.logged))

    def test_fails_when_the_watch_dir_cannot_be_resolved(self):
        self.write_options({"wahoo_client_id": "abc-123"})
        for path in self.addon_configs.glob("*/watch"):
            path.rmdir()

        exit_code = self.run_prepare()

        self.assertEqual(exit_code, 1)
        self.assertFalse(self.env_file.exists())
        self.assertTrue(any("expose_share" in message for message in self.logged))


if __name__ == "__main__":
    unittest.main()

import os
import tempfile
import unittest
from pathlib import Path

from dreeve_ha import watchdir


class ResolveTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.addon_configs = Path(self.directory.name)

    def make_dreeve_watch(self, slug):
        path = self.addon_configs / slug / "watch"
        path.mkdir(parents=True)
        return path

    def test_configured_value_wins_over_auto_detection(self):
        # No dreeve watch dir is set up under addon_configs here, so if resolve() fell through to
        # auto-detection instead of honouring the configured value, this would raise instead.
        configured = self.addon_configs / "configured"
        configured.mkdir()

        result = watchdir.resolve(str(configured), addon_configs=self.addon_configs)

        self.assertEqual(result, configured)

    def test_auto_detects_a_single_local_install(self):
        expected = self.make_dreeve_watch("local_statistics_for_strava")

        result = watchdir.resolve("", addon_configs=self.addon_configs)

        self.assertEqual(result, expected)

    def test_auto_detects_a_repository_install_with_a_hash_prefix(self):
        expected = self.make_dreeve_watch("a1b2c3d4_statistics_for_strava")

        result = watchdir.resolve("", addon_configs=self.addon_configs)

        self.assertEqual(result, expected)

    def test_ignores_a_dreeve_config_dir_without_a_watch_folder(self):
        (self.addon_configs / "local_statistics_for_strava").mkdir()

        with self.assertRaises(watchdir.WatchDirUnresolvable) as caught:
            watchdir.resolve("", addon_configs=self.addon_configs)

        self.assertIn("expose_share", str(caught.exception))

    def test_ignores_unrelated_addons(self):
        (self.addon_configs / "core_samba" / "watch").mkdir(parents=True)

        with self.assertRaises(watchdir.WatchDirUnresolvable):
            watchdir.resolve("", addon_configs=self.addon_configs)

    def test_ignores_entries_that_are_not_directories(self):
        # A matching name that is a file, and a slug dir whose "watch" is a file. Both must be
        # rejected rather than returned as a path nothing can be written into.
        (self.addon_configs / "aaaa_statistics_for_strava").write_text("", encoding="utf-8")
        (self.addon_configs / "bbbb_statistics_for_strava").mkdir()
        (self.addon_configs / "bbbb_statistics_for_strava" / "watch").write_text(
            "", encoding="utf-8"
        )

        with self.assertRaises(watchdir.WatchDirUnresolvable):
            watchdir.resolve("", addon_configs=self.addon_configs)

    def test_several_candidates_are_an_error_naming_them_in_a_stable_order(self):
        self.make_dreeve_watch("local_statistics_for_strava")
        self.make_dreeve_watch("a1b2c3d4_statistics_for_strava")

        with self.assertRaises(watchdir.WatchDirUnresolvable) as caught:
            watchdir.resolve("", addon_configs=self.addon_configs)

        message = str(caught.exception)
        self.assertIn("local_statistics_for_strava", message)
        self.assertIn("a1b2c3d4_statistics_for_strava", message)
        self.assertIn("watch_dir", message)
        # Sorted, not in directory-entry order: the message has to read the same on every run and on
        # every filesystem, or the same problem produces different support reports.
        self.assertLess(
            message.index("a1b2c3d4_statistics_for_strava"),
            message.index("local_statistics_for_strava"),
        )

    def test_a_configured_directory_that_does_not_exist_is_rejected(self):
        with self.assertRaises(watchdir.WatchDirUnresolvable) as caught:
            watchdir.resolve(str(self.addon_configs / "nope"), addon_configs=self.addon_configs)

        self.assertIn("does not exist", str(caught.exception))

    @unittest.skipIf(os.geteuid() == 0, "root ignores mode bits, so this cannot be exercised as root")
    def test_an_unwritable_watch_folder_is_rejected(self):
        watch = self.make_dreeve_watch("local_statistics_for_strava")
        watch.chmod(0o500)
        self.addCleanup(watch.chmod, 0o700)

        with self.assertRaises(watchdir.WatchDirUnresolvable) as caught:
            watchdir.resolve("", addon_configs=self.addon_configs)

        self.assertIn("not writable", str(caught.exception))


if __name__ == "__main__":
    unittest.main()

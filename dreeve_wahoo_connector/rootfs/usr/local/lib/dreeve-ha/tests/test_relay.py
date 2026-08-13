import json
import tempfile
import unittest
from pathlib import Path

from dreeve_ha import relay


class RelayTestCase(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.downloads = self.root / "downloads"
        self.watch = self.root / "watch"
        self.downloads.mkdir()
        self.watch.mkdir()
        self.ledger = self.root / "state" / "relayed.json"

    def download(self, name, payload=b"fit-bytes"):
        (self.downloads / name).write_bytes(payload)
        return name


class PendingTest(RelayTestCase):
    def test_lists_undelivered_fit_files_in_a_stable_order(self):
        self.download("2026-08-11_workout_2.fit")
        self.download("2026-08-12_workout_3.fit")

        self.assertEqual(
            relay.pending(self.downloads, set()),
            ["2026-08-11_workout_2.fit", "2026-08-12_workout_3.fit"],
        )

    def test_skips_what_the_ledger_already_records(self):
        self.download("a.fit")
        self.download("b.fit")

        self.assertEqual(relay.pending(self.downloads, {"a.fit"}), ["b.fit"])

    def test_ignores_everything_that_is_not_a_fit_file(self):
        # Upstream downloads to <name>.fit.tmp and renames it into place, so a .tmp is a download in
        # flight: copying it would hand Dreeve a partial file.
        self.download("a.fit.tmp")
        self.download("sync_history.json")

        self.assertEqual(relay.pending(self.downloads, set()), [])

    def test_an_absent_downloads_directory_is_not_an_error(self):
        # True on the very first boot, before upstream has created it.
        self.assertEqual(relay.pending(self.root / "absent", set()), [])


class DeliverTest(RelayTestCase):
    def test_copies_the_file_into_the_watch_folder(self):
        self.download("a.fit", b"payload")

        relay.deliver("a.fit", self.downloads, self.watch)

        self.assertEqual((self.watch / "a.fit").read_bytes(), b"payload")

    def test_leaves_the_source_in_place(self):
        # The whole point: upstream's deduplication asks whether this file still exists, and Dreeve
        # deletes the copy it imports.
        self.download("a.fit")

        relay.deliver("a.fit", self.downloads, self.watch)

        self.assertTrue((self.downloads / "a.fit").exists())

    def test_leaves_no_temporary_file_behind(self):
        self.download("a.fit")

        relay.deliver("a.fit", self.downloads, self.watch)

        self.assertEqual(sorted(entry.name for entry in self.watch.iterdir()), ["a.fit"])


class RelayOnceTest(RelayTestCase):
    def setUp(self):
        super().setUp()
        self.emitted = []
        self.warned = []
        self.reported = set()

    def relay_once(self, delivered):
        return relay.relay_once(
            self.downloads,
            self.watch,
            delivered,
            ledger=self.ledger,
            emit=self.emitted.append,
            warn=self.warned.append,
            reported=self.reported,
        )

    def fail_to_deliver(self, *names):
        """Makes deliver() raise for these names only, leaving the rest a real copy."""
        original = relay.deliver

        def failing(name, downloads_dir, watch_dir):
            if name in names:
                raise OSError("gone")
            return original(name, downloads_dir, watch_dir)

        relay.deliver = failing
        self.addCleanup(setattr, relay, "deliver", original)

    def test_delivers_and_records_a_new_file(self):
        self.download("a.fit")
        delivered = set()

        handled = self.relay_once(delivered)

        self.assertEqual(handled, ["a.fit"])
        self.assertTrue((self.watch / "a.fit").exists())
        self.assertEqual(delivered, {"a.fit"})
        self.assertEqual(json.loads(self.ledger.read_text(encoding="utf-8")), ["a.fit"])
        self.assertTrue(any("a.fit" in line for line in self.emitted))

    def test_does_not_deliver_the_same_file_twice(self):
        self.download("a.fit")
        delivered = set()
        self.relay_once(delivered)
        (self.watch / "a.fit").unlink()  # Dreeve imported it

        handled = self.relay_once(delivered)

        self.assertEqual(handled, [])
        self.assertFalse((self.watch / "a.fit").exists())

    def test_a_later_process_skips_what_an_earlier_one_delivered(self):
        # The whole reason the ledger is on disk: the delivered set lives in memory, the relay
        # restarts with the add-on, and /data/downloads keeps every file it ever received. A fresh
        # process that trusted the directory alone would re-deliver the whole history on its first
        # pass.
        self.download("a.fit")
        self.relay_once(set())
        (self.watch / "a.fit").unlink()  # Dreeve imported it

        handled = self.relay_once(relay.read_ledger(self.ledger))

        self.assertEqual(handled, [])
        self.assertFalse((self.watch / "a.fit").exists())

    def test_writes_no_ledger_when_there_was_nothing_to_do(self):
        self.assertEqual(self.relay_once(set()), [])
        self.assertFalse(self.ledger.exists())

    def test_one_undeliverable_file_does_not_block_the_ones_behind_it(self):
        # pending() is sorted, so without a per-file guard a file that permanently fails to copy
        # holds up every workout lexicographically after it, for as long as it sits in the downloads
        # directory - which is never pruned.
        self.download("a.fit")
        self.download("b.fit")
        self.download("c.fit")
        self.fail_to_deliver("b.fit")
        delivered = set()

        handled = self.relay_once(delivered)

        self.assertEqual(handled, ["a.fit", "c.fit"])
        self.assertTrue((self.watch / "c.fit").exists())
        self.assertEqual(delivered, {"a.fit", "c.fit"})

    def test_the_ledger_records_exactly_what_was_delivered(self):
        # The file that failed must stay out of the ledger, or it would never be retried.
        self.download("a.fit")
        self.download("b.fit")
        self.download("c.fit")
        self.fail_to_deliver("b.fit")

        self.relay_once(set())

        self.assertEqual(json.loads(self.ledger.read_text(encoding="utf-8")), ["a.fit", "c.fit"])

    def test_the_failure_is_logged_naming_the_file(self):
        self.download("b.fit")
        self.fail_to_deliver("b.fit")

        self.relay_once(set())

        self.assertEqual(len(self.warned), 1)
        self.assertIn("b.fit", self.warned[0])

    def test_a_permanent_failure_is_not_logged_on_every_pass(self):
        # Once a poll every 15 seconds, a file that can never be copied would otherwise fill the log
        # with the same line and bury everything worth reading.
        self.download("b.fit")
        self.fail_to_deliver("b.fit")
        delivered = set()
        self.relay_once(delivered)

        self.relay_once(delivered)

        self.assertEqual(len(self.warned), 1)

    def test_a_failing_ledger_write_is_logged_rather_than_raised(self):
        # Raising here would climb out of the finally block and replace whatever the pass was
        # already reporting with a less informative error about bookkeeping.
        self.download("a.fit")
        original = relay.write_ledger

        def failing(delivered, path=relay.LEDGER):
            raise OSError("read-only state directory")

        relay.write_ledger = failing
        self.addCleanup(setattr, relay, "write_ledger", original)

        handled = self.relay_once(set())

        self.assertEqual(handled, ["a.fit"])
        self.assertTrue(any("read-only state directory" in line for line in self.warned))


class LedgerTest(RelayTestCase):
    def test_round_trips(self):
        relay.write_ledger({"b.fit", "a.fit"}, path=self.ledger)

        self.assertEqual(relay.read_ledger(self.ledger), {"a.fit", "b.fit"})

    def test_overwrites_a_truncated_ledger_completely(self):
        # The relay is a background child killed on add-on stop, so a write interrupted mid-way
        # leaves a short file that reads as empty - after which every .fit still in the never-pruned
        # downloads directory is delivered again, potentially months of history in one burst.
        self.ledger.parent.mkdir(parents=True, exist_ok=True)
        self.ledger.write_text('["a-very-long-name-from-an-earlier-write.fit"]', encoding="utf-8")

        relay.write_ledger({"a.fit"}, path=self.ledger)

        self.assertEqual(relay.read_ledger(self.ledger), {"a.fit"})

    def test_leaves_no_temporary_file_behind(self):
        relay.write_ledger({"a.fit"}, path=self.ledger)

        self.assertEqual(
            sorted(entry.name for entry in self.ledger.parent.iterdir()), ["relayed.json"]
        )

    def test_a_reader_never_sees_a_half_written_ledger(self):
        # The ledger path must hold either the whole previous list or the whole new one at every
        # instant, because the only reader that matters is the next process after a kill. Checked at
        # the one moment the file changes: the previous content is still complete there, so the new
        # content was assembled elsewhere first.
        self.ledger.parent.mkdir(parents=True, exist_ok=True)
        relay.write_ledger({"a.fit"}, path=self.ledger)
        original_replace = relay.os.replace
        observed = []

        def replace(source, destination):
            observed.append(Path(destination).read_text(encoding="utf-8"))
            return original_replace(source, destination)

        relay.os.replace = replace
        self.addCleanup(setattr, relay.os, "replace", original_replace)

        relay.write_ledger({"a.fit", "b.fit"}, path=self.ledger)

        self.assertEqual(observed, ['["a.fit"]'])
        self.assertEqual(relay.read_ledger(self.ledger), {"a.fit", "b.fit"})

    def test_an_absent_ledger_reads_as_empty(self):
        self.assertEqual(relay.read_ledger(self.ledger), set())

    def test_a_damaged_ledger_reads_as_empty_rather_than_failing(self):
        # Re-delivering a file is harmless - Dreeve skips a workout it already imported - while
        # refusing to start is not.
        self.ledger.parent.mkdir(parents=True, exist_ok=True)
        for content in ("not json", '{"a.fit": true}'):
            with self.subTest(content=content):
                self.ledger.write_text(content, encoding="utf-8")

                self.assertEqual(relay.read_ledger(self.ledger), set())


class StopLooping(Exception):
    """Breaks main()'s infinite loop from the injected sleep, so the loop itself can be tested."""


class MainTest(RelayTestCase):
    def run_main(self, iterations):
        performed = {"sleeps": 0}

        def sleep(seconds):
            performed["sleeps"] += 1
            if performed["sleeps"] >= iterations:
                raise StopLooping()

        with self.assertRaises(StopLooping):
            relay.main(
                poll_seconds=0,
                sleep=sleep,
                downloads_dir=self.downloads,
                watch_dir=self.watch,
                ledger=self.ledger,
            )
        return performed["sleeps"]

    def test_delivers_on_the_first_pass_before_sleeping(self):
        self.download("a.fit")

        with self.assertLogs("dreeve-ha.relay", level="INFO"):
            self.assertEqual(self.run_main(iterations=1), 1)

        self.assertTrue((self.watch / "a.fit").exists())

    def fail_to_list_the_downloads(self):
        """Breaks a whole pass rather than one file, which is what main's own guard is there for.

        A single undeliverable file is handled inside relay_once now, so the loop-level guard has to
        be driven by something that fails before any file is reached - an unreadable downloads
        directory.
        """
        original = relay.pending

        def failing(downloads_dir, delivered):
            raise PermissionError("cannot list the downloads directory")

        relay.pending = failing
        self.addCleanup(setattr, relay, "pending", original)

    def test_a_failing_pass_does_not_kill_the_loop(self):
        # A dead relay delivers nothing and logs nothing, which reads exactly like "no new workouts".
        self.fail_to_list_the_downloads()

        with self.assertLogs("dreeve-ha.relay", level="WARNING") as captured:
            self.run_main(iterations=2)

        self.assertTrue(any("still trying" in line for line in captured.output))

    def test_the_same_error_is_not_logged_every_pass(self):
        self.fail_to_list_the_downloads()

        with self.assertLogs("dreeve-ha.relay", level="WARNING") as captured:
            self.run_main(iterations=3)

        warnings = [line for line in captured.output if "still trying" in line]
        self.assertEqual(len(warnings), 1)

    def test_an_undeliverable_file_is_reported_once_across_passes(self):
        # The de-duplication has to survive between passes, or the 15-second poll turns one broken
        # file into a warning every 15 seconds.
        self.download("a.fit")
        self.watch.rmdir()

        with self.assertLogs("dreeve-ha.relay", level="WARNING") as captured:
            self.run_main(iterations=3)

        warnings = [line for line in captured.output if "a.fit" in line]
        self.assertEqual(len(warnings), 1)

    def test_takes_the_watch_folder_from_dreeve_watch_dir(self):
        # Not WATCH_DIR: that name belongs to a planned upstream change, and this add-on must not
        # export it while the relay is the thing doing the delivering.
        self.download("a.fit")

        def sleep(seconds):
            raise StopLooping()

        with self.assertLogs("dreeve-ha.relay", level="INFO"):
            with self.assertRaises(StopLooping):
                relay.main(
                    poll_seconds=0,
                    sleep=sleep,
                    downloads_dir=self.downloads,
                    ledger=self.ledger,
                    environ={"DREEVE_WATCH_DIR": str(self.watch)},
                )

        self.assertTrue((self.watch / "a.fit").exists())

    def test_takes_the_downloads_folder_from_the_same_place_as_the_ledger(self):
        # The ledger path is frozen to env.STATE_DIR at import, so reading DATA_DIR from the process
        # environment here would be the one asymmetry in an otherwise add-on-owned pair of paths.
        self.download("a.fit")
        original = relay.env.DOWNLOADS_DIR
        relay.env.DOWNLOADS_DIR = self.downloads
        self.addCleanup(setattr, relay.env, "DOWNLOADS_DIR", original)

        def sleep(seconds):
            raise StopLooping()

        with self.assertLogs("dreeve-ha.relay", level="INFO"):
            with self.assertRaises(StopLooping):
                relay.main(
                    poll_seconds=0,
                    sleep=sleep,
                    ledger=self.ledger,
                    environ={
                        "DREEVE_WATCH_DIR": str(self.watch),
                        "DATA_DIR": str(self.root / "ignored"),
                    },
                )

        self.assertTrue((self.watch / "a.fit").exists())

    def test_refuses_to_run_without_a_watch_dir(self):
        # ha-start.sh sources DREEVE_WATCH_DIR from the env file prepare.py wrote; without it there is
        # nowhere to deliver, and a silent no-op loop would look like a working relay.
        #
        # The sleep raises and the downloads directory is this test's own, so a regressed guard
        # fails here instead of spinning forever against the host's real /data/downloads.
        def sleep(seconds):
            raise StopLooping()

        with self.assertLogs("dreeve-ha.relay", level="ERROR"):
            exit_code = relay.main(
                environ={}, sleep=sleep, downloads_dir=self.downloads, ledger=self.ledger
            )

        self.assertEqual(exit_code, 1)


if __name__ == "__main__":
    unittest.main()

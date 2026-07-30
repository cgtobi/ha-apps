import logging
import unittest

from dreeve_ha import statusloop


class Completed:
    def __init__(self, returncode, stdout):
        self.returncode = returncode
        self.stdout = stdout


def runner(returncode, stdout):
    def run(command, **kwargs):
        return Completed(returncode, stdout)

    return run


class SummarizeTest(unittest.TestCase):
    def test_reduces_the_payload_to_the_fields_that_matter(self):
        line = statusloop.summarize(
            {
                "healthy": True,
                "authorization": "ok",
                "authorizeUrl": None,
                "backlog": 42,
                "lastSuccessfulSync": "2026-07-29T10:00:00+00:00",
                "nextRunAt": "2026-07-29T10:15:00+00:00",
                "backoffSeconds": 0,
                "lastError": None,
                "cycles": 7,
            }
        )

        # Significant fields first, then the two that move every cycle - the same split the
        # change-detection uses, so the line reads in the order it is reasoned about.
        self.assertEqual(
            line,
            "healthy=True authorization=ok authorizeUrl=None backlog=42 backoffSeconds=0 "
            "lastError=None lastSuccessfulSync=2026-07-29T10:00:00+00:00 "
            "nextRunAt=2026-07-29T10:15:00+00:00",
        )

    def test_an_unauthorized_connector_reports_the_url_to_open(self):
        line = statusloop.summarize(
            {
                "healthy": False,
                "authorization": "required",
                "authorizeUrl": "http://ha.local:8080/authorize",
            }
        )

        self.assertIn("authorization=required", line)
        self.assertIn("authorizeUrl=http://ha.local:8080/authorize", line)

    def test_missing_fields_render_as_none(self):
        self.assertIn("backlog=None", statusloop.summarize({"healthy": False}))


class ReadStatusTest(unittest.TestCase):
    def test_parses_the_command_output(self):
        payload = statusloop.read_status(run=runner(0, '{"healthy": true}'))

        self.assertEqual(payload, {"healthy": True})

    def test_a_failed_command_yields_nothing(self):
        self.assertIsNone(statusloop.read_status(run=runner(1, "")))

    def test_unparsable_output_yields_nothing(self):
        self.assertIsNone(statusloop.read_status(run=runner(0, "not json")))


class LevelTest(unittest.TestCase):
    def test_reads_the_addons_log_level(self):
        self.assertEqual(statusloop.level({"LOG_LEVEL": "warning"}), logging.WARNING)
        self.assertEqual(statusloop.level({"LOG_LEVEL": " DEBUG "}), logging.DEBUG)

    def test_falls_back_to_info(self):
        # Unset, blank or nonsense: the status line is the only sign of progress during a backfill,
        # so an unreadable value must not silence it.
        for environ in ({}, {"LOG_LEVEL": ""}, {"LOG_LEVEL": "chatty"}):
            with self.subTest(environ=environ):
                self.assertEqual(statusloop.level(environ), logging.INFO)


class PollOnceTest(unittest.TestCase):
    def setUp(self):
        self.emitted = []

    def test_emits_a_changed_line(self):
        result = statusloop.poll_once(
            statusloop.signature({"healthy": True}), self.emitted.append, read=lambda: {"healthy": False}
        )

        self.assertEqual(len(self.emitted), 1)
        self.assertEqual(result, statusloop.signature({"healthy": False}))

    def test_stays_silent_when_nothing_changed(self):
        payload = {"healthy": True, "backlog": 0}
        first = statusloop.poll_once(None, self.emitted.append, read=lambda: payload)

        second = statusloop.poll_once(first, self.emitted.append, read=lambda: payload)

        self.assertEqual(len(self.emitted), 1)
        self.assertEqual(second, first)

    def test_a_moved_cycle_timestamp_alone_is_not_worth_a_line(self):
        # These advance every cycle by construction. Comparing them would put a line in the log every
        # POLL_INTERVAL forever, which is what "only log what changed" exists to avoid.
        first = statusloop.poll_once(
            None,
            self.emitted.append,
            read=lambda: {"healthy": True, "backlog": 0, "lastSuccessfulSync": "A", "nextRunAt": "B"},
        )

        second = statusloop.poll_once(
            first,
            self.emitted.append,
            read=lambda: {"healthy": True, "backlog": 0, "lastSuccessfulSync": "C", "nextRunAt": "D"},
        )

        self.assertEqual(len(self.emitted), 1)
        self.assertEqual(second, first)

    def test_the_timestamps_are_still_reported_when_a_line_is_emitted(self):
        statusloop.poll_once(
            None,
            self.emitted.append,
            read=lambda: {"healthy": True, "lastSuccessfulSync": "A", "nextRunAt": "B"},
        )

        self.assertIn("lastSuccessfulSync=A", self.emitted[0])
        self.assertIn("nextRunAt=B", self.emitted[0])

    def test_keeps_the_previous_value_when_the_status_is_unreadable(self):
        previous = statusloop.signature({"healthy": True})

        result = statusloop.poll_once(previous, self.emitted.append, read=lambda: None)

        self.assertEqual(result, previous)
        self.assertEqual(self.emitted, [])


class StopLooping(Exception):
    """Breaks main()'s infinite loop from the injected sleep, so the loop itself can be tested."""


class MainTest(unittest.TestCase):
    def run_main(self, reads, iterations):
        # main() polls before it sleeps, so the sleep that ends the budget lands on the same iteration
        # as the last poll (not one iteration later) - hence >=, not >, or one extra, unbudgeted poll
        # would run past the end of `reads`.
        performed = {"sleeps": 0}

        def sleep(seconds):
            performed["sleeps"] += 1
            if performed["sleeps"] >= iterations:
                raise StopLooping()

        def read():
            item = reads.pop(0)
            if isinstance(item, Exception):
                raise item
            return item

        with self.assertRaises(StopLooping):
            statusloop.main(poll_seconds=0, sleep=sleep, read=read)
        return performed["sleeps"]

    def test_a_raising_read_does_not_kill_the_loop(self):
        # A dead watcher leaves the log quiet, which looks identical to "nothing changed".
        reads = [OSError("boom"), {"healthy": True}, OSError("boom")]

        with self.assertLogs("dreeve-ha.status", level="WARNING") as captured:
            sleeps = self.run_main(reads, iterations=3)

        self.assertEqual(sleeps, 3)
        self.assertEqual(reads, [])
        self.assertTrue(any("still trying" in line for line in captured.output))

    def test_the_same_error_is_not_logged_every_cycle(self):
        reads = [FileNotFoundError("missing"), FileNotFoundError("missing")]

        with self.assertLogs("dreeve-ha.status", level="WARNING") as captured:
            self.run_main(reads, iterations=2)

        warnings = [line for line in captured.output if "still trying" in line]
        self.assertEqual(len(warnings), 1)

    def test_the_first_poll_happens_before_the_first_sleep(self):
        # Waiting a full interval before the first line is indistinguishable from a dead loop.
        reads = [{"healthy": True}]

        with self.assertLogs("dreeve-ha.status", level="INFO") as captured:
            self.run_main(reads, iterations=1)

        self.assertEqual(reads, [])
        self.assertTrue(any("healthy=True" in line for line in captured.output))


if __name__ == "__main__":
    unittest.main()

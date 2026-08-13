import importlib
import ssl
import unittest

from dreeve_ha import env, statusloop


def opener(responses):
    """A stand-in for the URL opener: maps url -> body, or url -> exception to raise."""

    def open_url(url):
        result = responses[url]
        if isinstance(result, Exception):
            raise result
        return result

    return open_url


class SummarizeTest(unittest.TestCase):
    def test_reduces_the_payload_to_the_fields_that_matter(self):
        line = statusloop.summarize(
            statusloop.flatten(
                {
                    "authenticated": True,
                    "cron_expr": "0 * * * *",
                    "is_syncing": False,
                    "last_sync_time": "2026-08-13T10:00:00Z",
                    "next_sync_time": "2026-08-13T11:00:00Z",
                    "last_result": {"status": "success", "errors": []},
                    "total_downloaded": 42,
                    "last_sync_history": "2026-08-13T10:00:03Z",
                }
            )
        )

        self.assertEqual(
            line,
            "authenticated=True next_sync_time=2026-08-13T11:00:00Z "
            "last_sync_history=2026-08-13T10:00:03Z last_result_status=success "
            "total_downloaded=42 is_syncing=False last_result_errors=[]",
        )

    def test_an_unauthorized_connector_is_visible(self):
        line = statusloop.summarize(statusloop.flatten({"authenticated": False}))

        self.assertIn("authenticated=False", line)

    def test_missing_fields_render_as_none(self):
        self.assertIn("next_sync_time=None", statusloop.summarize(statusloop.flatten({})))


class FlattenTest(unittest.TestCase):
    def test_lifts_the_nested_last_result_fields(self):
        flattened = statusloop.flatten({"last_result": {"status": "partial_success", "errors": ["x"]}})

        self.assertEqual(flattened["last_result_status"], "partial_success")
        self.assertEqual(flattened["last_result_errors"], ["x"])

    def test_a_missing_or_unusable_last_result_is_not_an_error(self):
        # null until the first sync of a boot has finished.
        for payload in ({}, {"last_result": None}, {"last_result": "nope"}):
            with self.subTest(payload=payload):
                flattened = statusloop.flatten(payload)

                self.assertIsNone(flattened["last_result_status"])
                self.assertIsNone(flattened["last_result_errors"])


class StatusUrlsTest(unittest.TestCase):
    def test_both_urls_follow_the_port_the_addon_owns(self):
        # env.PORT is the single owner of that number - the watchdog, the published port and the
        # HEALTHCHECK all read from it. A copy here would leave this loop silent if the port ever
        # moved, which is the exact failure the loop exists to eliminate.
        original = env.PORT
        env.PORT = "9999"
        self.addCleanup(importlib.reload, statusloop)
        self.addCleanup(setattr, env, "PORT", original)

        reloaded = importlib.reload(statusloop)

        self.assertEqual(
            reloaded.STATUS_URLS,
            ("http://127.0.0.1:9999/api/status", "https://127.0.0.1:9999/api/status"),
        )


class UnverifiedContextTest(unittest.TestCase):
    def test_accepts_the_self_signed_certificate_upstream_generates(self):
        context = statusloop.unverified_context()

        self.assertFalse(context.check_hostname)
        self.assertEqual(context.verify_mode, ssl.CERT_NONE)


class ReadStatusTest(unittest.TestCase):
    def test_parses_the_http_response(self):
        payload = statusloop.read_status(
            open_url=opener({statusloop.STATUS_URLS[0]: '{"authenticated": true}'})
        )

        self.assertTrue(payload["authenticated"])

    def test_falls_back_to_https(self):
        # USE_HTTPS is the documented escape hatch when Wahoo refuses a plain-HTTP redirect, and the
        # certificate upstream generates is self-signed by construction.
        payload = statusloop.read_status(
            open_url=opener(
                {
                    statusloop.STATUS_URLS[0]: OSError("connection reset"),
                    statusloop.STATUS_URLS[1]: '{"authenticated": true}',
                }
            )
        )

        self.assertTrue(payload["authenticated"])

    def test_no_answer_at_all_yields_nothing(self):
        # Normal for the first few seconds of a boot, before Flask has bound the port.
        payload = statusloop.read_status(
            open_url=opener({url: OSError("refused") for url in statusloop.STATUS_URLS})
        )

        self.assertIsNone(payload)

    def test_unparsable_output_yields_nothing(self):
        payload = statusloop.read_status(open_url=opener({statusloop.STATUS_URLS[0]: "<html>"}))

        self.assertIsNone(payload)

    def test_an_unparsable_http_answer_still_tries_https(self):
        # A 200 that is not JSON - an upstream error page, a proxy interstitial - says nothing about
        # whether the dashboard answers over https, so it must not cancel the second attempt.
        payload = statusloop.read_status(
            open_url=opener(
                {
                    statusloop.STATUS_URLS[0]: "<html>not the dashboard</html>",
                    statusloop.STATUS_URLS[1]: '{"authenticated": true}',
                }
            )
        )

        self.assertTrue(payload["authenticated"])

    def test_a_body_that_is_not_an_object_yields_nothing(self):
        # flatten() copies the payload into a dict, which a JSON array or scalar cannot fill, so the
        # shape is checked here rather than escaping the promise to return None.
        payload = statusloop.read_status(
            open_url=opener({url: "[1, 2, 3]" for url in statusloop.STATUS_URLS})
        )

        self.assertIsNone(payload)


class PollOnceTest(unittest.TestCase):
    def setUp(self):
        self.emitted = []
        self.warned = []

    def poll_once(self, previous, read, unreadable=0):
        return statusloop.poll_once(
            previous, self.emitted.append, read=read, unreadable=unreadable, warn=self.warned.append
        )

    def test_emits_a_changed_line(self):
        result, _ = self.poll_once(
            statusloop.signature(statusloop.flatten({"authenticated": False})),
            read=lambda: statusloop.flatten({"authenticated": True}),
        )

        self.assertEqual(len(self.emitted), 1)
        self.assertEqual(result, statusloop.signature(statusloop.flatten({"authenticated": True})))

    def test_stays_silent_when_nothing_changed(self):
        payload = statusloop.flatten({"authenticated": True, "next_sync_time": "A"})
        first, _ = self.poll_once(None, read=lambda: payload)

        second, _ = self.poll_once(first, read=lambda: payload)

        self.assertEqual(len(self.emitted), 1)
        self.assertEqual(second, first)

    def test_a_moved_counter_alone_is_not_worth_a_line(self):
        # total_downloaded and is_syncing move within a cycle by construction; comparing them would
        # put a line in the log on every poll, which is what "only log what changed" exists to avoid.
        first, _ = self.poll_once(
            None,
            read=lambda: statusloop.flatten({"authenticated": True, "total_downloaded": 1}),
        )

        second, _ = self.poll_once(
            first,
            read=lambda: statusloop.flatten(
                {"authenticated": True, "total_downloaded": 2, "is_syncing": True}
            ),
        )

        self.assertEqual(len(self.emitted), 1)
        self.assertEqual(second, first)

    def test_those_fields_are_still_reported_when_a_line_is_emitted(self):
        self.poll_once(
            None,
            read=lambda: statusloop.flatten({"authenticated": True, "total_downloaded": 7}),
        )

        self.assertIn("total_downloaded=7", self.emitted[0])

    def test_keeps_the_previous_value_when_the_status_is_unreadable(self):
        previous = statusloop.signature(statusloop.flatten({"authenticated": True}))

        result, _ = self.poll_once(previous, read=lambda: None)

        self.assertEqual(result, previous)
        self.assertEqual(self.emitted, [])

    def poll_unreadable(self, previous, count, times):
        """Polls a dashboard that answers nothing, carrying the count the way main() does."""
        for _ in range(times):
            previous, count = self.poll_once(previous, read=lambda: None, unreadable=count)
        return previous, count

    def test_an_unreadable_status_is_silent_until_the_threshold(self):
        # Normal for the first seconds of a boot, so the early ones must not cry wolf.
        self.poll_unreadable(None, 0, statusloop.UNREADABLE_POLLS_BEFORE_WARNING - 1)

        self.assertEqual(self.warned, [])

    def test_a_dashboard_that_never_answers_is_reported_once(self):
        # "Not up yet" and "never coming up" are the same silence from here, so the second has to be
        # said out loud - once, not on every poll.
        self.poll_unreadable(None, 0, statusloop.UNREADABLE_POLLS_BEFORE_WARNING + 3)

        self.assertEqual(len(self.warned), 1)

    def test_a_successful_poll_resets_the_count(self):
        # So a later outage can warn again instead of being swallowed by the first one.
        previous, count = self.poll_unreadable(
            None, 0, statusloop.UNREADABLE_POLLS_BEFORE_WARNING
        )
        previous, count = self.poll_once(
            previous,
            read=lambda: statusloop.flatten({"authenticated": True}),
            unreadable=count,
        )
        self.assertEqual(count, 0)

        self.poll_unreadable(previous, count, statusloop.UNREADABLE_POLLS_BEFORE_WARNING)

        self.assertEqual(len(self.warned), 2)


class StopLooping(Exception):
    """Breaks main()'s infinite loop from the injected sleep, so the loop itself can be tested."""


class MainTest(unittest.TestCase):
    def run_main(self, reads, iterations):
        # main() polls before it sleeps, so the sleep that ends the budget lands on the same iteration
        # as the last poll - hence >=, or one extra, unbudgeted poll would run past the end of `reads`.
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
        reads = [OSError("boom"), statusloop.flatten({"authenticated": True}), OSError("boom")]

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

    def test_a_dashboard_that_never_answers_is_reported_by_the_loop(self):
        # The count has to survive between iterations, or every poll starts from zero and the
        # warning is never reached.
        polls = statusloop.UNREADABLE_POLLS_BEFORE_WARNING + 2
        reads = [None] * polls

        with self.assertLogs("dreeve-ha.status", level="WARNING") as captured:
            self.run_main(reads, iterations=polls)

        self.assertEqual(len(captured.output), 1)

    def test_the_first_poll_happens_before_the_first_sleep(self):
        # Waiting a full interval before the first line is indistinguishable from a dead loop.
        reads = [statusloop.flatten({"authenticated": True})]

        with self.assertLogs("dreeve-ha.status", level="INFO") as captured:
            self.run_main(reads, iterations=1)

        self.assertEqual(reads, [])
        self.assertTrue(any("authenticated=True" in line for line in captured.output))


if __name__ == "__main__":
    unittest.main()

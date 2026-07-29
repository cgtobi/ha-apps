import tempfile
import unittest
from pathlib import Path

from dreeve_ha import login, options


def make_options(**overrides):
    result = dict(options.DEFAULTS)
    result["extra_env"] = []
    result.update(overrides)
    return result


class FakeGarmin:
    """Stands in for garminconnect.Garmin. Records how it was built and what was called.

    Mirrors the real 0.3.7 API deliberately: the garth client hangs off `.client` (there is no
    `.garth`), `login()` returns a (status, client_state) tuple, and `dump()` is what writes the token
    store - nothing else does, on the return_on_mfa path.
    """

    instances = []

    def __init__(self, email=None, password=None, return_on_mfa=False):
        self.email = email
        self.password = password
        self.return_on_mfa = return_on_mfa
        self.login_calls = []
        self.resume_calls = []
        self.login_result = (None, None)
        self.resume_error = None
        self.client = self
        self.dumped_to = None
        FakeGarmin.instances.append(self)

    def login(self, tokenstore=None):
        self.login_calls.append(tokenstore)
        return self.login_result

    def resume_login(self, client_state, mfa_code):
        self.resume_calls.append((client_state, mfa_code))
        if self.resume_error is not None:
            raise self.resume_error
        return (None, None)

    def dump(self, path):
        # Writes a real token file, so has_session() sees what it would see in production.
        self.dumped_to = path
        Path(path).mkdir(parents=True, exist_ok=True)
        (Path(path) / "oauth1_token.json").write_text("{}", encoding="utf-8")


class LoginTestCase(unittest.TestCase):
    def setUp(self):
        FakeGarmin.instances = []
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.tokens = root / "tokens"
        self.state_file = root / "mfa_state.json"
        self.attempt_file = root / "login-attempt"

    def ensure(self, addon_options, now=1000.0, factory=None):
        return login.ensure_session(
            addon_options,
            garmin_factory=factory or FakeGarmin,
            tokens=self.tokens,
            state_file=self.state_file,
            attempt_file=self.attempt_file,
            now=now,
        )

    def credentials(self, **overrides):
        return make_options(
            garmin_email="me@example.com", garmin_password="secret", **overrides
        )


class ExistingSessionTest(LoginTestCase):
    def test_does_nothing_when_a_token_file_exists(self):
        self.tokens.mkdir()
        (self.tokens / "oauth1_token.json").write_text("{}", encoding="utf-8")

        self.ensure(self.credentials())

        self.assertEqual(FakeGarmin.instances, [])
        self.assertFalse(self.attempt_file.exists())


class MissingCredentialsTest(LoginTestCase):
    def test_blocks_without_an_email(self):
        with self.assertRaises(login.LoginBlocked) as caught:
            self.ensure(make_options(garmin_password="secret"))

        self.assertIn("garmin_email", str(caught.exception))
        self.assertEqual(FakeGarmin.instances, [])

    def test_blocks_without_a_password(self):
        with self.assertRaises(login.LoginBlocked) as caught:
            self.ensure(make_options(garmin_email="me@example.com"))

        self.assertIn("garmin_password", str(caught.exception))
        self.assertEqual(FakeGarmin.instances, [])


class ThrottleTest(LoginTestCase):
    def test_refuses_a_second_attempt_inside_the_window(self):
        self.attempt_file.write_text("1000.0", encoding="utf-8")

        with self.assertRaises(login.LoginBlocked) as caught:
            self.ensure(self.credentials(), now=1000.0 + login.THROTTLE_SECONDS - 1)

        self.assertIn("rate-limited", str(caught.exception))
        self.assertEqual(FakeGarmin.instances, [])

    def test_allows_an_attempt_once_the_window_passed(self):
        self.attempt_file.write_text("1000.0", encoding="utf-8")

        self.ensure(self.credentials(), now=1000.0 + login.THROTTLE_SECONDS + 1)

        self.assertEqual(len(FakeGarmin.instances), 1)

    def test_a_corrupt_attempt_file_does_not_block(self):
        self.attempt_file.write_text("not-a-number", encoding="utf-8")

        self.ensure(self.credentials())

        self.assertEqual(len(FakeGarmin.instances), 1)


class SuccessfulLoginTest(LoginTestCase):
    def test_logs_in_and_records_the_attempt(self):
        self.ensure(self.credentials(), now=1234.0)

        client = FakeGarmin.instances[0]
        self.assertEqual(client.email, "me@example.com")
        self.assertEqual(client.password, "secret")
        self.assertTrue(client.return_on_mfa)
        self.assertEqual(client.login_calls, [str(self.tokens)])
        self.assertEqual(self.attempt_file.read_text(encoding="utf-8"), "1234.0")

    def test_creates_the_token_directory(self):
        self.ensure(self.credentials())

        self.assertTrue(self.tokens.is_dir())

    def test_a_garmin_error_becomes_a_blocked_login(self):
        class FailingGarmin(FakeGarmin):
            def login(self, tokenstore=None):
                raise RuntimeError("401 Unauthorized")

        with self.assertRaises(login.LoginBlocked) as caught:
            self.ensure(self.credentials(), factory=FailingGarmin)

        self.assertIn("401 Unauthorized", str(caught.exception))
        self.assertTrue(self.attempt_file.exists())

    def test_the_session_is_written_to_the_token_store(self):
        # garminconnect returns early on the return_on_mfa path, before its own token dump, so the
        # wrapper has to persist the session itself or the connector never gets one.
        self.ensure(self.credentials())

        self.assertEqual(FakeGarmin.instances[0].dumped_to, str(self.tokens))
        self.assertTrue(login.has_session(self.tokens))

    def test_a_login_that_stores_nothing_fails_loudly(self):
        class DumpsNothing(FakeGarmin):
            def dump(self, path):
                self.dumped_to = path

        with self.assertRaises(login.LoginBlocked) as caught:
            self.ensure(self.credentials(), factory=DumpsNothing)

        self.assertIn("no session was written", str(caught.exception))


class NeedsMfaTest(LoginTestCase):
    def factory_needing_mfa(self, client_state):
        class NeedsMfaGarmin(FakeGarmin):
            def __init__(inner, **kwargs):
                super().__init__(**kwargs)
                inner.login_result = (login.NEEDS_MFA, client_state)

        return NeedsMfaGarmin

    def test_persists_the_ticket_and_tells_the_user_what_to_do(self):
        with self.assertRaises(login.LoginBlocked) as caught:
            self.ensure(self.credentials(), factory=self.factory_needing_mfa({"ticket": "abc"}))

        message = str(caught.exception)
        self.assertIn("mfa_code", message)
        self.assertTrue(self.state_file.exists())
        self.assertEqual(login._load_state(self.state_file), {"ticket": "abc"})

    def test_the_ticket_file_is_not_world_readable(self):
        with self.assertRaises(login.LoginBlocked):
            self.ensure(self.credentials(), factory=self.factory_needing_mfa({"ticket": "abc"}))

        self.assertEqual(self.state_file.stat().st_mode & 0o777, 0o600)

    def test_a_ticket_json_cannot_represent_still_survives(self):
        unserialisable = {"ticket": object()}

        with self.assertRaises(login.LoginBlocked):
            self.ensure(self.credentials(), factory=self.factory_needing_mfa(unserialisable))

        self.assertTrue(self.state_file.exists())
        self.assertIn("ticket", login._load_state(self.state_file))


class ResumeTest(LoginTestCase):
    def setUp(self):
        super().setUp()
        login._save_state({"ticket": "abc"}, self.state_file)

    def test_blocks_while_the_code_option_is_empty(self):
        with self.assertRaises(login.LoginBlocked) as caught:
            self.ensure(self.credentials())

        self.assertIn("mfa_code", str(caught.exception))
        self.assertEqual(FakeGarmin.instances, [])
        self.assertTrue(self.state_file.exists())

    def test_resumes_the_stored_ticket_with_the_code(self):
        self.ensure(self.credentials(mfa_code="123456"))

        client = FakeGarmin.instances[0]
        self.assertEqual(client.resume_calls, [({"ticket": "abc"}, "123456")])
        self.assertEqual(client.login_calls, [])

    def test_dumps_tokens_and_clears_the_ticket_on_success(self):
        self.ensure(self.credentials(mfa_code="123456"))

        self.assertEqual(FakeGarmin.instances[0].dumped_to, str(self.tokens))
        self.assertFalse(self.state_file.exists())

    def test_a_failed_resume_reports_the_error_and_discards_the_spent_ticket(self):
        class FailingResume(FakeGarmin):
            def __init__(inner, **kwargs):
                super().__init__(**kwargs)
                inner.resume_error = RuntimeError("MFA code expired")

        with self.assertRaises(login.LoginBlocked) as caught:
            self.ensure(self.credentials(mfa_code="123456"), factory=FailingResume)

        message = str(caught.exception)
        self.assertIn("MFA code expired", message)
        self.assertIn("rejected", message)
        self.assertFalse(self.state_file.exists())

    def test_an_unreadable_ticket_is_reported_as_such_and_discarded(self):
        # Neither valid UTF-8 JSON nor a valid pickle stream. This is a local problem, so the message
        # must not claim Garmin rejected anything.
        self.state_file.write_bytes(b"\xff\xfe not a ticket")

        with self.assertRaises(login.LoginBlocked) as caught:
            self.ensure(self.credentials(mfa_code="123456"), factory=FakeGarmin)

        message = str(caught.exception)
        self.assertIn("could not be read", message)
        self.assertNotIn("rejected", message)
        self.assertFalse(self.state_file.exists())
        self.assertEqual(FakeGarmin.instances, [])

    def test_the_throttle_does_not_block_answering_a_pending_ticket(self):
        # The emailed code expires in minutes, so a 15-minute throttle on the resume would make the
        # documented "paste the code and restart" flow impossible to complete.
        self.attempt_file.write_text("1000.0", encoding="utf-8")

        self.ensure(self.credentials(mfa_code="123456"), now=1000.0 + 60)

        self.assertEqual(FakeGarmin.instances[0].resume_calls, [({"ticket": "abc"}, "123456")])
        self.assertTrue(login.has_session(self.tokens))


if __name__ == "__main__":
    unittest.main()

import subprocess
import tempfile
import unittest
from pathlib import Path

from dreeve_ha import env, options


def make_options(**overrides):
    result = dict(options.DEFAULTS)
    result["extra_env"] = []
    result.update(overrides)
    return result


class BuildTest(unittest.TestCase):
    def test_sets_the_paths_and_status_address_the_addon_owns(self):
        built, warnings = env.build(make_options(), Path("/addon_configs/x/watch"))

        self.assertEqual(built["POLAR_TOKENS"], "/data/tokens")
        self.assertEqual(built["STATE_DIR"], "/data/state")
        self.assertEqual(built["WATCH_DIR"], "/addon_configs/x/watch")
        self.assertEqual(built["HTTP_ADDR"], "0.0.0.0:8080")
        self.assertEqual(warnings, [])

    def test_passes_the_client_credentials_public_url_and_since_through(self):
        built, _ = env.build(
            make_options(
                polar_client_id="abc-123",
                polar_client_secret="secret",
                public_url="http://homeassistant.local:8080",
                since="-7d",
            ),
            Path("/watch"),
        )

        self.assertEqual(built["POLAR_CLIENT_ID"], "abc-123")
        self.assertEqual(built["POLAR_CLIENT_SECRET"], "secret")
        self.assertEqual(built["PUBLIC_URL"], "http://homeassistant.local:8080")
        self.assertEqual(built["SINCE"], "-7d")

    def test_the_client_id_is_exported_even_when_unset(self):
        # So the connector reports its own "POLAR_CLIENT_ID is required" message, which names where to
        # create a client, rather than this add-on inventing a second wording for the same problem.
        built, _ = env.build(make_options(polar_client_id=""), Path("/watch"))

        self.assertEqual(built["POLAR_CLIENT_ID"], "")

    def test_omits_blank_optional_values(self):
        built, _ = env.build(
            make_options(polar_client_secret="", public_url="", since="", tz=""), Path("/watch")
        )

        # Blank rather than absent would collide with POLAR_CLIENT_SECRET_FILE, which upstream refuses
        # to accept alongside an inline secret - so leaving the option empty must keep that route open.
        self.assertNotIn("POLAR_CLIENT_SECRET", built)
        self.assertNotIn("PUBLIC_URL", built)
        self.assertNotIn("SINCE", built)
        self.assertNotIn("TZ", built)

    def test_extra_env_is_applied(self):
        built, warnings = env.build(
            make_options(extra_env=["POLL_INTERVAL=7200", "SPORTS=running,cycling"]), Path("/watch")
        )

        self.assertEqual(built["POLL_INTERVAL"], "7200")
        self.assertEqual(built["SPORTS"], "running,cycling")
        self.assertEqual(warnings, [])

    def test_extra_env_can_point_the_secret_at_a_file(self):
        built, warnings = env.build(
            make_options(polar_client_secret="", extra_env=["POLAR_CLIENT_SECRET_FILE=/data/secret"]),
            Path("/watch"),
        )

        self.assertEqual(built["POLAR_CLIENT_SECRET_FILE"], "/data/secret")
        self.assertEqual(warnings, [])

    def test_extra_env_cannot_override_owned_variables(self):
        built, warnings = env.build(
            make_options(extra_env=["WATCH_DIR=/tmp/x", "HTTP_ADDR=off"]), Path("/watch")
        )

        self.assertEqual(built["WATCH_DIR"], "/watch")
        # HTTP_ADDR=off would take away the authorization page as well as the watchdog's only signal.
        self.assertEqual(built["HTTP_ADDR"], "0.0.0.0:8080")
        self.assertEqual(len(warnings), 2)
        self.assertIn("WATCH_DIR", warnings[0])
        self.assertIn("HTTP_ADDR", warnings[1])

    def test_malformed_extra_env_entry_is_warned_about(self):
        built, warnings = env.build(make_options(extra_env=["POLL_INTERVAL"]), Path("/watch"))

        self.assertNotIn("POLL_INTERVAL", built)
        self.assertEqual(len(warnings), 1)
        self.assertIn("KEY=VALUE", warnings[0])

    def test_extra_env_value_may_contain_an_equals_sign(self):
        built, _ = env.build(make_options(extra_env=["WEBHOOK_URL=https://x/webhook?a=b"]), Path("/watch"))

        self.assertEqual(built["WEBHOOK_URL"], "https://x/webhook?a=b")

    def test_a_key_that_is_not_a_valid_variable_name_is_rejected(self):
        # An unusable key must be caught here: ha-start.sh sources this file under `set -eu`, so a
        # malformed export line kills the add-on with a shell syntax error naming no option.
        built, warnings = env.build(
            make_options(extra_env=["MAX_DOWNLOADS(5)=10", "MY VAR=2", "lower_ok=1"]), Path("/watch")
        )

        self.assertNotIn("MAX_DOWNLOADS(5)", built)
        self.assertNotIn("MY VAR", built)
        self.assertNotIn("VAR", built)
        self.assertEqual(built["lower_ok"], "1")
        self.assertEqual(len(warnings), 2)
        self.assertTrue(all("not a valid environment variable name" in w for w in warnings))


class AsShellTest(unittest.TestCase):
    def test_emits_sorted_export_lines(self):
        result = env.as_shell({"B": "2", "A": "1"})

        self.assertEqual(result, "export A=1\nexport B=2\n")

    def test_hostile_values_round_trip_through_a_posix_shell(self):
        # The entrypoint sources this output, so quoting is correctness, not cosmetics. Asserting on
        # the rendered text would only re-implement the quoting rules; ask a real shell instead.
        hostile = "se cr'e\"t$(echo pwned)`echo also`\\end"

        with tempfile.TemporaryDirectory() as directory:
            env_file = Path(directory) / "env.sh"
            env_file.write_text(env.as_shell({"POLAR_CLIENT_SECRET": hostile}), encoding="utf-8")
            completed = subprocess.run(
                ["sh", "-c", '. "$1" && printf %s "$POLAR_CLIENT_SECRET"', "sh", str(env_file)],
                capture_output=True,
                text=True,
                check=True,
            )

        self.assertEqual(completed.stdout, hostile)
        self.assertEqual(completed.stderr, "")


if __name__ == "__main__":
    unittest.main()

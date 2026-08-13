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
    def test_sets_the_paths_and_port_the_addon_owns(self):
        built, warnings = env.build(make_options(), Path("/addon_configs/x/watch"))

        self.assertEqual(built["DATA_DIR"], "/data")
        self.assertEqual(built["PORT"], "8080")
        # Read by dreeve_ha.relay, not by upstream: upstream has no way to be told where to write.
        self.assertEqual(built["DREEVE_WATCH_DIR"], "/addon_configs/x/watch")
        self.assertEqual(warnings, [])

    def test_never_exports_watch_dir_itself(self):
        # WATCH_DIR is the name a planned upstream change will make upstream honour. Exporting it
        # would, on the first bump onto such a build, have upstream write straight into the folder
        # Dreeve empties - and upstream's deduplication asks whether the file is still on disk, so
        # it would re-download its whole window every cron fire while the add-on looked healthy.
        built, _ = env.build(make_options(), Path("/addon_configs/x/watch"))

        self.assertNotIn("WATCH_DIR", built)

    def test_passes_the_client_credentials_and_schedule_through(self):
        built, _ = env.build(
            make_options(
                wahoo_client_id="abc-123",
                wahoo_client_secret="secret",
                redirect_uri="http://ha.local:8085/callback",
                sync_time_window="1_month",
                sync_cron="*/30 * * * *",
                tz="Europe/Zurich",
            ),
            Path("/watch"),
        )

        self.assertEqual(built["WAHOO_CLIENT_ID"], "abc-123")
        self.assertEqual(built["WAHOO_CLIENT_SECRET"], "secret")
        self.assertEqual(built["WAHOO_REDIRECT_URI"], "http://ha.local:8085/callback")
        self.assertEqual(built["SYNC_TIME_WINDOW"], "1_month")
        self.assertEqual(built["SYNC_CRON"], "*/30 * * * *")
        self.assertEqual(built["TZ"], "Europe/Zurich")

    def test_the_redirect_uri_is_passed_through_verbatim(self):
        # Wahoo compares the redirect against the registered value, so a trailing slash this add-on
        # tidied away would turn an exact match into a rejected request.
        built, _ = env.build(make_options(redirect_uri="http://ha.local:8085/callback/"), Path("/watch"))

        self.assertEqual(built["WAHOO_REDIRECT_URI"], "http://ha.local:8085/callback/")

    def test_the_client_id_is_exported_even_when_unset(self):
        # So the connector reports its own "must be set in environment" message, which names where to
        # create an application, rather than this add-on inventing a second wording for it.
        built, _ = env.build(make_options(wahoo_client_id=""), Path("/watch"))

        self.assertEqual(built["WAHOO_CLIENT_ID"], "")

    def test_a_blank_redirect_uri_falls_back_to_plain_http(self):
        # Unset, upstream defaults to https://localhost:8085/callback, and any https redirect switches
        # on a self-signed certificate - so an add-on nobody has configured yet would answer its webui
        # link with a certificate warning instead of a dashboard.
        built, _ = env.build(make_options(redirect_uri=""), Path("/watch"))

        self.assertEqual(built["WAHOO_REDIRECT_URI"], "http://localhost:8080/callback")

    def test_blank_optional_values_are_left_out(self):
        built, _ = env.build(
            make_options(wahoo_client_secret="", sync_cron="", sync_time_window="", tz=""),
            Path("/watch"),
        )

        # Omitted rather than exported empty, so upstream's own defaults apply: an empty SYNC_CRON
        # disables its scheduler outright and an empty SYNC_TIME_WINDOW reads as all_time, neither of
        # which is what clearing an option should mean.
        self.assertNotIn("WAHOO_CLIENT_SECRET", built)
        self.assertNotIn("SYNC_CRON", built)
        self.assertNotIn("SYNC_TIME_WINDOW", built)
        self.assertNotIn("TZ", built)


class ExtraEnvTest(unittest.TestCase):
    def test_passes_extra_settings_through(self):
        built, warnings = env.build(
            make_options(extra_env=["WAHOO_SCOPES=user_read workouts_read", "USE_HTTPS=true"]),
            Path("/watch"),
        )

        self.assertEqual(built["WAHOO_SCOPES"], "user_read workouts_read")
        # The documented escape hatch when Wahoo's portal refuses a plain-HTTP redirect, so it must
        # not be an owned variable.
        self.assertEqual(built["USE_HTTPS"], "true")
        self.assertEqual(warnings, [])

    def test_refuses_the_variables_the_addon_owns(self):
        for owned in env.OWNED:
            with self.subTest(owned=owned):
                built, warnings = env.build(
                    make_options(extra_env=["{0}=/somewhere".format(owned)]), Path("/watch")
                )

                self.assertNotEqual(built.get(owned), "/somewhere")
                self.assertTrue(any(owned in warning for warning in warnings))

    def test_warns_about_entries_that_are_not_key_value(self):
        built, warnings = env.build(make_options(extra_env=["nonsense", "=1"]), Path("/watch"))

        self.assertEqual(len(warnings), 2)
        self.assertNotIn("nonsense", built)

    def test_warns_about_keys_that_are_not_variable_names(self):
        # An unsourceable export line would take the add-on down with a shell syntax error naming no
        # option at all.
        _, warnings = env.build(make_options(extra_env=["not-a-name=1"]), Path("/watch"))

        self.assertEqual(len(warnings), 1)

    def test_a_value_may_contain_equals_signs(self):
        built, _ = env.build(make_options(extra_env=["FLASK_SECRET_KEY=a=b"]), Path("/watch"))

        self.assertEqual(built["FLASK_SECRET_KEY"], "a=b")


class AsShellTest(unittest.TestCase):
    def test_renders_sorted_export_lines(self):
        rendered = env.as_shell({"B": "2", "A": "1"})

        self.assertEqual(rendered, "export A=1\nexport B=2\n")

    def test_a_hostile_value_survives_the_shell_round_trip(self):
        hostile = "se cr'e\"t$(echo pwned)`echo also`\\end"

        with tempfile.TemporaryDirectory() as directory:
            env_file = Path(directory) / "env"
            env_file.write_text(env.as_shell({"WAHOO_CLIENT_SECRET": hostile}), encoding="utf-8")
            completed = subprocess.run(
                ["sh", "-c", '. "$1" && printf %s "$WAHOO_CLIENT_SECRET"', "sh", str(env_file)],
                capture_output=True,
                text=True,
                check=True,
            )

        self.assertEqual(completed.stdout, hostile)


if __name__ == "__main__":
    unittest.main()

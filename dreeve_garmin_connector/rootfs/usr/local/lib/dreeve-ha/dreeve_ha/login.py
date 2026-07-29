"""Creates the Garmin session the connector daemon later resumes, without ever needing a terminal.

The connector's own `login` command refuses to run without a tty, and its daemon is built never to
log in by itself, because repeated logins are what get a Garmin account rate-limited. So this runs
once at boot, only when there is no session at all, and refuses to try again inside THROTTLE_SECONDS.
"""

from __future__ import annotations

import json
import logging
import pickle
import time
from pathlib import Path

from dreeve_ha import env, secretfile

TOKENS_DIR = env.TOKENS_DIR
MFA_STATE_FILE = Path("/data/mfa_state.json")
ATTEMPT_FILE = Path("/data/login-attempt")
THROTTLE_SECONDS = 900

# garminconnect returns this marker as the first element of its login() result when the account has
# multi-factor authentication enabled and return_on_mfa was requested.
NEEDS_MFA = "needs_mfa"

logger = logging.getLogger("dreeve-ha.login")


class LoginBlocked(Exception):
    """No session was created. The message is written for the user and says what to do next."""


def has_session(tokens):
    """The token store may be a file or a directory depending on the library version; both count."""
    tokens = Path(tokens)
    if tokens.is_file():
        return tokens.stat().st_size > 0
    return tokens.is_dir() and any(tokens.iterdir())


def _is_throttled(attempt_file, now):
    try:
        last_attempt = float(Path(attempt_file).read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return False
    return now - last_attempt < THROTTLE_SECONDS


def _record_attempt(attempt_file, now):
    attempt_file = Path(attempt_file)
    attempt_file.parent.mkdir(parents=True, exist_ok=True)
    attempt_file.write_text(str(now), encoding="utf-8")


def _save_state(client_state, state_file):
    """Persists the pending MFA ticket so the code can be answered after a restart."""
    try:
        payload = json.dumps(client_state).encode("utf-8")
    except TypeError:
        # garth may hand back objects json cannot represent; the ticket still has to survive.
        payload = pickle.dumps(client_state)
    secretfile.write(state_file, payload)


def _load_state(state_file):
    payload = Path(state_file).read_bytes()
    try:
        return json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return pickle.loads(payload)


def ensure_session(
    addon_options,
    garmin_factory,
    tokens=TOKENS_DIR,
    state_file=MFA_STATE_FILE,
    attempt_file=ATTEMPT_FILE,
    now=None,
):
    """Makes sure a Garmin session exists, doing as little as possible to get there."""
    now = time.time() if now is None else now
    tokens = Path(tokens)
    state_file = Path(state_file)

    if has_session(tokens):
        logger.info("Garmin session found in %s; not logging in.", tokens)
        return

    if not addon_options["garmin_email"]:
        raise LoginBlocked("Set the 'garmin_email' option.")
    if not addon_options["garmin_password"]:
        raise LoginBlocked(
            "Set the 'garmin_password' option. It is only needed until a session exists."
        )
    # Answering a pending ticket is exempt: it finishes a login already in flight, and the emailed code
    # expires in minutes, so throttling it would make the two-restart MFA flow impossible to complete.
    resuming = state_file.exists() and bool(addon_options["mfa_code"])
    if not resuming and _is_throttled(attempt_file, now):
        raise LoginBlocked(
            "A login was attempted less than {0} minutes ago, so this one is skipped. Repeated "
            "logins are what get a Garmin account rate-limited.".format(THROTTLE_SECONDS // 60)
        )
    if state_file.exists() and not addon_options["mfa_code"]:
        raise LoginBlocked(
            "Garmin is waiting for the multi-factor code it emailed. Put it in the 'mfa_code' "
            "option and restart this add-on."
        )

    tokens.mkdir(parents=True, exist_ok=True)
    _record_attempt(attempt_file, now)

    if state_file.exists():
        _resume_login(addon_options, garmin_factory, tokens, state_file)
        return

    _start_login(addon_options, garmin_factory, tokens, state_file)


def _store_session(client, tokens):
    """Persists the session garminconnect leaves in memory on the return_on_mfa path.

    The garth client lives on `.client` - there is no `.garth` attribute - and it owns the token store.
    """
    client.client.dump(str(tokens))
    if not has_session(tokens):
        raise LoginBlocked(
            "Garmin accepted the login but no session was written to {0}. That usually means the "
            "garminconnect library changed how it stores tokens, so this add-on needs "
            "updating.".format(tokens)
        )


def _start_login(addon_options, garmin_factory, tokens, state_file):
    client = garmin_factory(
        email=addon_options["garmin_email"],
        password=addon_options["garmin_password"],
        return_on_mfa=True,
    )
    try:
        result, client_state = client.login(str(tokens))
    except Exception as exception:  # garminconnect raises a family of transport/auth errors
        raise LoginBlocked("Garmin login failed: {0}".format(exception)) from exception

    if result == NEEDS_MFA:
        _save_state(client_state, state_file)
        raise LoginBlocked(
            "Garmin sent a multi-factor code by email. Put it in the 'mfa_code' option and restart "
            "this add-on."
        )

    _store_session(client, tokens)
    logger.info("Logged in. Session stored in %s.", tokens)


def _resume_login(addon_options, garmin_factory, tokens, state_file):
    """Answers the code against the ticket that produced it, which is why a pre-set code is not racy."""
    # Loading is outside the try below on purpose: a ticket this process cannot read is a different
    # problem from Garmin rejecting the code, and the user needs to be told which one happened.
    try:
        client_state = _load_state(state_file)
    except Exception as exception:
        state_file.unlink()
        raise LoginBlocked(
            "The stored Garmin login ticket could not be read ({0}), so it has been discarded. "
            "Clear the 'mfa_code' option and restart to begin a new login.".format(exception)
        ) from exception

    client = garmin_factory(
        email=addon_options["garmin_email"],
        password=addon_options["garmin_password"],
        return_on_mfa=True,
    )
    try:
        client.resume_login(client_state, addon_options["mfa_code"])
    except Exception as exception:
        # Ticket and code are both spent now, so the next start has to begin a fresh login.
        state_file.unlink()
        raise LoginBlocked(
            "Garmin rejected the multi-factor code ({0}), and the login ticket is now spent. "
            "Clear the 'mfa_code' option and restart to begin a new login.".format(exception)
        ) from exception

    # Inside a try so a spent ticket is discarded even when storing the session fails - otherwise the
    # next start replays a dead ticket instead of beginning a clean login.
    try:
        _store_session(client, tokens)
    finally:
        state_file.unlink()

    logger.info("Logged in with the multi-factor code. Session stored in %s.", tokens)

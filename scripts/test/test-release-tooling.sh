#!/usr/bin/env sh
# Exercises the release tooling against a throwaway copy of the repository, so a real bump is never
# written to the working tree.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

pass() {
  echo "ok: $*"
}

copy_repo() {
  target="$1"
  mkdir -p "$target"
  # A plain copy is enough: none of the checks under test need git history.
  (cd "$ROOT_DIR" && tar cf - --exclude .git .) | (cd "$target" && tar xf -)
}

REPO="${WORK_DIR}/repo"
copy_repo "$REPO"

# 1. Both add-ons are consistent as committed.
if (cd "$REPO" && ./scripts/check-release-consistency.sh >/dev/null 2>&1); then
  pass "check-release-consistency accepts both add-ons"
else
  fail "check-release-consistency rejected a clean tree"
fi

# 2. A changelog that disagrees with config.yaml is rejected, and the message names the add-on.
sed -i.bak 's/^## 0\.1\.0$/## 9.9.9/' "${REPO}/dreeve_garmin_connector/CHANGELOG.md"
output="$( (cd "$REPO" && ./scripts/check-release-consistency.sh 2>&1) || true )"
case "$output" in
  *dreeve_garmin_connector*) pass "a mismatch names the offending add-on" ;;
  *) fail "mismatch output did not name the add-on: ${output}" ;;
esac
mv "${REPO}/dreeve_garmin_connector/CHANGELOG.md.bak" "${REPO}/dreeve_garmin_connector/CHANGELOG.md"

# 3. `bump check` still works for every add-on at once, and for a single named one.
output="$( (cd "$REPO" && ./scripts/bump-upstream.sh check 2>&1) || true )"
missing=""
for addon in statistics_for_strava dreeve_garmin_connector dreeve_polar_connector; do
  case "$output" in
    *"$addon"*) ;;
    *) missing="${missing} ${addon}" ;;
  esac
done
if [ -z "$missing" ]; then
  pass "bump check with no argument covers every add-on"
else
  fail "bump check skipped:${missing}"
fi

# A pin that disagrees with .upstream-version is invisible to check-release-consistency.sh, so this
# is the only thing standing between a mismatched Dockerfile and a commit.
sed -i.bak 's|^ARG BUILD_FROM=.*|ARG BUILD_FROM=ghcr.io/dreeveapp/dreeve-polar-connector:9.9.9|' \
  "${REPO}/dreeve_polar_connector/Dockerfile"
output="$( (cd "$REPO" && ./scripts/bump-upstream.sh check 2>&1) || true )"
case "$output" in
  *"Mismatch: dreeve_polar_connector"*) pass "a pin disagreeing with .upstream-version is rejected" ;;
  *) fail "a mismatched pin was accepted: ${output}" ;;
esac
mv "${REPO}/dreeve_polar_connector/Dockerfile.bak" "${REPO}/dreeve_polar_connector/Dockerfile"
if (cd "$REPO" && ./scripts/bump-upstream.sh check dreeve_garmin_connector >/dev/null 2>&1); then
  pass "bump check accepts an add-on argument"
else
  fail "bump check failed for dreeve_garmin_connector"
fi

# 4. Bumping the connector to a new tag updates exactly its own four files.
addon="${REPO}/dreeve_garmin_connector"
# Derived, not hardcoded: every release of that add-on would otherwise break this assertion.
before_version="$(sed -n 's/^version: "\([0-9.]*\)".*/\1/p' "${addon}/config.yaml" | head -n1)"
expected_version="$(printf '%s\n' "$before_version" | awk -F. '{printf "%s.%s.%d", $1, $2, $3 + 1}')"
(cd "$REPO" && ./scripts/bump-upstream.sh bump dreeve_garmin_connector v9.9.9 >/dev/null)
[ "$(cat "${addon}/.upstream-version")" = "v9.9.9" ] \
  && pass ".upstream-version updated" || fail ".upstream-version not updated"
grep -q 'ARG BUILD_FROM=ghcr.io/dreeveapp/dreeve-garmin-connector:v9.9.9' "${addon}/Dockerfile" \
  && pass "Dockerfile pinned to the new tag" || fail "Dockerfile not repinned"
grep -q "^version: \"${expected_version}\"" "${addon}/config.yaml" \
  && pass "add-on version patch-bumped (${before_version} -> ${expected_version})" \
  || fail "add-on version not bumped to ${expected_version}"
grep -q '^- feat: bump Garmin connector to v9.9.9' "${addon}/CHANGELOG.md" \
  && pass "changelog entry written with the display name" || fail "changelog entry missing"
if diff -r "${ROOT_DIR}/statistics_for_strava" "${REPO}/statistics_for_strava" >/dev/null 2>&1; then
  pass "the other add-on was left alone"
else
  fail "bumping one add-on modified the other"
fi

# 4b. An upstream whose image tags carry no 'v' is pinned in its own shape, even when the tag is given
# v-prefixed on the command line. Getting this wrong is what broke the Polar add-on's first build.
(cd "$REPO" && ./scripts/bump-upstream.sh bump dreeve_polar_connector v9.9.9 >/dev/null)
addon="${REPO}/dreeve_polar_connector"
[ "$(cat "${addon}/.upstream-version")" = "9.9.9" ] \
  && pass "a bare-prefix upstream records the tag without a 'v'" || fail ".upstream-version carries a 'v'"
grep -q 'ARG BUILD_FROM=ghcr.io/dreeveapp/dreeve-polar-connector:9.9.9$' "${addon}/Dockerfile" \
  && pass "a bare-prefix upstream is pinned without a 'v'" || fail "Dockerfile pin carries a 'v'"
grep -q '^- feat: bump Polar connector to 9.9.9' "${addon}/CHANGELOG.md" \
  && pass "changelog entry matches the bare tag" || fail "changelog entry does not match the bare tag"

# 4c. The suggested commit subject names the add-on the way its users know it, not the way its
# directory is spelled - statistics_for_strava is still called that on disk because the add-on slug
# cannot change under existing installations, so the directory name is never the right label.
# A throwaway local repository stands in for the upstream, so this needs no network.
FAKE_UPSTREAM="${WORK_DIR}/fake-upstream"
git init -q "$FAKE_UPSTREAM"
(cd "$FAKE_UPSTREAM" \
  && git -c user.email=test@example.com -c user.name=test -c commit.gpgsign=false \
       commit -q --allow-empty -m init \
  && git tag v9.9.10)
sed -i.bak "s|^git_url=.*|git_url=${FAKE_UPSTREAM}|" "${REPO}/dreeve_garmin_connector/.upstream-repo"
rm -f "${REPO}/dreeve_garmin_connector/.upstream-repo.bak"
output="$( (cd "$REPO" && ./scripts/bump-upstream.sh dreeve_garmin_connector 2>&1) || true )"
case "$output" in
  *"feat: bump Garmin connector upstream to v9.9.10"*)
    pass "the commit subject uses the display name" ;;
  *) fail "commit subject did not use the display name: ${output}" ;;
esac
case "$output" in
  *"bump dreeve_garmin_connector upstream"*)
    fail "commit subject still names the directory: ${output}" ;;
  *) pass "the commit subject does not name the directory" ;;
esac

# 4d. An upstream that publishes no releases is pinned to a commit image tag. dreeve_wahoo_connector
# ships only 'latest' and 'sha-<short>', and its .upstream-repo documents this exact command; before
# it was accepted here, every wahoo pin had to be written by hand.
addon="${REPO}/dreeve_wahoo_connector"
(cd "$REPO" && ./scripts/bump-upstream.sh bump dreeve_wahoo_connector sha-9abcdef >/dev/null)
[ "$(cat "${addon}/.upstream-version")" = "sha-9abcdef" ] \
  && pass "a commit-tagged upstream records the sha tag" || fail ".upstream-version does not hold the sha tag"
grep -q 'ARG BUILD_FROM=ghcr.io/dreeveapp/dreeve-wahoo-connector:sha-9abcdef$' "${addon}/Dockerfile" \
  && pass "a commit-tagged upstream is pinned to the sha tag" || fail "Dockerfile not pinned to the sha tag"
grep -q '^- feat: bump Wahoo connector to sha-9abcdef' "${addon}/CHANGELOG.md" \
  && pass "changelog entry written for the sha tag" || fail "changelog entry missing for the sha tag"

# 4e. A tag of no recognisable shape is refused, and refused before anything is written - an empty or
# malformed version reaching the writes leaves a '<repo>:' pin and a changelog entry naming no
# release, which is how a wahoo bump once had to be undone by hand.
before_pin="$(cat "${addon}/.upstream-version")"
for bad_tag in 'sha-' 'nonsense' 'sha-zzzz'; do
  if (cd "$REPO" && ./scripts/bump-upstream.sh bump dreeve_wahoo_connector "$bad_tag" >/dev/null 2>&1); then
    fail "bump accepted the malformed tag '${bad_tag}'"
  else
    pass "bump refuses the malformed tag '${bad_tag}'"
  fi
done
[ "$(cat "${addon}/.upstream-version")" = "$before_pin" ] \
  && pass "a refused bump leaves the pin untouched" || fail "a refused bump rewrote the pin"

# 5. The bumped tree is self-consistent again.
if (cd "$REPO" && ./scripts/check-release-consistency.sh >/dev/null 2>&1); then
  pass "the bumped tree is consistent"
else
  fail "the bumped tree failed the consistency check"
fi

if [ "$failures" -ne 0 ]; then
  echo "${failures} failure(s)" >&2
  exit 1
fi

echo "all release tooling checks passed"

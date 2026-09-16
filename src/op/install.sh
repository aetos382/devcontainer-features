#!/bin/sh
set -eu

FEATURE_ID='op'
INSTALL_PATH='/usr/local/bin/op'

# Option values reach install.sh as uppercased environment variables.
OP_VERSION="${VERSION:-latest}"

# Recorded before the 'latest' resolution below overwrites OP_VERSION: only a version the caller
# named is a promise the installed binary can be held to.
VERSION_PINNED='1'
if [ "${OP_VERSION}" = latest ]; then
  VERSION_PINNED=''
fi

# 1Password does not publish the CLI on GitHub; these are the endpoints its own installation
# instructions and update checks use. Specifically this is the "manual" method documented at
# https://www.1password.dev/cli/get-started, the one method there that does not go through a
# distribution's package manager.
#
# 1Password documents apt, yum, and Alpine repositories too, and apt looks tempting whenever a
# download below fails. This feature deliberately never installs op that way, now or in future: an
# apt source lets apt-get upgrade move the version out from under a build that pinned one, and it
# would tie op itself to Debian/Ubuntu. The prerequisites further down are installed with apt-get,
# but that is a convenience for the images this feature is tested on, not a property of the install
# method — with those prerequisites present the script runs on any distribution.
DIST_BASE_URL='https://cache.agilebits.com/dist/1P/op2/pkg'
KEY_URL='https://downloads.1password.com/linux/keys/1password.asc'
VERSION_CHECK_URL='https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N'

# The release archive ships op.sig next to the binary. Pinning the fingerprint is what makes the
# verification meaningful: without it, a key served alongside a tampered binary would also pass.
SIGNING_KEY_FINGERPRINT='3FEF9748469ADBE15DA7CA80AC2D62742012EA22'

if [ "$(id -u)" -ne 0 ]; then
  echo "${FEATURE_ID}: install.sh must be run as root." >&2
  exit 1
fi

# uname -m rather than 'dpkg --print-architecture' so that architecture detection does not itself
# depend on Debian tooling.
case "$(uname -m)" in
  x86_64 | amd64) ARCH="amd64" ;;
  aarch64 | arm64) ARCH="arm64" ;;
  armv7l | armv7 | armhf) ARCH="arm" ;;
  i386 | i486 | i586 | i686) ARCH="386" ;;
  *)
    echo "${FEATURE_ID}: unsupported architecture '$(uname -m)'." >&2
    exit 1
    ;;
esac

# curl, unzip, and gnupg are needed for this install only; unlike the apt-repository approach,
# nothing here has to stay behind for op to keep working. ca-certificates is the exception: op
# reads the system trust store at runtime, so removing it later breaks every command that reaches
# 1Password.
MISSING_PACKAGES=''
add_missing_package() {
  # $1: command to probe, $2: package(s) providing it
  if ! command -v "$1" >/dev/null 2>&1; then
    MISSING_PACKAGES="${MISSING_PACKAGES} $2"
  fi
}

add_missing_package curl "curl ca-certificates"
add_missing_package unzip unzip
add_missing_package gpg gnupg

# An image can ship curl while ca-certificates was skipped by --no-install-recommends; HTTPS then
# fails with a certificate error that reads like a missing release.
if command -v curl >/dev/null 2>&1 && [ ! -e /etc/ssl/certs/ca-certificates.crt ]; then
  if command -v apt-get >/dev/null 2>&1; then
    MISSING_PACKAGES="${MISSING_PACKAGES} ca-certificates"
  else
    # An image without apt-get may keep its trust store elsewhere, so this is not fatal. It is
    # still worth saying up front: it is the one thing that explains a certificate error below.
    echo "${FEATURE_ID}: no CA bundle at /etc/ssl/certs/ca-certificates.crt, and no apt-get to install one." >&2
    echo "${FEATURE_ID}: if a download below fails with a certificate error, this is why." >&2
  fi
fi

if [ -n "${MISSING_PACKAGES}" ]; then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "${FEATURE_ID}: the following are required but missing, and apt-get is unavailable to install them:${MISSING_PACKAGES}" >&2
    echo "${FEATURE_ID}: install them in your base image, or use a Debian/Ubuntu-based image." >&2
    exit 1
  fi
  apt-get update -y
  # Intentionally unquoted: MISSING_PACKAGES is a space-separated package list.
  # shellcheck disable=SC2086
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${MISSING_PACKAGES}
  rm -rf /var/lib/apt/lists/*
fi

if [ "${OP_VERSION}" = latest ]; then
  # The fetch is a separate step from the sed because POSIX sh has no pipefail: piped together, an
  # unreachable endpoint would be indistinguishable from a response carrying no version, and the
  # advice to pin a version would send the user after the wrong problem.
  # curl -f fails on an HTTP error status as well as on a connection or TLS failure, so the message
  # says what did not happen rather than guessing at the cause: with an HTTP error the endpoint is
  # reachable and pinning is the way around it, with a connection failure it is not.
  if ! VERSION_CHECK_RESPONSE="$(curl -fsSL --retry 3 "${VERSION_CHECK_URL}")"; then
    echo "${FEATURE_ID}: could not get a version check response from ${VERSION_CHECK_URL} (see curl's message above)." >&2
    echo "${FEATURE_ID}: if that was an HTTP error rather than a connection or TLS failure, setting the 'version' option to an exact version skips this endpoint entirely." >&2
    exit 1
  fi

  # Response shape: {"available":"1","version":"2.39.0","relnotes":"..."}
  # head -n 1 because sed prints one line per match: a multi-line response would otherwise put a
  # newline inside OP_VERSION, which passes the emptiness check below and breaks the archive name.
  OP_VERSION="$(printf '%s\n' "${VERSION_CHECK_RESPONSE}" |
    sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -n 1)"
  if [ -z "${OP_VERSION}" ]; then
    echo "${FEATURE_ID}: no version field in the response from ${VERSION_CHECK_URL}: ${VERSION_CHECK_RESPONSE}" >&2
    echo "${FEATURE_ID}: set the 'version' option to an exact version instead." >&2
    exit 1
  fi
fi
OP_VERSION="${OP_VERSION#v}"

TMP_DIR="$(mktemp -d)"
# Set OP_KEEP_TMP to investigate a verification failure: the downloaded binary, its signature, and
# the keyring gpg was given are otherwise gone by the time the error message is read.
cleanup() {
  if [ -n "${OP_KEEP_TMP:-}" ]; then
    echo "${FEATURE_ID}: OP_KEEP_TMP is set; leaving ${TMP_DIR} behind." >&2
    return
  fi
  rm -rf "${TMP_DIR}"
}
# The signal handlers exit rather than clean up directly: without the exit the script would carry on
# from the next command with its temp directory already deleted, and exiting runs the EXIT trap, so
# cleanup still happens exactly once.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ARCHIVE_NAME="op_linux_${ARCH}_v${OP_VERSION}.zip"

# Not every patch version is published for download, so a 404 here is a plausible user error. But
# network and TLS failures land here too, hence a hint rather than a diagnosis.
if ! curl -fsSL --retry 3 -o "${TMP_DIR}/${ARCHIVE_NAME}" "${DIST_BASE_URL}/v${OP_VERSION}/${ARCHIVE_NAME}"; then
  echo "${FEATURE_ID}: failed to download ${ARCHIVE_NAME} (see curl's message above)." >&2
  echo "${FEATURE_ID}: if that was a 404, version '${OP_VERSION}' may not be published for ${ARCH} at ${DIST_BASE_URL}/v${OP_VERSION}/." >&2
  exit 1
fi

if ! curl -fsSL --retry 3 -o "${TMP_DIR}/1password.asc" "${KEY_URL}"; then
  echo "${FEATURE_ID}: failed to download 1Password's code signing key from ${KEY_URL} (see curl's message above)." >&2
  exit 1
fi
unzip -q "${TMP_DIR}/${ARCHIVE_NAME}" op op.sig -d "${TMP_DIR}"

# Keep the imported key out of root's keyring; it is needed for this verification only.
GNUPGHOME="${TMP_DIR}/gnupg"
export GNUPGHOME
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"
gpg --batch --quiet --import "${TMP_DIR}/1password.asc"

# The failure paths below are not covered by the feature tests and cannot be: the harness treats a
# failed build as a failed test, so a case that must fail cannot be expressed. Run the manual
# procedure in test/op/negative-tests.md whenever this block changes.
#
# GOODSIG is required, not just VALIDSIG: gpg emits exactly one of GOODSIG / BADSIG / EXPSIG /
# EXPKEYSIG / REVKEYSIG / ERRSIG per signature, and a revoked or expired key still produces a
# VALIDSIG line. Matching VALIDSIG's last field (the primary key fingerprint) keeps working if
# 1Password starts signing with a subkey.
GPG_STATUS="${TMP_DIR}/gpg-status"
GPG_STDERR="${TMP_DIR}/gpg-stderr"
verification_failed=''
gpg --batch --status-file "${GPG_STATUS}" --verify "${TMP_DIR}/op.sig" "${TMP_DIR}/op" \
  2>"${GPG_STDERR}" || verification_failed=1
grep -qE '^\[GNUPG:\] GOODSIG ' "${GPG_STATUS}" || verification_failed=1
grep -qE "^\[GNUPG:\] VALIDSIG .* ${SIGNING_KEY_FINGERPRINT}\$" "${GPG_STATUS}" || verification_failed=1

if [ -n "${verification_failed}" ]; then
  echo "${FEATURE_ID}: signature verification failed for ${ARCHIVE_NAME}." >&2
  echo "${FEATURE_ID}: expected a good signature from 1Password's code signing key ${SIGNING_KEY_FINGERPRINT}," >&2
  echo "${FEATURE_ID}: made with a key that is neither revoked nor expired. gpg reported:" >&2
  sed "s/^/${FEATURE_ID}:   /" "${GPG_STDERR}" >&2
  exit 1
fi

# unzip restores the mode recorded in the archive, which is 1Password's to change; the run below
# should not be the thing that discovers it lost the execute bit.
chmod 755 "${TMP_DIR}/op"

# Run it here rather than after installing: this fails the install if the binary cannot run on this
# image and architecture, and it keeps a binary that fails the version check below out of
# $INSTALL_PATH. The assignment is the whole point: inside 'echo "$(...)"' the substitution's exit
# status is discarded and set -e sees only echo's success.
INSTALLED_VERSION="$("${TMP_DIR}/op" --version)"

# The signature proves the binary is one 1Password published. It says nothing about which version it
# is, because the version appears only in the URL and the file name, neither of which is signed. So
# this check is the only thing standing between a build that pinned a version and an older, equally
# well-signed release served in its place. Not checked for 'latest': there is no requested version
# to hold the binary to, and a formatting difference in the undocumented endpoint's response would
# then fail installs that are otherwise fine.
if [ -n "${VERSION_PINNED}" ] && [ "${INSTALLED_VERSION}" != "${OP_VERSION}" ]; then
  echo "${FEATURE_ID}: ${ARCHIVE_NAME} contains 1Password CLI ${INSTALLED_VERSION}, not the requested ${OP_VERSION}." >&2
  echo "${FEATURE_ID}: the signature verified, so this is 1Password serving a different release at ${DIST_BASE_URL}/v${OP_VERSION}/, not a tampered download." >&2
  exit 1
fi

install -o root -g root -m 755 "${TMP_DIR}/op" "${INSTALL_PATH}"

echo "${FEATURE_ID}: installed 1Password CLI ${INSTALLED_VERSION} at ${INSTALL_PATH}"

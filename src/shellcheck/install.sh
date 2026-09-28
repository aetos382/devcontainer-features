#!/bin/sh
set -eu

FEATURE_ID='shellcheck'
INSTALL_PATH='/usr/local/bin/shellcheck'

# There is deliberately no 'version' option: each release of this feature installs exactly the
# ShellCheck version below, so that only one set of digests has to be kept here. To move to a newer
# ShellCheck, update the version and both digests together and release a new version of this
# feature. devcontainer-lock.json pins the feature version, and with it the ShellCheck version.
SHELLCHECK_VERSION='v0.11.0'

if [ "$(id -u)" -ne 0 ]; then
  echo "${FEATURE_ID}: install.sh must be run as root." >&2
  exit 1
fi

# ShellCheck publishes no checksum files. These are the sha256 digests GitHub computes for the
# release assets (the 'digest' field of the releases API), cross-checked against a fresh download.
# They pin the exact bytes, which is what makes the version check further down unnecessary.
case "$(uname -m)" in
  x86_64 | amd64)
    ARCH='x86_64'
    SHA256='8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198'
    ;;
  aarch64 | arm64)
    ARCH='aarch64'
    SHA256='12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588'
    ;;
  *)
    echo "${FEATURE_ID}: unsupported architecture '$(uname -m)'." >&2
    exit 1
    ;;
esac

# curl and xz are needed for this install only; the binary itself is statically linked and needs
# nothing at runtime.
MISSING_PACKAGES=''
add_missing_package() {
  # $1: command to probe, $2: package(s) providing it
  if ! command -v "$1" >/dev/null 2>&1; then
    MISSING_PACKAGES="${MISSING_PACKAGES} $2"
  fi
}

add_missing_package 'curl' 'curl ca-certificates'
# tar -J shells out to xz; tar itself does not decompress it.
add_missing_package 'xz' 'xz-utils'

# An image can ship curl while ca-certificates was skipped by --no-install-recommends; HTTPS then
# fails with a certificate error that reads like a missing release.
if command -v 'curl' >/dev/null 2>&1 && [ ! -e '/etc/ssl/certs/ca-certificates.crt' ]; then
  if command -v 'apt-get' >/dev/null 2>&1; then
    MISSING_PACKAGES="${MISSING_PACKAGES} ca-certificates"
  else
    echo "${FEATURE_ID}: no CA bundle at /etc/ssl/certs/ca-certificates.crt, and no apt-get to install one." >&2
    echo "${FEATURE_ID}: if the download below fails with a certificate error, this is why." >&2
  fi
fi

if [ -n "${MISSING_PACKAGES}" ]; then
  if ! command -v 'apt-get' >/dev/null 2>&1; then
    echo "${FEATURE_ID}: the following are required but missing, and apt-get is unavailable to install them:${MISSING_PACKAGES}" >&2
    echo "${FEATURE_ID}: install them in your base image, or use a Debian/Ubuntu-based image." >&2
    exit 1
  fi
  apt-get update -y
  # Intentionally unquoted: MISSING_PACKAGES is a space-separated package list.
  # shellcheck disable=SC2086
  DEBIAN_FRONTEND='noninteractive' apt-get install -y --no-install-recommends ${MISSING_PACKAGES}
  rm -rf /var/lib/apt/lists/*
fi

TMP_DIR="$(mktemp -d)"
# The signal handlers exit rather than clean up directly: exiting runs the EXIT trap, so cleanup
# happens exactly once and the script does not carry on with its temp directory gone.
trap 'rm -rf "${TMP_DIR}"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ARCHIVE_NAME="shellcheck-${SHELLCHECK_VERSION}.linux.${ARCH}.tar.xz"
URL="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/${ARCHIVE_NAME}"

if ! curl -fsSL --retry 3 -o "${TMP_DIR}/${ARCHIVE_NAME}" "${URL}"; then
  echo "${FEATURE_ID}: failed to download ${URL} (see curl's message above)." >&2
  exit 1
fi

if ! printf '%s  %s\n' "${SHA256}" "${TMP_DIR}/${ARCHIVE_NAME}" | sha256sum -c - >/dev/null; then
  echo "${FEATURE_ID}: sha256 mismatch for ${ARCHIVE_NAME}." >&2
  echo "${FEATURE_ID}: expected ${SHA256}," >&2
  echo "${FEATURE_ID}: got      $(sha256sum "${TMP_DIR}/${ARCHIVE_NAME}" | cut -d ' ' -f 1)." >&2
  exit 1
fi

tar -xJf "${TMP_DIR}/${ARCHIVE_NAME}" -C "${TMP_DIR}" "shellcheck-${SHELLCHECK_VERSION}/shellcheck"
EXTRACTED_PATH="${TMP_DIR}/shellcheck-${SHELLCHECK_VERSION}/shellcheck"

# Run it before installing so that a binary that cannot run on this image and architecture fails
# the install instead of landing on PATH. The assignment matters: inside 'echo "$(...)"' the
# substitution's exit status would be discarded and set -e would see only echo's success.
VERSION_OUTPUT="$("${EXTRACTED_PATH}" --version)"

install -o 'root' -g 'root' -m 755 "${EXTRACTED_PATH}" "${INSTALL_PATH}"

echo "${FEATURE_ID}: installed $(printf '%s\n' "${VERSION_OUTPUT}" | sed -n 's/^version: //p') at ${INSTALL_PATH}"

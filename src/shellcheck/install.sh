#!/bin/sh
set -eu

FEATURE_ID='shellcheck'
INSTALL_PATH='/usr/local/bin/shellcheck'

# There is deliberately no 'version' option: each release of this feature installs exactly the
# ShellCheck version below, so that only one set of digests has to be kept here. To move to a newer
# ShellCheck, update the version and every digest together and release a new version of this
# feature. devcontainer-lock.json pins the feature version, and with it the ShellCheck version.
SHELLCHECK_VERSION='v0.11.0'

if [ "$(id -u)" -ne 0 ]; then
  echo "${FEATURE_ID}: install.sh must be run as root." >&2
  exit 1
fi

# ShellCheck publishes no checksum files. These are the sha256 digests GitHub computes for the
# release assets (the 'digest' field of the releases API), cross-checked against a fresh download.
# They pin the exact bytes, so the version the binary reports needs no separate check here; the
# run before installing below only confirms that the binary works on this image.
#
# The .tar.gz assets are used rather than .tar.xz because gzip is essential on Debian and Ubuntu,
# whereas xz-utils would have to be installed just for this.
#
# The unsupported-architecture exit is covered by negative-tests.md.
case "$(uname -m)" in
  x86_64 | amd64)
    ARCH='x86_64'
    SHA256='b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6'
    ;;
  aarch64 | arm64)
    ARCH='aarch64'
    SHA256='68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc'
    ;;
  riscv64)
    ARCH='riscv64'
    SHA256='a70e86454e9ae1a328aeafe62629d04ffea93b99138bfe1203083e2621b5ca4f'
    ;;
  # Upstream's only 32-bit ARM build targets ARMv6 with hard float, which ARMv7 also runs.
  armv6l | armv7l)
    ARCH='armv6hf'
    SHA256='89f29e76e881122416eb95947f812b1496ff9a46d1e1676abe1e3f3f903b0f46'
    ;;
  *)
    echo "${FEATURE_ID}: unsupported architecture '$(uname -m)'." >&2
    exit 1
    ;;
esac

# The binary itself is statically linked and needs nothing at runtime; these are only needed to
# download and unpack it.
MISSING_PACKAGES=''
add_missing_package() {
  # $1: command to probe, $2: package(s) providing it
  if ! command -v "$1" >/dev/null 2>&1; then
    MISSING_PACKAGES="${MISSING_PACKAGES} $2"
  fi
}

add_missing_package 'curl' 'curl ca-certificates'
add_missing_package 'tar' 'tar'
# tar -z shells out to gzip; tar itself does not decompress it.
add_missing_package 'gzip' 'gzip'

# An image can ship curl while ca-certificates was skipped by --no-install-recommends; HTTPS then
# fails with a certificate error that reads like a missing release.
if command -v 'curl' >/dev/null 2>&1 && [ ! -e '/etc/ssl/certs/ca-certificates.crt' ]; then
  if command -v 'apt-get' >/dev/null 2>&1; then
    MISSING_PACKAGES="${MISSING_PACKAGES} ca-certificates"
  else
    # Not fatal: an image without apt-get may keep its trust store elsewhere.
    echo "${FEATURE_ID}: no CA bundle at /etc/ssl/certs/ca-certificates.crt, and no apt-get to install one." >&2
    echo "${FEATURE_ID}: if the download below fails with a certificate error, this is why." >&2
  fi
fi

# The exit for missing dependencies without apt-get is covered by negative-tests.md.
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

ARCHIVE_NAME="shellcheck-${SHELLCHECK_VERSION}.linux.${ARCH}.tar.gz"
URL="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/${ARCHIVE_NAME}"

# Download and digest failures are covered by negative-tests.md.
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

# The digest already matched, so a failure here is a local problem (disk space, a broken tar or
# gzip) rather than a bad download.
if ! tar -xzf "${TMP_DIR}/${ARCHIVE_NAME}" -C "${TMP_DIR}" "shellcheck-${SHELLCHECK_VERSION}/shellcheck"; then
  echo "${FEATURE_ID}: failed to unpack ${ARCHIVE_NAME} into ${TMP_DIR} (see tar's message above)." >&2
  exit 1
fi
EXTRACTED_PATH="${TMP_DIR}/shellcheck-${SHELLCHECK_VERSION}/shellcheck"

# Run it before installing so that a binary that cannot run on this image and architecture fails
# the install instead of landing on PATH.
if ! "${EXTRACTED_PATH}" --version >/dev/null; then
  echo "${FEATURE_ID}: the downloaded shellcheck binary does not run on this image." >&2
  echo "${FEATURE_ID}: if the message above is 'Permission denied', ${TMP_DIR} may be on a noexec mount; set TMPDIR to another directory." >&2
  exit 1
fi

install -o 'root' -g 'root' -m 755 "${EXTRACTED_PATH}" "${INSTALL_PATH}"

echo "${FEATURE_ID}: installed ShellCheck ${SHELLCHECK_VERSION} (${ARCH}) at ${INSTALL_PATH}"

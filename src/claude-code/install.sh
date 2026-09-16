#!/bin/sh
set -eu

FEATURE_ID='claude-code'
INSTALL_PATH='/usr/local/bin/claude'
MOUNT_POINT='/var/lib/claude-code'
SHARE_DIR="/usr/local/share/${FEATURE_ID}"

# Anthropic's release bucket, and the verification procedure documented at
# https://code.claude.com/docs/en/setup#binary-integrity-and-code-signing: manifest.json lists a
# SHA256 for every platform binary, and manifest.json.sig is a detached signature over that
# manifest, so verifying the signature transitively verifies the binary.
#
# The official installer at https://claude.ai/install.sh is deliberately not used. It is only a
# bootstrapper: it downloads the newest binary, checks it against manifest.json, and hands the real
# work to 'claude install'. It never verifies manifest.json.sig, so doing the download here is a
# stronger check, not a weaker one. It also installs under one user's home directory, which is not
# what this feature wants.
DOWNLOAD_BASE_URL='https://downloads.claude.ai/claude-code-releases'
KEY_URL='https://downloads.claude.ai/keys/claude-code.asc'

# Pinning the fingerprint is what makes the verification meaningful: without it, a key served
# alongside a tampered manifest would also pass.
SIGNING_KEY_FINGERPRINT='31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE'

# Option values reach install.sh as uppercased environment variables.
CC_VERSION="${VERSION:-latest}"
PERSISTENCE="${PERSISTENCE:-true}"

if [ "$(id -u)" -ne 0 ]; then
  echo "${FEATURE_ID}: install.sh must be run as root." >&2
  exit 1
fi

cd "$(dirname "$0")"

if [ -z "${_REMOTE_USER:-}" ]; then
  echo "${FEATURE_ID}: _REMOTE_USER is not set; install.sh must be run by the devcontainer CLI." >&2
  exit 1
fi
TARGET_USER="${_REMOTE_USER}"

if [ "$(uname -s)" != 'Linux' ]; then
  echo "${FEATURE_ID}: unsupported operating system '$(uname -s)'; the release bucket only carries Linux builds usable here." >&2
  exit 1
fi

# uname -m rather than 'dpkg --print-architecture' so that architecture detection does not itself
# depend on Debian tooling.
case "$(uname -m)" in
  x86_64 | amd64) ARCH='x64' ;;
  aarch64 | arm64) ARCH='arm64' ;;
  *)
    echo "${FEATURE_ID}: unsupported architecture '$(uname -m)'; Claude Code is published for x86_64 and aarch64 only." >&2
    exit 1
    ;;
esac

# The bucket publishes separate musl builds, and a glibc binary will not run on Alpine. ldd's exit
# status is not consulted because it fails for reasons unrelated to the libc in use; only its output
# is inspected, matching what the official installer does.
if [ -f '/lib/libc.musl-x86_64.so.1' ] || [ -f '/lib/libc.musl-aarch64.so.1' ] ||
   ldd '/bin/ls' 2>&1 | grep -q 'musl'; then
  PLATFORM="linux-${ARCH}-musl"
else
  PLATFORM="linux-${ARCH}"
fi

# curl, gnupg, and sha256sum are needed for this install only; nothing here has to stay behind for
# claude to keep working. ca-certificates is the exception: Claude Code reads the system trust store
# at runtime, so removing it later breaks every request it makes.
MISSING_PACKAGES=''
add_missing_package() {
  # $1: command to probe, $2: package(s) providing it
  if ! command -v "$1" >/dev/null 2>&1; then
    MISSING_PACKAGES="${MISSING_PACKAGES} $2"
  fi
}

add_missing_package 'curl' 'curl ca-certificates'
add_missing_package 'gpg' 'gnupg'
add_missing_package 'sha256sum' 'coreutils'

# An image can ship curl while ca-certificates was skipped by --no-install-recommends; HTTPS then
# fails with a certificate error that reads like a missing release.
if command -v 'curl' >/dev/null 2>&1 && [ ! -e '/etc/ssl/certs/ca-certificates.crt' ]; then
  if command -v 'apt-get' >/dev/null 2>&1; then
    MISSING_PACKAGES="${MISSING_PACKAGES} ca-certificates"
  else
    # An image without apt-get may keep its trust store elsewhere, so this is not fatal. It is
    # still worth saying up front: it is the one thing that explains a certificate error below.
    echo "${FEATURE_ID}: no CA bundle at /etc/ssl/certs/ca-certificates.crt, and no apt-get to install one." >&2
    echo "${FEATURE_ID}: if a download below fails with a certificate error, this is why." >&2
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

case "${CC_VERSION}" in
  latest | stable)
    # The channel pointers are plain-text documents holding nothing but a version number. The fetch
    # is kept separate from the trimming below because POSIX sh has no pipefail: piped together, an
    # unreachable endpoint would be indistinguishable from a response carrying no version.
    if ! CHANNEL_RESPONSE="$(curl -fsSL --retry 3 "${DOWNLOAD_BASE_URL}/${CC_VERSION}")"; then
      echo "${FEATURE_ID}: could not resolve the '${CC_VERSION}' channel from ${DOWNLOAD_BASE_URL}/${CC_VERSION} (see curl's message above)." >&2
      echo "${FEATURE_ID}: setting the 'version' option to an exact version skips this endpoint entirely." >&2
      exit 1
    fi
    # head -n 1 because a multi-line response would otherwise put a newline inside the version and
    # break every URL built from it below.
    RESOLVED_VERSION="$(printf '%s\n' "${CHANNEL_RESPONSE}" | head -n 1 | tr -d '\r')"
    ;;
  *)
    RESOLVED_VERSION="${CC_VERSION#v}"
    ;;
esac

# Catches an HTML error page here rather than at the manifest URL, where it would surface as a 404
# and send the reader after a version that was never the problem. Anchored at both ends so that
# nothing unexpected reaches the URLs and the shell patterns built from this below; the optional
# suffix matches what the official installer accepts, for prerelease builds.
if ! printf '%s\n' "${RESOLVED_VERSION}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[^[:space:]]+)?$'; then
  echo "${FEATURE_ID}: '${RESOLVED_VERSION}' does not look like a Claude Code version." >&2
  echo "${FEATURE_ID}: if the 'version' option named a channel, downloads.claude.ai may be unreachable or unavailable in this region (https://www.anthropic.com/supported-countries)." >&2
  exit 1
fi

RELEASE_URL="${DOWNLOAD_BASE_URL}/${RESOLVED_VERSION}"

TMP_DIR="$(mktemp -d)"
# Set CLAUDE_CODE_KEEP_TMP to investigate a verification failure: the manifest, its signature, the
# keyring gpg was given, and the downloaded binary are otherwise gone by the time the error message
# is read.
cleanup() {
  if [ -n "${CLAUDE_CODE_KEEP_TMP:-}" ]; then
    echo "${FEATURE_ID}: CLAUDE_CODE_KEEP_TMP is set; leaving ${TMP_DIR} behind." >&2
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

if ! curl -fsSL --retry 3 -o "${TMP_DIR}/manifest.json" "${RELEASE_URL}/manifest.json"; then
  echo "${FEATURE_ID}: failed to download the release manifest from ${RELEASE_URL}/manifest.json (see curl's message above)." >&2
  echo "${FEATURE_ID}: if that was a 404, version '${RESOLVED_VERSION}' does not exist." >&2
  exit 1
fi

# Releases before 2.1.89 publish manifest.json without a detached signature. Installing one would
# mean dropping the signature check entirely, so this feature refuses instead.
if ! curl -fsSL --retry 3 -o "${TMP_DIR}/manifest.json.sig" "${RELEASE_URL}/manifest.json.sig"; then
  echo "${FEATURE_ID}: failed to download the manifest signature from ${RELEASE_URL}/manifest.json.sig (see curl's message above)." >&2
  echo "${FEATURE_ID}: if that was a 404, version '${RESOLVED_VERSION}' predates 2.1.89 and is unsigned; this feature requires a signed manifest." >&2
  exit 1
fi

if ! curl -fsSL --retry 3 -o "${TMP_DIR}/claude-code.asc" "${KEY_URL}"; then
  echo "${FEATURE_ID}: failed to download Anthropic's release signing key from ${KEY_URL} (see curl's message above)." >&2
  exit 1
fi

# Keep the imported key out of root's keyring; it is needed for this verification only.
GNUPGHOME="${TMP_DIR}/gnupg"
export GNUPGHOME
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"
gpg --batch --quiet --import "${TMP_DIR}/claude-code.asc"

# The failure paths below are not covered by the feature tests and cannot be: the harness treats a
# failed build as a failed test, so a case that must fail cannot be expressed. Run the manual
# procedure in test/claude-code/negative-tests.md whenever this block changes.
#
# GOODSIG is required, not just VALIDSIG: gpg emits exactly one of GOODSIG / BADSIG / EXPSIG /
# EXPKEYSIG / REVKEYSIG / ERRSIG per signature, and a revoked or expired key still produces a
# VALIDSIG line. Matching VALIDSIG's last field (the primary key fingerprint) keeps working if
# Anthropic starts signing with a subkey.
GPG_STATUS="${TMP_DIR}/gpg-status"
GPG_STDERR="${TMP_DIR}/gpg-stderr"
verification_failed=''
gpg --batch --status-file "${GPG_STATUS}" --verify "${TMP_DIR}/manifest.json.sig" "${TMP_DIR}/manifest.json" \
  2>"${GPG_STDERR}" || verification_failed=1
grep -qE '^\[GNUPG:\] GOODSIG ' "${GPG_STATUS}" || verification_failed=1
grep -qE "^\[GNUPG:\] VALIDSIG .* ${SIGNING_KEY_FINGERPRINT}\$" "${GPG_STATUS}" || verification_failed=1

if [ -n "${verification_failed}" ]; then
  echo "${FEATURE_ID}: signature verification failed for the ${RESOLVED_VERSION} release manifest." >&2
  echo "${FEATURE_ID}: expected a good signature from Anthropic's release signing key ${SIGNING_KEY_FINGERPRINT}," >&2
  echo "${FEATURE_ID}: made with a key that is neither revoked nor expired. gpg reported:" >&2
  sed "s/^/${FEATURE_ID}:   /" "${GPG_STDERR}" >&2
  exit 1
fi

# jq cannot be assumed, so the manifest is flattened to one line and read with sed. [^}] keeps the
# match inside the platform's own object, and the 64-hex pattern means a malformed value is reported
# as a missing checksum rather than compared against the download.
CHECKSUM="$(tr -d ' \n\t' < "${TMP_DIR}/manifest.json" |
  sed -n "s/.*\"${PLATFORM}\":{[^}]*\"checksum\":\"\([a-f0-9]\{64\}\)\".*/\1/p" | head -n 1)"

if [ -z "${CHECKSUM}" ]; then
  echo "${FEATURE_ID}: the signed ${RESOLVED_VERSION} manifest carries no checksum for platform '${PLATFORM}'." >&2
  exit 1
fi

if ! curl -fsSL --retry 3 -o "${TMP_DIR}/claude" "${RELEASE_URL}/${PLATFORM}/claude"; then
  echo "${FEATURE_ID}: failed to download the ${PLATFORM} binary from ${RELEASE_URL}/${PLATFORM}/claude (see curl's message above)." >&2
  exit 1
fi

ACTUAL_CHECKSUM="$(sha256sum "${TMP_DIR}/claude" | cut -d ' ' -f 1)"
if [ "${ACTUAL_CHECKSUM}" != "${CHECKSUM}" ]; then
  echo "${FEATURE_ID}: checksum mismatch for the ${PLATFORM} binary of ${RESOLVED_VERSION}." >&2
  echo "${FEATURE_ID}: the signed manifest lists ${CHECKSUM}, but the download hashes to ${ACTUAL_CHECKSUM}." >&2
  exit 1
fi

chmod 755 "${TMP_DIR}/claude"

# Run it here rather than after installing: this fails the install if the binary cannot run on this
# image and architecture, and it keeps a binary that fails the version check below out of
# $INSTALL_PATH. HOME and CLAUDE_CONFIG_DIR are redirected so that the run cannot seed configuration
# into root's home directory, which post-create.sh would later report as a conflicting ~/.claude.
# The assignment is the whole point: inside 'echo "$(...)"' the substitution's exit status is
# discarded and set -e sees only echo's success.
mkdir -p "${TMP_DIR}/home"
INSTALLED_VERSION="$(HOME="${TMP_DIR}/home" CLAUDE_CONFIG_DIR="${TMP_DIR}/home/.claude" "${TMP_DIR}/claude" --version)"

# The signature and checksum prove the binary is one Anthropic published. They say nothing about
# which version it is, because the version appears only in the URL, so this check is the only thing
# standing between a build that pinned a version and a different, equally well-signed release served
# in its place. 'claude --version' prints '2.1.267 (Claude Code)', and only the leading version is
# compared so that a change to the parenthesised suffix does not fail the install.
case "${INSTALLED_VERSION}" in
  "${RESOLVED_VERSION}" | "${RESOLVED_VERSION} "*) ;;
  *)
    echo "${FEATURE_ID}: the binary at ${RELEASE_URL}/${PLATFORM}/claude reports '${INSTALLED_VERSION}', not the expected ${RESOLVED_VERSION}." >&2
    echo "${FEATURE_ID}: the manifest signature verified, so this is Anthropic serving a different release at that URL, not a tampered download." >&2
    exit 1
    ;;
esac

install -o 'root' -g 'root' -m 755 "${TMP_DIR}/claude" "${INSTALL_PATH}"

mkdir -p "${SHARE_DIR}"
cp 'post-create.sh' 'entrypoint.sh' "${SHARE_DIR}/"
chmod 755 "${SHARE_DIR}/post-create.sh" "${SHARE_DIR}/entrypoint.sh"
printf '%s\n' "${TARGET_USER}" > "${SHARE_DIR}/remote-user"

if [ "${PERSISTENCE}" = 'true' ]; then
  mkdir -p "${MOUNT_POINT}"

  # Docker initializes an empty named volume with the ownership of the image-side directory.
  # This is intentionally redundant with entrypoint.sh, which re-fixes ownership on every container
  # start and is what test/claude-code actually exercises for non-root correctness; if this chown
  # alone were broken, entrypoint.sh (and post-create.sh's sudo fallback, when available) would
  # silently cover for it. Not worth a dedicated test scenario for that failure mode.
  if id -u "${TARGET_USER}" >/dev/null 2>&1; then
    TARGET_GROUP="$(id -gn "${TARGET_USER}")"
    chown "${TARGET_USER}:${TARGET_GROUP}" "${MOUNT_POINT}"
    chmod 700 "${MOUNT_POINT}"
  else
    echo "${FEATURE_ID}: warning: user '${TARGET_USER}' does not exist at build time; ${MOUNT_POINT} is left owned by root." >&2
  fi

  # The guard must live inside the snippet so that values from containerEnv, applied after the build, win.
  # Single-quoted heredoc, so the path is spelled out rather than interpolated from $MOUNT_POINT:
  # an unquoted heredoc would also expand the $CLAUDE_CONFIG_DIR references that have to survive
  # into the generated file.
  cat > "/etc/profile.d/${FEATURE_ID}.sh" <<'EOF'
if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
  export CLAUDE_CONFIG_DIR='/var/lib/claude-code'
fi
EOF
  chmod 644 "/etc/profile.d/${FEATURE_ID}.sh"

  # devcontainer-feature.json wires up entrypoint.sh and postCreateCommand unconditionally, because
  # neither can be made conditional on an option. This marker is what tells them persistence is on.
  : > "${SHARE_DIR}/persistence-enabled"
fi

echo "${FEATURE_ID}: installed Claude Code ${RESOLVED_VERSION} (${PLATFORM}) at ${INSTALL_PATH}"

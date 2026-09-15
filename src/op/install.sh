#!/bin/sh
set -eu

FEATURE_ID=op
INSTALL_PATH=/usr/local/bin/op

# Option values reach install.sh as uppercased environment variables.
OP_VERSION="${VERSION:-latest}"

# 1Password does not publish the CLI on GitHub; these are the endpoints its own installation
# instructions and update checks use.
DIST_BASE_URL=https://cache.agilebits.com/dist/1P/op2/pkg
KEY_URL=https://downloads.1password.com/linux/keys/1password.asc
VERSION_CHECK_URL=https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N

# The release archive ships op.sig next to the binary. Pinning the fingerprint is what makes the
# verification meaningful: without it, a key served alongside a tampered binary would also pass.
SIGNING_KEY_FINGERPRINT=3FEF9748469ADBE15DA7CA80AC2D62742012EA22

if [ "$(id -u)" -ne 0 ]; then
  echo "$FEATURE_ID: install.sh must be run as root." >&2
  exit 1
fi

# uname -m rather than 'dpkg --print-architecture' so that architecture detection does not itself
# depend on Debian tooling.
case "$(uname -m)" in
  x86_64 | amd64) ARCH=amd64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  armv7l | armv7 | armhf) ARCH=arm ;;
  i386 | i486 | i586 | i686) ARCH=386 ;;
  *)
    echo "$FEATURE_ID: unsupported architecture '$(uname -m)'." >&2
    exit 1
    ;;
esac

# Build dependencies only; unlike the apt-repository approach, nothing here is needed to keep op
# working afterwards.
MISSING_PACKAGES=''
add_missing_package() {
  # $1: command to probe, $2: package(s) providing it
  if ! command -v "$1" >/dev/null 2>&1; then
    MISSING_PACKAGES="$MISSING_PACKAGES $2"
  fi
}

add_missing_package curl "curl ca-certificates"
add_missing_package unzip unzip
add_missing_package gpg gnupg

if [ -n "$MISSING_PACKAGES" ]; then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "$FEATURE_ID: the following are required but missing, and apt-get is unavailable to install them:$MISSING_PACKAGES" >&2
    echo "$FEATURE_ID: install them in your base image, or use a Debian/Ubuntu-based image." >&2
    exit 1
  fi
  apt-get update -y
  # Intentionally unquoted: MISSING_PACKAGES is a space-separated package list.
  # shellcheck disable=SC2086
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $MISSING_PACKAGES
  rm -rf /var/lib/apt/lists/*
fi

if [ "$OP_VERSION" = latest ]; then
  # Response shape: {"available":"1","version":"2.39.0","relnotes":"..."}
  OP_VERSION="$(curl -fsSL --retry 3 "$VERSION_CHECK_URL" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
  if [ -z "$OP_VERSION" ]; then
    echo "$FEATURE_ID: could not determine the latest version from $VERSION_CHECK_URL." >&2
    echo "$FEATURE_ID: set the 'version' option to an exact version instead." >&2
    exit 1
  fi
fi
OP_VERSION="${OP_VERSION#v}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

ARCHIVE_NAME="op_linux_${ARCH}_v${OP_VERSION}.zip"

# Not every patch version is published for download, so a 404 here is a plausible user error
# rather than an infrastructure failure.
if ! curl -fsSL --retry 3 -o "$TMP_DIR/$ARCHIVE_NAME" "$DIST_BASE_URL/v$OP_VERSION/$ARCHIVE_NAME"; then
  echo "$FEATURE_ID: failed to download $ARCHIVE_NAME." >&2
  echo "$FEATURE_ID: check that version '$OP_VERSION' is published for $ARCH at $DIST_BASE_URL/v$OP_VERSION/." >&2
  exit 1
fi

curl -fsSL --retry 3 -o "$TMP_DIR/1password.asc" "$KEY_URL"
unzip -q "$TMP_DIR/$ARCHIVE_NAME" op op.sig -d "$TMP_DIR"

# Keep the imported key out of root's keyring; it is needed for this verification only.
GNUPGHOME="$TMP_DIR/gnupg"
export GNUPGHOME
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
gpg --batch --quiet --import "$TMP_DIR/1password.asc"

# The last field of VALIDSIG is the primary key fingerprint, so matching there keeps working if
# 1Password starts signing with a subkey.
if ! gpg --batch --quiet --status-fd 1 --verify "$TMP_DIR/op.sig" "$TMP_DIR/op" 2>/dev/null |
  grep -qE "^\[GNUPG:\] VALIDSIG .* $SIGNING_KEY_FINGERPRINT\$"; then
  echo "$FEATURE_ID: signature verification failed for $ARCHIVE_NAME." >&2
  echo "$FEATURE_ID: expected a signature from 1Password's code signing key $SIGNING_KEY_FINGERPRINT." >&2
  exit 1
fi

install -o root -g root -m 755 "$TMP_DIR/op" "$INSTALL_PATH"

# Also confirms that the binary actually runs on this image and architecture.
echo "$FEATURE_ID: installed 1Password CLI $("$INSTALL_PATH" --version) at $INSTALL_PATH"

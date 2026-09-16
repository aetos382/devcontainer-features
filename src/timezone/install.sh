#!/bin/sh
set -eu

FEATURE_ID="timezone"

# Option values reach install.sh as uppercased environment variables.
TIMEZONE="${TIMEZONE:-Etc/UTC}"
ZONEINFO="/usr/share/zoneinfo/${TIMEZONE}"

if [ "$(id -u)" -ne 0 ]; then
  echo "${FEATURE_ID}: install.sh must be run as root." >&2
  exit 1
fi

# Rejects anything that isn't a TZif regular file inside /usr/share/zoneinfo, so a directory
# (e.g. "Asia"), a non-zoneinfo file (e.g. "zone.tab"), or a value that traverses outside
# the zoneinfo tree (e.g. "../../../etc/passwd") can't end up behind /etc/localtime.
is_valid_zoneinfo() {
  resolved="$(readlink -f "${ZONEINFO}" 2>/dev/null)" || return 1
  case "${resolved}" in
    /usr/share/zoneinfo/*) [ -f "${resolved}" ] || return 1 ;;
    *) return 1 ;;
  esac
  [ "$(head -c 4 "${resolved}" 2>/dev/null)" = "TZif" ]
}

if ! is_valid_zoneinfo; then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "${FEATURE_ID}: the 'tzdata' package is required but apt-get is unavailable to install it." >&2
    echo "${FEATURE_ID}: install 'tzdata' yourself, or use a Debian/Ubuntu-based image." >&2
    exit 1
  fi
  apt-get update -y
  # DEBIAN_FRONTEND=noninteractive is what keeps tzdata's postinst from prompting; tzdata's own
  # postinst unsets TZ, so the actual zone this feature wants is set below via /etc/localtime,
  # regardless of what tzdata's postinst configures here.
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata
  rm -rf /var/lib/apt/lists/*
fi

if ! is_valid_zoneinfo; then
  echo "${FEATURE_ID}: timezone '${TIMEZONE}' is not a valid zoneinfo entry." >&2
  exit 1
fi

# Symlinked rather than copied, so that a tzdata upgrade later on picks up DST rule changes for
# this zone without this feature having to run again. -n keeps ln from resolving into an
# existing directory target if /etc/localtime were ever one.
ln -sfn "${ZONEINFO}" /etc/localtime
printf '%s\n' "${TIMEZONE}" > /etc/timezone

echo "${FEATURE_ID}: set timezone to ${TIMEZONE}"

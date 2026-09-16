#!/bin/sh
set -eu

FEATURE_ID=timezone

# Option values reach install.sh as uppercased environment variables.
TIMEZONE="${TIMEZONE:-Etc/UTC}"
ZONEINFO="/usr/share/zoneinfo/$TIMEZONE"

if [ "$(id -u)" -ne 0 ]; then
  echo "$FEATURE_ID: install.sh must be run as root." >&2
  exit 1
fi

if [ ! -e "$ZONEINFO" ]; then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "$FEATURE_ID: the 'tzdata' package is required but apt-get is unavailable to install it." >&2
    echo "$FEATURE_ID: install 'tzdata' yourself, or use a Debian/Ubuntu-based image." >&2
    exit 1
  fi
  apt-get update -y
  # TZ is set for this command only, so that tzdata's postinst configures itself non-interactively
  # instead of prompting; it does not depend on install.sh's own environment being clean afterward.
  DEBIAN_FRONTEND=noninteractive TZ="$TIMEZONE" apt-get install -y --no-install-recommends tzdata
  rm -rf /var/lib/apt/lists/*
fi

if [ ! -e "$ZONEINFO" ]; then
  echo "$FEATURE_ID: timezone '$TIMEZONE' does not exist at $ZONEINFO." >&2
  exit 1
fi

# Symlinked rather than copied, so that a tzdata upgrade later on picks up DST rule changes for
# this zone without this feature having to run again.
ln -sf "$ZONEINFO" /etc/localtime
printf '%s\n' "$TIMEZONE" > /etc/timezone

echo "$FEATURE_ID: set timezone to $TIMEZONE"

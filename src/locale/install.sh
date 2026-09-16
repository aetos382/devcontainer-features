#!/bin/sh
set -eu

FEATURE_ID="locale"

# Option values reach install.sh as uppercased environment variables.
LOCALE="${LOCALE:-en_US}"
LOCALE_UTF8="$LOCALE.UTF-8"

if [ "$(id -u)" -ne 0 ]; then
  echo "$FEATURE_ID: install.sh must be run as root." >&2
  exit 1
fi

# localedef itself ships in libc-bin and is present on a bare Debian/Ubuntu image; the charmaps and
# locale sources it needs come from the 'locales' package, so that directory, not the command, is
# what decides whether 'locales' still needs installing.
if [ ! -d /usr/share/i18n/charmaps ]; then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "$FEATURE_ID: the 'locales' package is required but apt-get is unavailable to install it." >&2
    echo "$FEATURE_ID: install 'locales' yourself, or use a Debian/Ubuntu-based image." >&2
    exit 1
  fi
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends locales
  rm -rf /var/lib/apt/lists/*
fi

localedef -i "$LOCALE" -f UTF-8 "$LOCALE_UTF8"
update-locale LANG="$LOCALE_UTF8"

# update-locale alone only takes effect through PAM on login, and not at all for a login shell
# started outside PAM (e.g. VS Code Server). The profile.d snippet covers those cases too.
#
# Set unconditionally, not just when unset: Debian/Ubuntu base images already export LANG (usually
# C.UTF-8) as part of the image itself, so a guard that only fills in an empty value would never
# fire. There is no way to tell that inherited default apart from a value the user actually wants
# kept, so the option this feature was given is treated as the deciding one.
cat > /etc/profile.d/$FEATURE_ID.sh <<EOF
export LANG=$LOCALE_UTF8
export LANGUAGE=$LOCALE_UTF8
export LC_ALL=$LOCALE_UTF8
EOF
chmod 644 /etc/profile.d/$FEATURE_ID.sh

echo "$FEATURE_ID: generated locale $LOCALE_UTF8"

#!/bin/sh
set -eu

FEATURE_ID='locale'

# Option values reach install.sh as uppercased environment variables.
LOCALE="${LOCALE:-en_US}"

# The codeset goes before '@variant', not after: glibc's own locale names follow
# language_territory.codeset@variant (e.g. "ca_ES.UTF-8@valencia"). Appending ".UTF-8"
# unconditionally would instead produce "ca_ES@valencia.UTF-8", which locale-gen's own '@'
# splitting logic misparses into a source file name that does not exist.
case "${LOCALE}" in
  *@*) LOCALE_UTF8="${LOCALE%%@*}.UTF-8@${LOCALE#*@}" ;;
  *) LOCALE_UTF8="${LOCALE}.UTF-8" ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "${FEATURE_ID}: install.sh must be run as root." >&2
  exit 1
fi

# localedef itself ships in libc-bin and is present on a bare Debian/Ubuntu image; the charmaps and
# locale sources it needs come from the 'locales' package, so that directory, not the command, is
# what decides whether 'locales' still needs installing.
if [ ! -d '/usr/share/i18n/charmaps' ]; then
  if ! command -v 'apt-get' >/dev/null 2>&1; then
    echo "${FEATURE_ID}: the 'locales' package is required but apt-get is unavailable to install it." >&2
    echo "${FEATURE_ID}: install 'locales' yourself, or use a Debian/Ubuntu-based image." >&2
    exit 1
  fi
  apt-get update -y
  DEBIAN_FRONTEND='noninteractive' apt-get install -y --no-install-recommends 'locales'
  rm -rf /var/lib/apt/lists/*
fi

# Rejected explicitly, rather than left to fail the lookup below: /usr/share/i18n/SUPPORTED lists
# some locales' UTF-8 form under the plain name (e.g. "ja_JP.UTF-8"), so a value that already
# includes the suffix could otherwise coincidentally match a real SUPPORTED entry instead of being
# caught as user error.
case "${LOCALE}" in
  *[Uu][Tt][Ff]?8*)
    echo "${FEATURE_ID}: '${LOCALE}' must not include the '.UTF-8' suffix; it is appended automatically." >&2
    exit 1
    ;;
esac

# Checked against /usr/share/i18n/SUPPORTED (rather than left to localedef) so that a typo fails
# with a message that names the feature and the value it rejected, instead of localedef's
# unprefixed, easy-to-miss error. Most locales are listed there with the codeset spelled out in the
# name (e.g. "ja_JP.UTF-8 UTF-8", alongside "ja_JP.EUC-JP EUC-JP"), but locales with only ever one
# encoding are listed under the plain name instead (e.g. "aa_ER UTF-8", with no "aa_ER.UTF-8" line
# anywhere in the file), so both forms have to be checked.
if ! grep -qFx "${LOCALE_UTF8} UTF-8" '/usr/share/i18n/SUPPORTED' \
    && ! grep -qFx "${LOCALE} UTF-8" '/usr/share/i18n/SUPPORTED'; then
  echo "${FEATURE_ID}: '${LOCALE}' is not a supported UTF-8 locale (checked /usr/share/i18n/SUPPORTED for '${LOCALE_UTF8} UTF-8' and '${LOCALE} UTF-8')." >&2
  exit 1
fi

# Registered in /etc/locale.gen (rather than generated with a bare localedef call) so the locale
# survives a later argument-less locale-gen run, e.g. from a 'locales' package reinstall or
# upgrade, instead of being wiped the next time something regenerates the default locale set.
#
# The entry is appended directly instead of passed as a locale-gen argument: Debian's locale-gen
# only reads /etc/locale.gen and otherwise ignores its arguments, while Ubuntu's additionally
# accepts a single locale name on the command line. Writing the entry ourselves works the same way
# on both.
if ! grep -qFx "${LOCALE_UTF8} UTF-8" '/etc/locale.gen'; then
  printf '%s UTF-8\n' "${LOCALE_UTF8}" >> '/etc/locale.gen'
fi
locale-gen
# Only LANG is set, here and in the profile.d snippet below. LANG has the lowest precedence of the
# locale variables, which leaves LC_ALL and LANGUAGE free for a single process to override it with,
# e.g. an AI agent that should get English command output while interactive shells use this locale.
# LANGUAGE is not needed for a base language fallback either: gettext already falls back from
# "de_AT.UTF-8" to "de_AT" and then "de" on its own.
update-locale LANG="${LOCALE_UTF8}"

# update-locale alone only takes effect through PAM on login, and not at all for a login shell
# started outside PAM (e.g. VS Code Server). The profile.d snippet covers those cases too.
#
# Set unconditionally, not just when unset: Debian/Ubuntu base images already export LANG (usually
# C.UTF-8) as part of the image itself, so a guard that only fills in an empty value would never
# fire. There is no way to tell that inherited default apart from a value the user actually wants
# kept, so the option this feature was given is treated as the deciding one.
cat > "/etc/profile.d/${FEATURE_ID}.sh" <<EOF
export LANG='${LOCALE_UTF8}'
EOF
chmod 644 "/etc/profile.d/${FEATURE_ID}.sh"

echo "${FEATURE_ID}: generated locale ${LOCALE_UTF8}"

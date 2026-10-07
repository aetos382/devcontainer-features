#!/bin/sh
set -eu

FEATURE_ID='apt-mirror'

# Option values reach install.sh as uppercased environment variables.
MIRROR="${MIRROR:-}"
SECURITY_MIRROR="${SECURITY_MIRROR:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "${FEATURE_ID}: install.sh must be run as root." >&2
  exit 1
fi

# $1: option name, $2: its value. An empty value means "leave this archive alone" and is fine.
validate_url() {
  [ -n "${2}" ] || return 0

  case "${2}" in
    http://* | https://*) ;;
    *)
      echo "${FEATURE_ID}: '${1}' must start with http:// or https:// (got '${2}')." >&2
      exit 1
      ;;
  esac

  # The value lands verbatim in the URIs field of a deb822 file, where whitespace separates one URI
  # from the next: a space would silently turn one URI into two. Control characters, a newline
  # included, have no place in a URL either.
  case "${2}" in
    *[[:space:][:cntrl:]]*)
      echo "${FEATURE_ID}: '${1}' must not contain whitespace or control characters (got '${2}')." >&2
      exit 1
      ;;
  esac
}

# Both are checked before the early exit below, so that a bad value is reported even when the other
# option is empty.
validate_url 'mirror' "${MIRROR}"
validate_url 'security_mirror' "${SECURITY_MIRROR}"

if [ -z "${MIRROR}" ] && [ -z "${SECURITY_MIRROR}" ]; then
  echo "${FEATURE_ID}: 'mirror' and 'security_mirror' are empty; leaving apt sources unchanged."
  exit 0
fi

# Which hosts a distribution's sources name by default is that distribution's own business, not
# apt's, so each supported one is spelled out here. The patterns are extended regular expressions
# without the scheme; the path is part of them because Debian serves both archives from one host.
#
# os-release(5) allows its values to be quoted, so ID="ubuntu" is as valid as ID=ubuntu. Sourcing
# the file in a subshell is the parsing method that spec prescribes, and it keeps the variables it
# defines out of this script.
OS_ID=''
if [ -r '/etc/os-release' ]; then
  # shellcheck source=/dev/null
  OS_ID="$(. '/etc/os-release' && printf '%s' "${ID:-}")"
fi
case "${OS_ID}" in
  ubuntu)
    DEFAULT_ARCHIVE='archive\.ubuntu\.com/ubuntu'
    DEFAULT_ARCHIVE_NAME='archive.ubuntu.com/ubuntu'
    DEFAULT_SECURITY='security\.ubuntu\.com/ubuntu'
    DEFAULT_SECURITY_NAME='security.ubuntu.com/ubuntu'
    ;;
  debian)
    DEFAULT_ARCHIVE='deb\.debian\.org/debian'
    DEFAULT_ARCHIVE_NAME='deb.debian.org/debian'
    DEFAULT_SECURITY='deb\.debian\.org/debian-security'
    DEFAULT_SECURITY_NAME='deb.debian.org/debian-security'
    ;;
  *)
    echo "${FEATURE_ID}: this feature only supports Ubuntu and Debian images (ID in /etc/os-release is '${OS_ID}')." >&2
    exit 1
    ;;
esac

# The rewritten URI always ends in a slash of this script's own, so one in the option value would
# come out doubled.
MIRROR="${MIRROR%/}"
SECURITY_MIRROR="${SECURITY_MIRROR%/}"

# Escapes characters that are special inside a sed replacement -- '&' (the whole match), '\', and
# the '#' delimiter used below -- so a mirror URL can't break the substitution or be mangled by it.
# The delimiter is '#' because the pattern itself contains '|'.
escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\&#]/\\&/g'
}

# A URI in a deb822 file ends at whitespace or at the end of the line. Requiring that end is what
# keeps ".../debian" from also matching ".../debian-security". The scheme is part of the pattern
# too: without it, a mirror whose own hostname ends in a default host (a subdomain mirror is one
# plausible way to get that) would be mistaken for the default on a second run of this feature.
# $1: host-and-path pattern
uri_pattern() {
  printf '%s' "https?://${1}/?([[:space:]]|\$)"
}

# grep exits 1 for "no match" but 2 for a read error; conflating the two would silently treat an
# unreadable sources file as one that simply needs no rewriting.
# $1: file, $2: host-and-path pattern
names_default() {
  MATCH_RC=0
  grep -qE "$(uri_pattern "${2}")" "${1}" || MATCH_RC=$?
  case "${MATCH_RC}" in
    0) return 0 ;;
    1) return 1 ;;
    *)
      echo "${FEATURE_ID}: failed to read ${1} (grep exited ${MATCH_RC})." >&2
      exit 1
      ;;
  esac
}

# Whether a whole URI in the file equals the given URL, with or without a trailing slash. Comparing
# whole fields, rather than searching for a substring, keeps ".../debian" from being found inside
# ".../debian-security". The URL travels through the environment because awk -v would interpret
# backslash escapes in it.
# $1: file, $2: URL without a trailing slash
names_url() {
  MATCH_RC=0
  WANTED_URL="${2}" awk '
    { for (i = 1; i <= NF; i++) if ($i == ENVIRON["WANTED_URL"] || $i == ENVIRON["WANTED_URL"] "/") found = 1 }
    END { exit found ? 0 : 1 }
  ' "${1}" || MATCH_RC=$?
  case "${MATCH_RC}" in
    0) return 0 ;;
    1) return 1 ;;
    *)
      echo "${FEATURE_ID}: failed to read ${1} (awk exited ${MATCH_RC})." >&2
      exit 1
      ;;
  esac
}

# -E keeps the pattern identical to the grep in names_default and avoids '\?', which basic regular
# expressions only have as a GNU extension.
# $1: file, $2: host-and-path pattern, $3: URL without a trailing slash
replace_default() {
  sed -E -i -e "s#$(uri_pattern "${2}")#$(escape_sed_replacement "${3}")/\\1#g" "${1}" || {
    echo "${FEATURE_ID}: failed to rewrite ${1}." >&2
    exit 1
  }
}

# Only the deb822-style *.sources files are rewritten, which is where every supported release keeps
# its default sources. The one-line format (sources.list, sources.list.d/*.list) is the default
# only on releases this feature is not tested on, so it is left alone rather than rewritten
# untested.
#
# For each archive an option asked for, a file either still names the default (rewrite it), or
# already names the requested URL (nothing to do; seen on a second run with the same value, and on
# a base image whose author configured it), or names something else (handled after the loop).
CHANGED=0
ARCHIVE_IN_EFFECT=0
SECURITY_IN_EFFECT=0
for FILE in /etc/apt/sources.list.d/*.sources; do
  [ -f "${FILE}" ] || continue
  REWROTE=0

  # The security archive goes first only so that the two log lines read in a stable order; the
  # patterns cannot match each other's URIs.
  if [ -n "${SECURITY_MIRROR}" ]; then
    if names_default "${FILE}" "${DEFAULT_SECURITY}"; then
      replace_default "${FILE}" "${DEFAULT_SECURITY}" "${SECURITY_MIRROR}"
      REWROTE=1
      SECURITY_IN_EFFECT=1
    elif names_url "${FILE}" "${SECURITY_MIRROR}"; then
      SECURITY_IN_EFFECT=1
    fi
  fi

  if [ -n "${MIRROR}" ]; then
    if names_default "${FILE}" "${DEFAULT_ARCHIVE}"; then
      replace_default "${FILE}" "${DEFAULT_ARCHIVE}" "${MIRROR}"
      REWROTE=1
      ARCHIVE_IN_EFFECT=1
    elif names_url "${FILE}" "${MIRROR}"; then
      ARCHIVE_IN_EFFECT=1
    fi
  fi

  if [ "${REWROTE}" -eq 1 ]; then
    CHANGED=1
    echo "${FEATURE_ID}: rewrote apt sources in ${FILE}"
  fi
done

# Reached when the sources name neither the default nor the requested URL: after an earlier run of
# this feature with another value, on a base image configured by other means, on Ubuntu for arm64
# (ports.ubuntu.com), or with one-line sources. Not an error, since the image may be set up that
# way on purpose, but the requested value is not in effect, so it must not pass silently.
# $1: option name, $2: its value, $3: the default it looked for
warn_not_in_effect() {
  echo "${FEATURE_ID}: no apt source for ${3} found in /etc/apt/sources.list.d/*.sources; '${1}' (${2}) is NOT in effect." >&2
}
if [ -n "${MIRROR}" ] && [ "${ARCHIVE_IN_EFFECT}" -eq 0 ]; then
  warn_not_in_effect 'mirror' "${MIRROR}" "${DEFAULT_ARCHIVE_NAME}"
fi
if [ -n "${SECURITY_MIRROR}" ] && [ "${SECURITY_IN_EFFECT}" -eq 0 ]; then
  warn_not_in_effect 'security_mirror' "${SECURITY_MIRROR}" "${DEFAULT_SECURITY_NAME}"
fi

if [ "${CHANGED}" -eq 0 ]; then
  echo "${FEATURE_ID}: nothing to change in apt sources."
  exit 0
fi

# Verifies the mirror actually works now, rather than leaving that discovery to whichever later
# feature happens to run apt-get first with a much less obvious error. Error-Mode=any is needed
# because apt-get update's default mode downgrades a failed fetch to a warning whenever it still
# has an older cached index to fall back on.
if ! apt-get -o 'APT::Update::Error-Mode=any' update -y; then
  echo "${FEATURE_ID}: apt-get update failed after rewriting apt sources (mirror='${MIRROR}', security_mirror='${SECURITY_MIRROR}'). Check that each is reachable and mirrors this distribution/release." >&2
  exit 1
fi

# The update above only served as a check. Later features run their own before installing
# anything, so keeping its lists would just add weight to this layer.
rm -rf /var/lib/apt/lists/*

# Names no URL: one of the two options may have been left without effect, with the warning above.
echo "${FEATURE_ID}: the rewritten apt sources passed apt-get update."

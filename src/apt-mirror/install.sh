#!/bin/sh
set -eu

FEATURE_ID='apt-mirror'

# Option values reach install.sh as uppercased environment variables.
MIRROR="${MIRROR:-}"
INCLUDE_SECURITY="${INCLUDE_SECURITY:-false}"

if [ "$(id -u)" -ne 0 ]; then
  echo "${FEATURE_ID}: install.sh must be run as root." >&2
  exit 1
fi

# The CLI does not enforce an option's type: a typo such as "True" in devcontainer.json arrives here
# as written, and the comparison with 'true' further down would quietly treat it as false. Checked
# before the early exit below, so that the typo is reported even while 'mirror' is still empty.
case "${INCLUDE_SECURITY}" in
  true | false) ;;
  *)
    echo "${FEATURE_ID}: 'include_security' must be true or false (got '${INCLUDE_SECURITY}')." >&2
    exit 1
    ;;
esac

if [ -z "${MIRROR}" ]; then
  echo "${FEATURE_ID}: 'mirror' option is empty; leaving apt sources unchanged."
  exit 0
fi

case "${MIRROR}" in
  http://* | https://*) ;;
  *)
    echo "${FEATURE_ID}: 'mirror' must start with http:// or https:// (got '${MIRROR}')." >&2
    exit 1
    ;;
esac

# The value lands verbatim in apt sources, where whitespace separates fields: in deb822's URIs field
# a space would silently turn one URI into two, and in a one-line entry it would shift the suite and
# components. Control characters, a newline included, have no place in a URL either.
case "${MIRROR}" in
  *[[:space:][:cntrl:]]*)
    echo "${FEATURE_ID}: 'mirror' must not contain whitespace or control characters (got '${MIRROR}')." >&2
    exit 1
    ;;
esac

# archive.ubuntu.com / security.ubuntu.com are Ubuntu-specific, so a non-Ubuntu image (Debian
# included) is refused outright rather than silently matching nothing further down.
#
# os-release(5) allows its values to be quoted, so ID="ubuntu" is as valid as ID=ubuntu. Sourcing
# the file in a subshell is the parsing method that spec prescribes, and it keeps the variables it
# defines out of this script.
# shellcheck source=/dev/null
if [ ! -r '/etc/os-release' ] || ! (. '/etc/os-release' && [ "${ID:-}" = 'ubuntu' ]); then
  echo "${FEATURE_ID}: this feature only supports Ubuntu-based images (expected ID=ubuntu in /etc/os-release)." >&2
  exit 1
fi

# The sources follow the replaced ".../ubuntu" with a slash of their own (as in
# "http://archive.ubuntu.com/ubuntu/"), so a trailing slash here would come out doubled.
MIRROR="${MIRROR%/}"

# Escapes characters that are special inside a sed replacement -- '&' (the whole match), '\', and
# the '|' delimiter used below -- so a mirror URL can't break the substitution or be mangled by it.
escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\&|]/\\&/g'
}
MIRROR_ESCAPED="$(escape_sed_replacement "${MIRROR}")"

# grep exits 1 for "no match" but 2 for a read error; conflating the two would silently treat an
# unreadable sources file as one that simply needs no rewriting.
# $1: file, remaining arguments: grep options and the pattern
file_matches() {
  MATCH_FILE="${1}"
  shift
  MATCH_RC=0
  grep -q "$@" "${MATCH_FILE}" || MATCH_RC=$?
  case "${MATCH_RC}" in
    0) return 0 ;;
    1) return 1 ;;
    *)
      echo "${FEATURE_ID}: failed to read ${MATCH_FILE} (grep exited ${MATCH_RC})." >&2
      exit 1
      ;;
  esac
}

matches_default_host() {
  file_matches "${1}" -E "https?://${2}\.ubuntu\.com/ubuntu"
}

# The scheme is part of the pattern, not just the host: without it, a mirror whose own hostname
# ends in "archive.ubuntu.com" (a subdomain mirror is one plausible way to get that) would be
# mistaken for the default host on a second run of this feature. -E keeps the pattern identical to
# the grep in matches_default_host and avoids '\?', which basic regular expressions only have as a
# GNU extension.
replace_default_host() {
  sed -E -i -e "s|https?://${2}\.ubuntu\.com/ubuntu|${MIRROR_ESCAPED}|g" "${1}" || {
    echo "${FEATURE_ID}: failed to rewrite ${1}." >&2
    exit 1
  }
}

# Only the deb822-style *.sources files are rewritten, which is where every supported Ubuntu release
# keeps its default sources. The one-line format (sources.list, sources.list.d/*.list) is the
# default only on releases this feature is not tested on, so it is left alone rather than rewritten
# untested.
CHANGED=0
ALREADY_SET=0
for FILE in /etc/apt/sources.list.d/*.sources; do
  [ -f "${FILE}" ] || continue

  # Seen on a second run of this feature with the same mirror, and on a base image whose author
  # already configured it. -F: the mirror is a literal string, not a pattern.
  if file_matches "${FILE}" -F -e "${MIRROR}/"; then
    ALREADY_SET=1
  fi

  REWRITE_ARCHIVE=0
  if matches_default_host "${FILE}" 'archive'; then
    REWRITE_ARCHIVE=1
  fi

  REWRITE_SECURITY=0
  if [ "${INCLUDE_SECURITY}" = 'true' ] && matches_default_host "${FILE}" 'security'; then
    REWRITE_SECURITY=1
  fi

  if [ "${REWRITE_ARCHIVE}" -eq 0 ] && [ "${REWRITE_SECURITY}" -eq 0 ]; then
    continue
  fi

  if [ "${REWRITE_ARCHIVE}" -eq 1 ]; then
    replace_default_host "${FILE}" 'archive'
  fi
  if [ "${REWRITE_SECURITY}" -eq 1 ]; then
    replace_default_host "${FILE}" 'security'
  fi

  CHANGED=1
  echo "${FEATURE_ID}: rewrote apt sources in ${FILE}"
done

if [ "${CHANGED}" -eq 0 ]; then
  # The requested mirror is in effect, so there is nothing to warn about.
  if [ "${ALREADY_SET}" -eq 1 ]; then
    echo "${FEATURE_ID}: apt sources already point at ${MIRROR}; nothing to change."
    exit 0
  fi

  # Reached when the sources name neither the default hosts nor the requested mirror: after an
  # earlier run of this feature with another mirror, on a base image configured by other means, on
  # arm64 (ports.ubuntu.com), or with one-line sources. Not an error, since the image may be set up
  # that way on purpose, but the requested mirror is not in effect, so it must not pass silently.
  echo "${FEATURE_ID}: no default Ubuntu apt sources (archive.ubuntu.com, security.ubuntu.com) found in /etc/apt/sources.list.d/*.sources; leaving apt sources unchanged. '${MIRROR}' is NOT in effect." >&2
  exit 0
fi

# Verifies the mirror actually works now, rather than leaving that discovery to whichever later
# feature happens to run apt-get first with a much less obvious error. Error-Mode=any is needed
# because apt-get update's default mode downgrades a failed fetch to a warning whenever it still
# has an older cached index to fall back on.
if ! apt-get -o 'APT::Update::Error-Mode=any' update -y; then
  echo "${FEATURE_ID}: apt-get update failed after switching to '${MIRROR}'. Check that the mirror is reachable and mirrors this distribution/release." >&2
  exit 1
fi

# The update above only served as a check. Later features run their own before installing
# anything, so keeping its lists would just add weight to this layer.
rm -rf /var/lib/apt/lists/*

echo "${FEATURE_ID}: switched apt sources to ${MIRROR}"

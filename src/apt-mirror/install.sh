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

# sources.list has no slash after the host while deb822's URIs field does, so a trailing slash here
# would leave behind a stray or a doubled one depending on which file it lands in.
MIRROR="${MIRROR%/}"

# Escapes characters that are special inside a sed replacement -- '&' (the whole match), '\', and
# the '|' delimiter used below -- so a mirror URL can't break the substitution or be mangled by it.
escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\&|]/\\&/g'
}
MIRROR_ESCAPED="$(escape_sed_replacement "${MIRROR}")"

# grep exits 1 for "no match" but 2 for a read error; conflating the two would silently treat an
# unreadable sources file as one that simply needs no rewriting.
matches_default_host() {
  MATCH_RC=0
  grep -qE "https?://${2}\.ubuntu\.com/ubuntu" "${1}" || MATCH_RC=$?
  case "${MATCH_RC}" in
    0) return 0 ;;
    1) return 1 ;;
    *)
      echo "${FEATURE_ID}: failed to read ${1} (grep exited ${MATCH_RC})." >&2
      exit 1
      ;;
  esac
}

# The scheme is part of the pattern, not just the host: without it, a mirror whose own hostname
# ends in "archive.ubuntu.com" (a subdomain mirror is one plausible way to get that) would be
# mistaken for the default host on a second run of this feature.
replace_default_host() {
  sed -i -e "s|https\?://${2}\.ubuntu\.com/ubuntu|${MIRROR_ESCAPED}|g" "${1}" || {
    echo "${FEATURE_ID}: failed to rewrite ${1}." >&2
    exit 1
  }
}

# Covers the classic one-line format (sources.list and the sources.list.d/*.list fragments apt also
# reads) as well as the deb822-style *.sources files that Ubuntu 24.04+ ships by default; the
# mirror host appears as a plain substring in all of them, so one substitution fits each.
CHANGED=0
for FILE in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
  [ -f "${FILE}" ] || continue

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
  echo "${FEATURE_ID}: no default Ubuntu apt sources found in /etc/apt/sources.list or /etc/apt/sources.list.d/; leaving apt sources unchanged." >&2
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

echo "${FEATURE_ID}: switched apt sources to ${MIRROR}"

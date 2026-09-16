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
if [ ! -r '/etc/os-release' ] || ! grep -qE '^ID=ubuntu$' '/etc/os-release'; then
  echo "${FEATURE_ID}: this feature only supports Ubuntu-based images (expected ID=ubuntu in /etc/os-release)." >&2
  exit 1
fi

# Strips a trailing slash so the sed replacements below don't leave a doubled slash behind,
# whichever of the two files' own trailing-slash conventions (sources.list has none after the
# host, deb822's URIs field has one) it lands next to.
MIRROR="${MIRROR%/}"

# Escapes characters that are special inside a sed replacement -- '&' (the whole match), '\', and
# the '|' delimiter used below -- so a mirror URL can't break the substitution or be mangled by it.
escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\&|]/\\&/g'
}
MIRROR_ESCAPED="$(escape_sed_replacement "${MIRROR}")"

# Covers both the classic one-line sources.list and the deb822-style *.sources files that
# Ubuntu 24.04+ ships by default (/etc/apt/sources.list.d/ubuntu.sources); either way the mirror
# host appears as a plain substring, so the same substitution works on both formats.
#
# The scheme is part of every pattern below, not just archive\.ubuntu\.com: without it, a mirror
# whose own hostname ends in "archive.ubuntu.com" (a subdomain mirror is one plausible way to get
# that) would be mistaken for the default host on a second run of this feature.
CHANGED=0
for FILE in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources; do
  [ -f "${FILE}" ] || continue
  FILE_CHANGED=0
  if grep -qE 'https?://archive\.ubuntu\.com/ubuntu' "${FILE}"; then
    sed -i -e "s|https\?://archive\.ubuntu\.com/ubuntu|${MIRROR_ESCAPED}|g" "${FILE}"
    FILE_CHANGED=1
  fi
  if [ "${INCLUDE_SECURITY}" = 'true' ] && grep -qE 'https?://security\.ubuntu\.com/ubuntu' "${FILE}"; then
    sed -i -e "s|https\?://security\.ubuntu\.com/ubuntu|${MIRROR_ESCAPED}|g" "${FILE}"
    FILE_CHANGED=1
  fi
  if [ "${FILE_CHANGED}" -eq 1 ]; then
    CHANGED=1
    echo "${FEATURE_ID}: rewrote apt sources in ${FILE}"
  fi
done

if [ "${CHANGED}" -eq 0 ]; then
  echo "${FEATURE_ID}: no known Ubuntu apt sources found (looked for archive.ubuntu.com in /etc/apt/sources.list and /etc/apt/sources.list.d/*.sources)." >&2
  exit 1
fi

# Verifies the mirror actually works now, rather than leaving that discovery to whichever later
# feature happens to run apt-get first with a much less obvious error. Error-Mode=any is required
# for that: apt-get update's default mode treats a failed fetch as a warning (exit 0) whenever it
# still has an older cached index to fall back on, which every suite here does right after the sed
# above ran on a freshly rewritten but still-cached sources file.
if ! apt-get -o APT::Update::Error-Mode=any update -y; then
  echo "${FEATURE_ID}: apt-get update failed after switching to '${MIRROR}'; check that it is reachable and mirrors this distribution/release." >&2
  exit 1
fi

echo "${FEATURE_ID}: switched apt sources to ${MIRROR}"

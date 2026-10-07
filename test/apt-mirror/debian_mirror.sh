#!/bin/bash
# Ensures that, on Debian, mirror replaces deb.debian.org/debian and nothing else. Debian serves
# its security archive from the same host under /debian-security, so a replacement that matched
# too eagerly would send security updates to a mirror path that does not exist.
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'the archive now points at the requested mirror' bash -c \
  'grep -qx "URIs: http://ftp.jp.debian.org/debian/" /etc/apt/sources.list.d/debian.sources'
check 'no reference to the default Debian archive remains' bash -c \
  '! grep -qE "https?://deb\.debian\.org/debian/?$" /etc/apt/sources.list.d/debian.sources'
check 'the security archive is left untouched' bash -c \
  'grep -qx "URIs: http://deb.debian.org/debian-security" /etc/apt/sources.list.d/debian.sources'
# Runs before the apt-get update below, which would fetch the lists all over again.
# shellcheck disable=SC2016 # expanded by the inner bash, not here
check 'the package lists fetched to verify the mirror were removed' bash -c \
  '[ -z "$(ls -A /var/lib/apt/lists)" ]'
check 'apt-get update works against the new mirror' apt-get update -y

reportResults

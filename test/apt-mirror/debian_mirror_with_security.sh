#!/bin/bash
# Ensures that, on Debian, mirror and security_mirror each replace their own archive with their own
# URL. The two differ on purpose: Debian's security archive is a separate one that an ordinary
# mirror need not carry, which is the reason the feature takes two URLs rather than one.
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'the archive now points at the requested mirror' bash -c \
  'grep -qx "URIs: http://ftp.jp.debian.org/debian/" /etc/apt/sources.list.d/debian.sources'
check 'the security archive now points at the requested security mirror' bash -c \
  'grep -qx "URIs: http://security.debian.org/debian-security/" /etc/apt/sources.list.d/debian.sources'
check 'no reference to the default Debian host remains' bash -c \
  '! grep -qE "https?://deb\.debian\.org" /etc/apt/sources.list.d/debian.sources'
check 'apt-get update works against both' apt-get update -y

reportResults

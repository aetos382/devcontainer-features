#!/bin/bash
# Ensures that include_security additionally replaces security.ubuntu.com with the requested
# mirror, and that apt-get still works against it. The scenario's mirror value carries a trailing
# slash, which the doubled-slash check below verifies was stripped: a server that tolerates '//'
# would let that regression reach apt-get update unnoticed.
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'no reference to the default Ubuntu archive host remains' bash -c \
  '! grep -qrE "https?://(archive|security)\.ubuntu\.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
check 'apt sources now point at the requested mirror' bash -c \
  'grep -qrF "jp.archive.ubuntu.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
check 'the trailing slash of the mirror value was stripped' bash -c \
  '! grep -qrF "jp.archive.ubuntu.com/ubuntu//" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
check 'no backup files are left behind once the mirror is verified' bash -c \
  '! ls /etc/apt/sources.list.apt-mirror.bak /etc/apt/sources.list.d/*.apt-mirror.bak >/dev/null 2>&1'
check 'apt-get update works against the new mirror' apt-get update -y

reportResults

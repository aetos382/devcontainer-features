#!/bin/bash
# Ensures that mirror replaces archive.ubuntu.com but, without include_security, leaves
# security.ubuntu.com pointed at Canonical's own server -- and that apt-get still works against
# the new mirror.
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'no reference to the default Ubuntu archive host remains' bash -c \
  '! grep -qrE "https?://archive\.ubuntu\.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
check 'security.ubuntu.com is left untouched' bash -c \
  'grep -qrE "https?://security\.ubuntu\.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
check 'apt sources now point at the requested mirror' bash -c \
  'grep -qrF "jp.archive.ubuntu.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
check 'no backup files are left behind once the mirror is verified' bash -c \
  '! ls /etc/apt/sources.list.apt-mirror.bak /etc/apt/sources.list.d/*.apt-mirror.bak >/dev/null 2>&1'
check 'apt-get update works against the new mirror' apt-get update -y

reportResults
